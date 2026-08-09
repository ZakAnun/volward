import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:volward/scan_snapshot_state.dart';
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
        'path:/root/Downloads/deleted.txt':
            '/root/Downloads/deleted.txt',
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
}
