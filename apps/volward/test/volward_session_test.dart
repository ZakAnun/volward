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
  });
}
