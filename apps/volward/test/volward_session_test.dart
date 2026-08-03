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
