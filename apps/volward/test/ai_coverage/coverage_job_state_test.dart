import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_job_state.dart';

void main() {
  test('state round trips through store with temp rename', () async {
    final dir = await Directory.systemTemp.createTemp('coverage-job-');
    final store = CoverageJobStateStore(dir);
    const state = CoverageJobState(
      snapshotId: 's1',
      rootPath: '/Users/x',
      planVersion: 1,
      cursor: 40,
      totalUnclassified: 120,
      analyzedFiles: 40,
      preClassifiedCount: 3,
      status: CoverageJobStatus.paused,
      pauseReason: CoveragePauseReason.budget,
      usedTokens: 1000,
      usedCredits: 0,
      budgetTokens: 500000,
      budgetCredits: 0,
      updatedAtMs: 1,
    );
    await store.save(state);
    final loaded = await store.load('s1');
    expect(loaded, isNotNull);
    expect(loaded!.cursor, 40);
    expect(loaded.status, CoverageJobStatus.paused);
    expect(loaded.pauseReason, CoveragePauseReason.budget);
    await dir.delete(recursive: true);
  });

  test('failed batch paths and creditsChargedNoVerdict persist', () async {
    final dir = await Directory.systemTemp.createTemp('coverage-job-fail');
    final store = CoverageJobStateStore(dir);
    const state = CoverageJobState(
      snapshotId: 's-fail',
      rootPath: '/Users/x',
      planVersion: 1,
      cursor: 0,
      totalUnclassified: 2,
      analyzedFiles: 0,
      preClassifiedCount: 0,
      status: CoverageJobStatus.paused,
      pauseReason: CoveragePauseReason.failed,
      pauseDetail: CoveragePauseDetail.parse,
      usedTokens: 0,
      usedCredits: 0,
      budgetTokens: 0,
      budgetCredits: 10,
      updatedAtMs: 1,
      failedBatchPaths: ['/cache/a', '/cache/b'],
      creditsChargedNoVerdict: 1,
    );
    await store.save(state);
    final loaded = await store.load('s-fail');
    expect(loaded!.failedBatchPaths, ['/cache/a', '/cache/b']);
    expect(loaded.creditsChargedNoVerdict, 1);
    await dir.delete(recursive: true);
  });

  test('client_logic_version round trips', () async {
    final dir = await Directory.systemTemp.createTemp('coverage-job-clv');
    final store = CoverageJobStateStore(dir);
    const state = CoverageJobState(
      snapshotId: 's-clv',
      rootPath: '/',
      planVersion: 1,
      cursor: 0,
      totalUnclassified: 1,
      analyzedFiles: 0,
      preClassifiedCount: 0,
      status: CoverageJobStatus.running,
      usedTokens: 0,
      usedCredits: 0,
      budgetTokens: 0,
      budgetCredits: 50,
      updatedAtMs: 1,
      clientLogicVersion: 3,
    );
    await store.save(state);
    final loaded = await store.load('s-clv');
    expect(loaded!.clientLogicVersion, 3);
    await dir.delete(recursive: true);
  });

  test('legacy job json without failure fields uses defaults', () async {
    final dir = await Directory.systemTemp.createTemp('coverage-job-legacy');
    final store = CoverageJobStateStore(dir);
    final file = File('${dir.path}/ai_coverage_job_s-legacy.json');
    await file.writeAsString('''
{
  "snapshot_id": "s-legacy",
  "root_path": "/",
  "plan_version": 1,
  "cursor": 40,
  "total_unclassified": 80,
  "analyzed_files": 40,
  "pre_classified_count": 0,
  "status": "paused",
  "pause_reason": "manual",
  "used_tokens": 0,
  "used_credits": 1,
  "budget_tokens": 0,
  "budget_credits": 50,
  "updated_at_ms": 1
}
''');
    final loaded = await store.load('s-legacy');
    expect(loaded!.failedBatchPaths, isEmpty);
    expect(loaded.creditsChargedNoVerdict, 0);
    expect(loaded.clientLogicVersion, 1);
    await dir.delete(recursive: true);
  });

  test('v3 tree plan fields round trip through json', () {
    const state = CoverageJobState(
      snapshotId: 's-v3',
      rootPath: '/Users/x',
      planVersion: 3,
      cursor: 10,
      totalUnclassified: 100,
      analyzedFiles: 10,
      preClassifiedCount: 0,
      status: CoverageJobStatus.running,
      usedTokens: 0,
      usedCredits: 5,
      budgetTokens: 0,
      budgetCredits: 50,
      updatedAtMs: 2,
      clientLogicVersion: 3,
      treeQueueCursor: 7,
      tailQueueCursor: 3,
      localResolvedFiles: 12,
      treeNodesCompleted: 4,
      estimatedTreeCredits: 20,
      estimatedTailCredits: 8,
    );
    final restored = CoverageJobState.fromJson(state.toJson());
    expect(restored.treeQueueCursor, 7);
    expect(restored.tailQueueCursor, 3);
    expect(restored.localResolvedFiles, 12);
    expect(restored.treeNodesCompleted, 4);
    expect(restored.estimatedTreeCredits, 20);
    expect(restored.estimatedTailCredits, 8);
    expect(restored.clientLogicVersion, 3);
  });

  test('v2 job json without tree plan fields uses defaults', () {
    final loaded = CoverageJobState.fromJson({
      'snapshot_id': 's-v2',
      'root_path': '/',
      'plan_version': 2,
      'cursor': 0,
      'total_unclassified': 10,
      'analyzed_files': 0,
      'pre_classified_count': 0,
      'status': 'running',
      'used_tokens': 0,
      'used_credits': 0,
      'budget_tokens': 0,
      'budget_credits': 50,
      'updated_at_ms': 1,
      'client_logic_version': 2,
    });
    expect(loaded.treeQueueCursor, 0);
    expect(loaded.tailQueueCursor, 0);
    expect(loaded.localResolvedFiles, 0);
    expect(loaded.treeNodesCompleted, 0);
    expect(loaded.estimatedTreeCredits, isNull);
    expect(loaded.estimatedTailCredits, isNull);
  });
}
