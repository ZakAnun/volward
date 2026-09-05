import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_models.dart';

void main() {
  test('CoveragePlanSummary parses summary JSON', () {
    final raw =
        jsonDecode('''
      {"snapshot_id":"s1","plan_version":1,"root_path":"/Users/x",
       "total_unclassified":120,"pre_classified_count":3,
       "group_rows":1,"file_rows":60,"estimated_pages":2}
    ''')
            as Map<String, dynamic>;
    final summary = CoveragePlanSummary.fromJson(raw);
    expect(summary.snapshotId, 's1');
    expect(summary.totalUnclassified, 120);
    expect(summary.estimatedPages, 2);
  });

  test('CoveragePage parses rows and null cursor', () {
    final raw =
        jsonDecode('''
      {"snapshot_id":"s1","plan_version":1,"next_cursor":null,
       "rows":[
         {"row_index":0,"kind":"group","path":"/a","size_bytes":10,"member_count":2},
         {"row_index":1,"kind":"file","path":"/b","size_bytes":3}
       ]}
    ''')
            as Map<String, dynamic>;
    final page = CoveragePage.fromJson(raw);
    expect(page.nextCursor, isNull);
    expect(page.rows, hasLength(2));
    expect(page.rows.first.kind, CoverageRowKind.group);
    expect(page.rows.first.memberCount, 2);
    expect(page.rows.last.memberCount, isNull);
  });
}
