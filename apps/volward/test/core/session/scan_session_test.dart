import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/core/session/scan_session.dart';
import 'package:volward/core/session/snapshot_persistence.dart';
import 'package:volward/scan_root_record.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/snapshot_cache.dart';
import 'package:volward/volward_session.dart';

import '../../support/cached_snapshot.dart';

void main() {
  test('scan state is owned by ScanSession and exposed through Session', () {
    final session = VolwardSession.test();
    final scan = session.scanSessionForTest;

    scan.setScanRootsForTest(['/old']);
    scan.setLastSnapshotForTest(ScanSnapshotState.fromWire(_snapshot('old')));

    expect(session.scanRoots, ['/old']);
    expect(session.lastSnapshot?.snapshotId, 'old');
    expect(identical(session.scanSessionForTest, scan), isTrue);
  });

  test('switching roots keeps only the newest owner state', () async {
    final session = VolwardSession.test();
    final scan = session.scanSessionForTest;

    scan.setScanRootsForTest(['/old']);
    session.scanRunnerForTest = (_, _) async => null;
    await scan.switchRootForTest('/new');

    expect(scan.currentRoot, '/new');
    expect(session.scanRoots, ['/new']);
    expect(scan.lastSnapshot, isNull);
  });

  test(
    'SnapshotPersistence writes and restores the session root state',
    () async {
      final root = await Directory.systemTemp.createTemp('volward-scan-state-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/session.json');
      final persistence = SnapshotPersistence(
        stateFile: () async => file,
        readState: (file) => file.readAsString(),
        writeState: (file, value) => file.writeAsString(value),
      );

      await persistence.persist({
        'scan_roots': ['/Users/test/Downloads'],
        'last_custom_roots': ['/Users/test/Downloads'],
      });
      final restored = await persistence.load();

      expect(restored?['scan_roots'], ['/Users/test/Downloads']);
    },
  );

  test('ScanSession owns notifications consumed by Session', () {
    final session = VolwardSession.test();
    final scan = session.scanSessionForTest;
    var scanNotifications = 0;
    var sessionNotifications = 0;
    scan.addListener(() => scanNotifications++);
    session.addListener(() => sessionNotifications++);

    scan.primeTransientScanStateForTest(scanning: true, openScanPorts: false);
    scan.cancelScan();

    expect(scanNotifications, 1);
    expect(sessionNotifications, 1);
  });

  test('ScanSession immediate notifications bypass Session batching', () {
    final session = VolwardSession.test();
    final scan = session.scanSessionForTest;
    var sessionNotifications = 0;
    session.addListener(() => sessionNotifications++);

    session.beginNotificationBatchForTest();
    scan.setSnapshotForTest(ScanSnapshotState.fromWire(_snapshot('batched')));
    expect(sessionNotifications, 0);

    scan.primeTransientScanStateForTest(scanning: true, openScanPorts: false);
    scan.cancelScan();
    expect(sessionNotifications, 1);

    session.endNotificationBatchForTest();
    expect(sessionNotifications, 2);
  });

  test('SnapshotPersistence retries after a failed load', () async {
    var attempts = 0;
    final persistence = SnapshotPersistence(
      stateFile: () async => null,
      readState: (_) async => '{}',
      writeState: (_, _) async {},
    );

    await expectLater(
      persistence.loadIfNeeded(() async {
        attempts++;
        throw const FileSystemException('temporary read failure');
      }),
      throwsA(isA<FileSystemException>()),
    );
    await persistence.loadIfNeeded(() async {
      attempts++;
    });

    expect(attempts, 2);
    expect(persistence.loaded, isTrue);
  });

  test('ScanSession rejects a restore that races a newer root', () async {
    final temp = await Directory.systemTemp.createTemp(
      'volward-scan-owner-stale',
    );
    addTearDown(() {
      SnapshotCache.cacheDirForTest = null;
      temp.deleteSync(recursive: true);
    });
    SnapshotCache.cacheDirForTest = temp;
    writeCachedSnapshot(
      cacheDir: temp,
      manifestName: 'slow-restore',
      snapshotName: 'slow-restore',
      root: '/slow-restore',
      snapshotId: 'slow-restore-scan',
      scannedAtMs: 1700000000900,
      sizeBytes: 512,
      reclaimableBytes: 7,
    );

    final restoreStarted = Completer<void>();
    final session = VolwardSession.test();
    final scan = session.scanSessionForTest;
    scan.treatAsIndexApiForTest = true;
    scan.scanRunnerForTest = (_, _) async => null;
    scan.setScanRootsForTest(['/slow-restore']);
    scan.restoreDelayForTest = const Duration(milliseconds: 50);
    scan.restoreDelayStartedForTest = () {
      if (!restoreStarted.isCompleted) restoreStarted.complete();
    };

    final staleRestore = scan.restoreCachedSnapshotForTest();
    await restoreStarted.future;
    await scan.switchRootForTest('/fast');
    await staleRestore;

    expect(scan.currentRoot, '/fast');
    expect(scan.lastSnapshot?.tree?.path, isNot('/slow-restore'));
  });

  test('ScanSession persists a successful pause checkpoint', () async {
    final temp = await Directory.systemTemp.createTemp(
      'volward-scan-owner-pause',
    );
    addTearDown(() {
      SnapshotCache.cacheDirForTest = null;
      temp.deleteSync(recursive: true);
    });
    SnapshotCache.cacheDirForTest = temp;
    const root = '/Users/test/PausedOwner';
    final checkpoint = File('${temp.path}/owner-pause.index.json');
    await checkpoint.writeAsString('{}');
    final store = ScanRootRecordStore(temp);
    late ScanSession scan;
    final session = VolwardSession.test()
      ..rootRecordStoreForTest = store
      ..setScanRoots([root]);
    scan = session.scanSessionForTest
      ..primeTransientScanStateForTest(scanning: true, openScanPorts: false)
      ..pauseRequestForTest = (_, _) {
        scheduleMicrotask(scan.clearTransientScanStateForTest);
        return checkpoint.path;
      }
      ..pauseErrorForTest = () => null;

    expect(await scan.pauseCurrentScanForSwitch(), isTrue);

    final record = await store.load(root);
    expect(record?.status, ScanRootStatus.paused);
    expect(record?.checkpointPath, checkpoint.path);
  });
}

Map<String, dynamic> _snapshot(String id) => {
  'snapshot_id': id,
  'stats': {'scan_state': 'Done'},
  'tree': {
    'path': '/old',
    'name': 'old',
    'is_dir': true,
    'size_bytes': 0,
    'allocated_bytes': 0,
    'children': <dynamic>[],
  },
  'entries': <dynamic>[],
};
