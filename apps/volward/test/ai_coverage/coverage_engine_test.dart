import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_engine.dart';
import 'package:volward/ai/coverage_models.dart';
import 'package:volward/ai/coverage_native_responses.dart';

void main() {
  test('CoveragePlanSummary parses tree plan v3 summary fields', () {
    const raw = '''
      {"snapshot_id":"tree-snap","plan_version":3,"root_path":"/root",
       "root_size_bytes":1000,"scanned_at_ms":42,
       "seed_node_count":2,"tail_file_count":5,
       "local_safe_files":0,"local_keep_files":10,"tail_files":5,"tree_pending_files":3,
       "estimated_tree_credits":1,"estimated_tail_credits":2}
    ''';
    final summary = CoveragePlanSummary.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    expect(summary.isTreePlan, isTrue);
    expect(summary.seedNodeCount, 2);
    expect(summary.tailFileCount, 5);
    expect(summary.treePendingFiles, 3);
    expect(summary.estimatedTailCredits, 2);
    expect(summary.fingerprint?.rootSizeBytes, 1000);
  });

  test('parseCoverageTreePage decodes nodes page', () {
    const raw = '''
      {"snapshot_id":"tree-snap","plan_version":3,"next_cursor":80,
       "nodes":[{"path":"/root/a","size_bytes":900,"file_count":2,"subdir_count":1,
                 "role":"storage","markers":[],"pruned_flags":0,"top_extensions":[[".dat",2]]}]}
    ''';
    final page = parseCoverageTreePage(raw);
    expect(page.nextCursor, 80);
    expect(page.nodes.single.path, '/root/a');
    expect(page.nodes.single.topExtensions.single.extension, '.dat');
  });

  test('FakeCoverageEngine pages rows by cursor', () async {
    final engine = FakeCoverageEngine(
      summary: const CoveragePlanSummary(
        snapshotId: 's1',
        planVersion: 1,
        rootPath: '/',
        totalUnclassified: 2,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 2,
        estimatedPages: 1,
      ),
      pages: [
        const CoveragePage(
          snapshotId: 's1',
          planVersion: 1,
          nextCursor: null,
          rows: [
            CoverageRow(
              rowIndex: 0,
              kind: CoverageRowKind.file,
              path: '/a',
              sizeBytes: 1,
            ),
            CoverageRow(
              rowIndex: 1,
              kind: CoverageRowKind.file,
              path: '/b',
              sizeBytes: 2,
            ),
          ],
        ),
      ],
    );
    final summary = await engine.buildPlan('s1');
    final page = await engine.nextPage('s1', summary.planVersion, 0);
    expect(page.rows, hasLength(2));
  });
}
