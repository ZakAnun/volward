import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_native_responses.dart';

void main() {
  test('parseCoveragePlanSummary decodes summary JSON', () {
    final summary = parseCoveragePlanSummary('''
      {"snapshot_id":"s1","plan_version":1,"root_path":"/Users/x",
       "total_unclassified":120,"pre_classified_count":3,
       "group_rows":1,"file_rows":60,"estimated_pages":2}
    ''');
    expect(summary.snapshotId, 's1');
    expect(summary.totalUnclassified, 120);
  });

  test('parseCoveragePage decodes rows', () {
    final page = parseCoveragePage('''
      {"snapshot_id":"s1","plan_version":1,"next_cursor":40,
       "rows":[{"row_index":0,"kind":"file","path":"/a","size_bytes":1}]}
    ''');
    expect(page.nextCursor, 40);
    expect(page.rows.single.path, '/a');
  });

  test('parseCoverageGroupMembers decodes member list', () {
    final members = parseCoverageGroupMembers('''
      {"snapshot_id":"s1","path":"/tmp/cache",
       "members":[{"path":"/tmp/cache/a","size_bytes":1}]}
    ''');
    expect(members, hasLength(1));
    expect(members.single['path'], '/tmp/cache/a');
  });

  test('decodeCoverageObjectJson throws on error prefix', () {
    expect(
      () => decodeCoverageObjectJson('error:coverage plan mismatch'),
      throwsA(isA<CoverageEngineException>()),
    );
  });
}
