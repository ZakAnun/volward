import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/snapshot_cache.dart';
import 'package:volward/volward_session.dart';

import 'support/cached_snapshot.dart';

ScanSnapshotState snapshotForRoot(String id, String root) {
  return ScanSnapshotState.fromWire({
    'snapshot_id': id,
    'tree': {
      'path': root,
      'name': root.split('/').last,
      'is_dir': true,
      'children': const [],
    },
    'entries': const [],
    'stats': {'scan_state': 'Done', 'files_in_snapshot': 1},
  });
}

void main() {
  test(
    'restore reuses in-memory engine index without hitting disk load',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-reuse-engine',
      );
      addTearDown(() {
        SnapshotCache.cacheDirForTest = null;
        temp.deleteSync(recursive: true);
      });
      SnapshotCache.cacheDirForTest = temp;

      const root = '/Users/test/Downloads';
      writeCachedSnapshot(
        cacheDir: temp,
        manifestName: 'downloads',
        snapshotName: 'downloads',
        root: root,
        snapshotId: 'downloads-scan',
        scannedAtMs: 1700000000200,
        sizeBytes: 512,
        reclaimableBytes: 7,
      );

      final session = VolwardSession.test()
        ..treatAsIndexApiForTest = true
        ..setScanRoots([root])
        ..engineIndexSnapshotForTest = snapshotForRoot('engine-scan', root)
        ..indexLoadAsyncResultsForTest = ['error:should-not-load'];

      final restored = await session.restoreCachedSnapshotForTest();
      expect(restored, isTrue);
      expect(session.lastSnapshot?.snapshotId, 'engine-scan');
      expect(session.startIndexLoadCallsForTest, 0);
    },
  );

  test('restore does not reuse engine index from a different root', () async {
    final temp = await Directory.systemTemp.createTemp('volward-cross-root');
    addTearDown(() {
      SnapshotCache.cacheDirForTest = null;
      temp.deleteSync(recursive: true);
    });
    SnapshotCache.cacheDirForTest = temp;

    const downloads = '/Users/test/Downloads';
    const desktop = '/Users/test/Desktop';
    writeCachedSnapshot(
      cacheDir: temp,
      manifestName: 'desktop',
      snapshotName: 'desktop',
      root: desktop,
      snapshotId: 'desktop-scan',
      scannedAtMs: 1700000000500,
      sizeBytes: 128,
      reclaimableBytes: 0,
    );

    var polls = 0;
    final session = VolwardSession.test()
      ..treatAsIndexApiForTest = true
      ..setScanRoots([desktop])
      ..engineIndexSnapshotForTest = snapshotForRoot(
        'downloads-engine',
        downloads,
      )
      ..indexLoadAsyncResultsForTest = ['ok'];
    session.isIndexLoadingForTest = () {
      if (session.startIndexLoadCallsForTest == 0) return false;
      polls++;
      if (polls == 1) {
        session.engineIndexSnapshotForTest = snapshotForRoot(
          'desktop-loaded',
          desktop,
        );
      }
      return polls < 1;
    };

    final restored = await session.restoreCachedSnapshotForTest();
    expect(restored, isTrue);
    expect(session.startIndexLoadCallsForTest, 1);
    expect(session.lastSnapshot?.tree?.path, desktop);
    expect(session.lastSnapshot?.snapshotId, 'desktop-loaded');
  });

  test('restore waits for in-flight load then reuses engine index', () async {
    final temp = await Directory.systemTemp.createTemp('volward-busy-restore');
    addTearDown(() {
      SnapshotCache.cacheDirForTest = null;
      temp.deleteSync(recursive: true);
    });
    SnapshotCache.cacheDirForTest = temp;

    const root = '/Users/test/Desktop';
    writeCachedSnapshot(
      cacheDir: temp,
      manifestName: 'desktop',
      snapshotName: 'desktop',
      root: root,
      snapshotId: 'desktop-scan',
      scannedAtMs: 1700000000300,
      sizeBytes: 128,
      reclaimableBytes: 0,
    );

    var polls = 0;
    final session = VolwardSession.test()
      ..treatAsIndexApiForTest = true
      ..setScanRoots([root])
      ..indexLoadAsyncResultsForTest = ['ok'];
    session.isIndexLoadingForTest = () {
      polls++;
      if (polls >= 3) {
        session.engineIndexSnapshotForTest = snapshotForRoot(
          'desktop-loaded',
          root,
        );
        return false;
      }
      return true;
    };

    final restored = await session.restoreCachedSnapshotForTest();
    expect(restored, isTrue);
    expect(session.lastSnapshot?.snapshotId, 'desktop-loaded');
    expect(session.startIndexLoadCallsForTest, 0);
  });

  test(
    'large cache files get extended timeout beyond 8 seconds',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-large-restore-timeout',
      );
      addTearDown(() {
        SnapshotCache.cacheDirForTest = null;
        temp.deleteSync(recursive: true);
      });
      SnapshotCache.cacheDirForTest = temp;

      const root = '/Users/test/Applications';
      writeCachedSnapshot(
        cacheDir: temp,
        manifestName: 'apps',
        snapshotName: 'apps',
        root: root,
        snapshotId: 'apps-scan',
        scannedAtMs: 1700000000400,
        sizeBytes: 1024,
        reclaimableBytes: 0,
      );
      final snapshotFile = File('${temp.path}/snapshots/apps.json');
      final handle = snapshotFile.openSync(mode: FileMode.write);
      handle.truncateSync(91 * 1024 * 1024);
      handle.closeSync();

      var polls = 0;
      final session = VolwardSession.test()
        ..treatAsIndexApiForTest = true
        ..setScanRoots([root])
        ..indexLoadAsyncResultsForTest = ['ok'];
      session.isIndexLoadingForTest = () {
        if (session.startIndexLoadCallsForTest == 0) return false;
        polls++;
        if (polls == 75) {
          session.engineIndexSnapshotForTest = snapshotForRoot(
            'apps-loaded',
            root,
          );
        }
        return polls < 75;
      };

      final restored = await session.restoreCachedSnapshotForTest();
      expect(restored, isTrue);
      expect(session.lastSnapshot?.snapshotId, 'apps-loaded');
      expect(session.startIndexLoadCallsForTest, 1);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test('oversized cache timeout is not mislabeled as too-large', () async {
    final temp = await Directory.systemTemp.createTemp(
      'volward-oversized-timeout-error',
    );
    addTearDown(() {
      SnapshotCache.cacheDirForTest = null;
      temp.deleteSync(recursive: true);
    });
    SnapshotCache.cacheDirForTest = temp;

    const root = '/Users/test/Home';
    writeCachedSnapshot(
      cacheDir: temp,
      manifestName: 'home',
      snapshotName: 'home',
      root: root,
      snapshotId: 'home-scan',
      scannedAtMs: 1700000000700,
      sizeBytes: 1024,
      reclaimableBytes: 0,
    );
    final snapshotFile = File('${temp.path}/snapshots/home.json');
    final handle = snapshotFile.openSync(mode: FileMode.write);
    handle.truncateSync(200 * 1024 * 1024);
    handle.closeSync();

    final session = VolwardSession.test()
      ..treatAsIndexApiForTest = true
      ..setScanRoots([root])
      ..cacheRestoreTimeoutForTest = const Duration(milliseconds: 50)
      ..indexLoadAsyncResultsForTest = ['ok'];
    session.isIndexLoadingForTest = () {
      if (session.startIndexLoadCallsForTest == 0) return false;
      return true;
    };

    final restored = await session.restoreCachedSnapshotForTest();
    expect(restored, isFalse);
    expect(session.lastError, 'scan-cache-restore-timeout');
    expect(session.lastError, isNot('scan-cache-too-large'));
  });

  test(
    'oversized cache async failure is not mislabeled as too-large',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-oversized-async-error',
      );
      addTearDown(() {
        SnapshotCache.cacheDirForTest = null;
        temp.deleteSync(recursive: true);
      });
      SnapshotCache.cacheDirForTest = temp;

      const root = '/Users/test/Home';
      writeCachedSnapshot(
        cacheDir: temp,
        manifestName: 'home',
        snapshotName: 'home',
        root: root,
        snapshotId: 'home-scan',
        scannedAtMs: 1700000000800,
        sizeBytes: 1024,
        reclaimableBytes: 0,
      );
      final snapshotFile = File('${temp.path}/snapshots/home.json');
      final handle = snapshotFile.openSync(mode: FileMode.write);
      handle.truncateSync(200 * 1024 * 1024);
      handle.closeSync();

      final session = VolwardSession.test()
        ..treatAsIndexApiForTest = true
        ..setScanRoots([root])
        ..indexLoadAsyncResultsForTest = ['error:parse failed'];

      final restored = await session.restoreCachedSnapshotForTest();
      expect(restored, isFalse);
      expect(session.lastError, 'scan-cache-unreadable');
      expect(session.lastError, isNot('scan-cache-too-large'));
    },
  );
}
