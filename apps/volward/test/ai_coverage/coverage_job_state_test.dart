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

  test('legacy job json without failure fields uses defaults', () async {
    final dir = await Directory.systemTemp.createTemp('coverage-job-legacy');
    final store = CoverageJobStateStore(dir);
    const state = CoverageJobState(
      snapshotId: 's-legacy',
      rootPath: '/',
      planVersion: 1,
      cursor: 40,
      totalUnclassified: 80,
      analyzedFiles: 40,
      preClassifiedCount: 0,
      status: CoverageJobStatus.paused,
      pauseReason: CoveragePauseReason.manual,
      usedTokens: 0,
      usedCredits: 1,
      budgetTokens: 0,
      budgetCredits: 50,
      updatedAtMs: 1,
    );
    await store.save(state);
    final loaded = await store.load('s-legacy');
    expect(loaded!.failedBatchPaths, isEmpty);
    expect(loaded.creditsChargedNoVerdict, 0);
    await dir.delete(recursive: true);
  });
}
