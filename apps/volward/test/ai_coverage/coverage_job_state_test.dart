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
}
