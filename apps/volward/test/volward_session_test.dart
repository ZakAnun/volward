import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:volward/scan_preview.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/snapshot_cache.dart';
import 'package:volward/volward_session.dart';

ScanSnapshotState snapshot(String id, String root) =>
    ScanSnapshotState.fromWire({
      'snapshot_id': id,
      'tree': {
        'path': root,
        'name': root.split('/').last,
        'is_dir': true,
        'children': const [],
      },
      'entries': const [],
    });

void writeCachedSnapshot({
  required Directory cacheDir,
  required String manifestName,
  required String snapshotName,
  required String root,
  required String snapshotId,
  required int scannedAtMs,
  required int sizeBytes,
  required int reclaimableBytes,
}) {
  Directory('${cacheDir.path}/manifests').createSync(recursive: true);
  Directory('${cacheDir.path}/snapshots').createSync(recursive: true);
  final snapshotFile = File('${cacheDir.path}/snapshots/$snapshotName.json')
    ..writeAsStringSync(
      jsonEncode({
        'snapshot_id': snapshotId,
        'scanned_at_ms': scannedAtMs,
        'reclaimable_estimate_bytes': reclaimableBytes,
        'entries': const [],
        'tree': {
          'name': root.split('/').last,
          'path': root,
          'is_dir': true,
          'size_bytes': sizeBytes,
          'children': const [],
        },
        'stats': {
          'scan_state': 'Done',
          'files_seen': 4,
          'files_in_snapshot': 4,
        },
      }),
    );
  File('${cacheDir.path}/manifests/$manifestName.json').writeAsStringSync(
    jsonEncode({
      'root': root,
      'scanned_at_ms': scannedAtMs,
      'snapshot_id': snapshotId,
      'snapshot_path': snapshotFile.path,
    }),
  );
}

void main() {
  test('snapshot update preserves selection and invalidates one prefix', () {
    final session = VolwardSession.test();
    session.setSelectedEntryIds({'entry-a'});
    session.setSnapshotForTest(snapshot('one', '/root'));

    session.updateSnapshotForTest(
      snapshot('two', '/root'),
      affectedPrefix: '/root/changed',
    );

    expect(session.selectedEntryIds, {'entry-a'});
    expect(session.snapshotVersion, 2);
    expect(session.invalidatedPrefixes, {'/root/changed'});
    expect(session.consumeInvalidatedPrefixes(), {'/root/changed'});
    expect(session.invalidatedPrefixes, isEmpty);
  });

  test(
    'authoritative peek keeps an overlay for index-only snapshots',
    () async {
      final session = VolwardSession.test();
      session.setSnapshotForTest(
        ScanSnapshotState.fromIndexSummary({
          'snapshot_id': 'snap-index',
          'root_path': '/root',
          'root_size_bytes': 100,
          'entry_count': 1,
        }),
      );

      await session.applyMergeForTest(
        '/root/Downloads',
        {
          'name': 'Downloads',
          'path': '/root/Downloads',
          'is_dir': true,
          'children': [
            {
              'name': 'fresh.txt',
              'path': '/root/Downloads/fresh.txt',
              'is_dir': false,
              'entry_id': 'fresh',
              'size_bytes': 12,
              'category': 'Document',
            },
          ],
        },
        [
          {
            'id': 'fresh',
            'display_name': 'fresh.txt',
            'path_or_uri': '/root/Downloads/fresh.txt',
            'size_bytes': 12,
            'category': 'Document',
            'deletable': false,
          },
        ],
        authoritative: true,
      );

      final overlay = session.directoryOverlayForPath('/root/Downloads');
      expect(overlay, isNotNull);
      expect(overlay!.children.single.path, '/root/Downloads/fresh.txt');
      expect(session.lastSnapshot!.tree!.children, isEmpty);
    },
  );

  test(
    'successful delete removes the target from the directory overlay',
    () async {
      final session = VolwardSession.test();
      session.setSnapshotForTest(
        ScanSnapshotState.fromIndexSummary({
          'snapshot_id': 'snap-index',
          'root_path': '/root',
          'root_size_bytes': 100,
          'entry_count': 2,
        }),
      );

      await session.applyMergeForTest(
        '/root/Downloads',
        {
          'name': 'Downloads',
          'path': '/root/Downloads',
          'is_dir': true,
          'children': [
            {
              'name': 'deleted.txt',
              'path': '/root/Downloads/deleted.txt',
              'is_dir': false,
              'entry_id': 'new-deleted-id',
              'size_bytes': 12,
            },
            {
              'name': 'blocked.txt',
              'path': '/root/Downloads/blocked.txt',
              'is_dir': false,
              'entry_id': 'blocked',
              'size_bytes': 8,
            },
          ],
        },
        const [],
        authoritative: true,
      );

      session.applySuccessfulDeleteOverlayForTest(
        '/root/Downloads',
        const ['old-deleted-id', 'blocked'],
        {
          'deleted_count': 1,
          'failed_paths': ['/root/Downloads/blocked.txt'],
        },
        targetPathById: const {
          'old-deleted-id': '/root/Downloads/deleted.txt',
          'blocked': '/root/Downloads/blocked.txt',
        },
      );

      final overlay = session.directoryOverlayForPath('/root/Downloads');
      expect(overlay, isNotNull);
      expect(overlay!.children.map((node) => node.path), [
        '/root/Downloads/blocked.txt',
      ]);
    },
  );

  test('delete completes before post-delete directory refresh', () async {
    final session = VolwardSession.test();
    session.setSnapshotForTest(
      ScanSnapshotState.fromIndexSummary({
        'snapshot_id': 'snap-index',
        'root_path': '/root',
        'root_size_bytes': 20,
        'entry_count': 2,
      }),
    );
    await session.applyMergeForTest(
      '/root/Downloads',
      {
        'name': 'Downloads',
        'path': '/root/Downloads',
        'is_dir': true,
        'children': [
          {
            'name': 'deleted.txt',
            'path': '/root/Downloads/deleted.txt',
            'is_dir': false,
            'entry_id': 'path:/root/Downloads/deleted.txt',
            'size_bytes': 12,
          },
          {
            'name': 'kept.txt',
            'path': '/root/Downloads/kept.txt',
            'is_dir': false,
            'entry_id': 'path:/root/Downloads/kept.txt',
            'size_bytes': 8,
          },
        ],
      },
      const [],
      authoritative: true,
    );

    session.deleteRunnerForTest = (_, __, ___) => {
      'deleted_count': 1,
      'freed_bytes': 12,
      'failed_paths': const <String>[],
    };
    final refreshStarted = Completer<void>();
    final finishRefresh = Completer<void>();
    session.directoryRefreshRunnerForTest = (path) async {
      expect(path, '/root/Downloads');
      refreshStarted.complete();
      await finishRefresh.future;
    };

    final report = await session.deleteEntries(
      const ['path:/root/Downloads/deleted.txt'],
      rescanAfterDelete: true,
      refreshPath: '/root/Downloads',
      targetPathById: const {
        'path:/root/Downloads/deleted.txt': '/root/Downloads/deleted.txt',
      },
    );

    expect(report['deleted_count'], 1);
    expect(session.deleting, isFalse);
    expect(
      session
          .directoryOverlayForPath('/root/Downloads')!
          .children
          .map((node) => node.path),
      ['/root/Downloads/kept.txt'],
    );
    await refreshStarted.future.timeout(const Duration(seconds: 1));
    expect(finishRefresh.isCompleted, isFalse);

    finishRefresh.complete();
    await Future<void>.delayed(Duration.zero);
  });

  test('estimated scan progress advances over time and finishes at 100%', () {
    final startedAt = DateTime.utc(2026, 8, 3, 12);

    final initial = estimateScanFraction(
      scanning: true,
      phase: 'DiscoveringRoots',
      scanStartedAt: startedAt,
      now: startedAt,
    );
    final later = estimateScanFraction(
      scanning: true,
      phase: 'DiscoveringRoots',
      scanStartedAt: startedAt,
      now: startedAt.add(const Duration(seconds: 3)),
    );
    final done = estimateScanFraction(
      scanning: true,
      phase: 'Done',
      scanStartedAt: startedAt,
      now: startedAt.add(const Duration(seconds: 3)),
    );

    expect(initial, isNotNull);
    expect(later, isNotNull);
    expect(done, isNotNull);
    expect(later!, greaterThan(initial!));
    expect(later, lessThan(0.04));
    expect(done, 1.0);
  });

  test(
    'restoreCachedSnapshotIfNeeded overwrites a preview stub from disk cache',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-restore-preview',
      );
      addTearDown(() {
        SnapshotCache.cacheDirForTest = null;
        temp.deleteSync(recursive: true);
      });
      SnapshotCache.cacheDirForTest = temp;

      const root = '/Users/test/Home';
      writeCachedSnapshot(
        cacheDir: temp,
        manifestName: 'cached',
        snapshotName: 'cached',
        root: root,
        snapshotId: 'cached-scan',
        scannedAtMs: 1700000000000,
        sizeBytes: 100,
        reclaimableBytes: 42,
      );

      final session = VolwardSession.test()..setScanRoots([root]);
      session.setSnapshotForTest(
        ScanSnapshotState.fromWire(
          buildPreviewSnapshot(rootPath: root, quickListEntries: const []),
        ),
      );
      expect(session.lastSnapshot!.snapshotId, startsWith('preview-'));

      await session.restoreCachedSnapshotIfNeeded();

      expect(session.lastSnapshot!.snapshotId, 'cached-scan');
      expect(session.lastSnapshot!.stats['scan_state'], 'Done');
      expect(session.lastSnapshot!.reclaimableEstimateBytes, 42);
    },
  );

  test(
    'restoreCachedSnapshotIfNeeded keeps an already completed scan',
    () async {
      final session = VolwardSession.test()..setScanRoots(['/Users/test/Home']);
      session.setSnapshotForTest(snapshot('live-scan', '/Users/test/Home'));

      await session.restoreCachedSnapshotIfNeeded();

      expect(session.lastSnapshot!.snapshotId, 'live-scan');
    },
  );

  test(
    'restoreCachedSnapshotIfNeeded replaces a completed scan from another root',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-restore-custom',
      );
      addTearDown(() {
        SnapshotCache.cacheDirForTest = null;
        temp.deleteSync(recursive: true);
      });
      SnapshotCache.cacheDirForTest = temp;

      const homeRoot = '/Users/test/Home';
      const customRoot = '/Users/test/Projects/Archive';
      writeCachedSnapshot(
        cacheDir: temp,
        manifestName: 'custom',
        snapshotName: 'custom',
        root: customRoot,
        snapshotId: 'custom-scan',
        scannedAtMs: 1700000000100,
        sizeBytes: 80,
        reclaimableBytes: 9,
      );

      final session = VolwardSession.test()..setScanRoots([customRoot]);
      session.setSnapshotForTest(snapshot('home-scan', homeRoot));

      await session.restoreCachedSnapshotIfNeeded();

      expect(session.lastSnapshot!.snapshotId, 'custom-scan');
      expect(session.lastSnapshot!.tree!.path, customRoot);
    },
  );

  test(
    'switchScanRoot restores cached scan for the selected root before preview',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-switch-restore',
      );
      addTearDown(() {
        SnapshotCache.cacheDirForTest = null;
        temp.deleteSync(recursive: true);
      });
      SnapshotCache.cacheDirForTest = temp;

      const cachedRoot = '/Users/test/Downloads';
      const otherRoot = '/Users/test/Documents';
      writeCachedSnapshot(
        cacheDir: temp,
        manifestName: 'downloads',
        snapshotName: 'downloads',
        root: cachedRoot,
        snapshotId: 'downloads-scan',
        scannedAtMs: 1700000000200,
        sizeBytes: 512,
        reclaimableBytes: 7,
      );

      var previewCalls = 0;
      final session = VolwardSession.test()
        ..setScanRoots([otherRoot])
        ..scanRootPreviewReaderForTest = ((root) async {
          previewCalls++;
          return [
            {'path': '$root/Preview', 'is_dir': true},
          ];
        });
      session.setSnapshotForTest(snapshot('other-scan', otherRoot));

      await session.switchScanRoot(cachedRoot, startFullScan: false);
      for (
        var index = 0;
        index < 20 && session.lastSnapshot?.snapshotId != 'downloads-scan';
        index++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(session.lastSnapshot!.snapshotId, 'downloads-scan');
      expect(session.lastSnapshot!.tree!.path, cachedRoot);
      expect(session.lastSnapshot!.tree!.sizeBytes, 512);
      expect(session.targetPreviewLoading, isFalse);
      expect(previewCalls, 0);
    },
  );
}
