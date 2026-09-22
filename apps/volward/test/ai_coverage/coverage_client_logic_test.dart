import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/ai/coverage_client_logic.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_models.dart';

void main() {
  CoverageJobState job({
    CoverageJobStatus status = CoverageJobStatus.paused,
    int clientLogicVersion = 1,
    int planVersion = 1,
  }) => CoverageJobState(
    snapshotId: 's',
    rootPath: '/',
    planVersion: planVersion,
    cursor: 0,
    totalUnclassified: 10,
    analyzedFiles: 0,
    preClassifiedCount: 0,
    status: status,
    usedTokens: 0,
    usedCredits: 0,
    budgetTokens: 0,
    budgetCredits: 50,
    updatedAtMs: 0,
    clientLogicVersion: clientLogicVersion,
  );

  test('v2 plan active job needs upgrade at client logic v3', () {
    expect(
      coverageJobNeedsClientLogicUpgrade(
        job(planVersion: 2, clientLogicVersion: kCoverageClientLogicVersion),
      ),
      isTrue,
    );
    expect(
      coverageJobNeedsClientLogicUpgrade(
        job(planVersion: 3, clientLogicVersion: kCoverageClientLogicVersion),
      ),
      isFalse,
    );
  });

  test('legacy active job needs upgrade when version below current', () {
    expect(coverageJobNeedsClientLogicUpgrade(job()), isTrue);
    expect(
      coverageJobNeedsClientLogicUpgrade(
        job(
          clientLogicVersion: kCoverageClientLogicVersion,
          planVersion: kCoverageClientLogicVersion,
        ),
      ),
      isFalse,
    );
  });

  test('precheck credits prefer v3 tree and tail breakdown', () {
    const v3 = CoveragePlanSummary(
      snapshotId: 's',
      planVersion: 3,
      rootPath: '/',
      totalUnclassified: 10,
      preClassifiedCount: 0,
      groupRows: 0,
      fileRows: 10,
      estimatedPages: 99,
      localSafeFiles: 1,
      localKeepFiles: 2,
      estimatedTreeCredits: 4,
      estimatedTailCredits: 2,
      seedNodeCount: 1,
    );
    expect(coveragePrecheckEstimatedCredits(v3), 6);
    expect(
      coveragePrecheckEstimatedCredits(
        const CoveragePlanSummary(
          snapshotId: 's',
          planVersion: 1,
          rootPath: '/',
          totalUnclassified: 10,
          preClassifiedCount: 0,
          groupRows: 0,
          fileRows: 10,
          estimatedPages: 8,
        ),
      ),
      8,
    );
  });

  test('completed legacy job does not need upgrade', () {
    expect(
      coverageJobNeedsClientLogicUpgrade(
        job(status: CoverageJobStatus.completed),
      ),
      isFalse,
    );
  });

  test('coveragePlanMinApiCalls sums v3 tree and tail credits', () {
    const summary = CoveragePlanSummary(
      snapshotId: 's',
      planVersion: 3,
      rootPath: '/',
      totalUnclassified: 100,
      preClassifiedCount: 0,
      groupRows: 0,
      fileRows: 0,
      estimatedPages: 0,
      estimatedTreeCredits: 3,
      estimatedTailCredits: 2,
    );
    expect(coveragePlanMinApiCalls(summary), 5);
  });

  test(
    'coverageJobEstimatedRemainingApiCalls subtracts used credits for v3',
    () {
      const state = CoverageJobState(
        snapshotId: 's',
        rootPath: '/',
        planVersion: 3,
        cursor: 0,
        totalUnclassified: 200,
        analyzedFiles: 0,
        preClassifiedCount: 0,
        status: CoverageJobStatus.paused,
        usedTokens: 0,
        usedCredits: 2,
        budgetTokens: 0,
        budgetCredits: 50,
        updatedAtMs: 1,
        estimatedTreeCredits: 3,
        estimatedTailCredits: 2,
      );
      expect(coverageJobEstimatedRemainingApiCalls(state), 3);
    },
  );

  test(
    'coveragePlanRequiresApi is false when tree and tail credits are zero',
    () {
      const summary = CoveragePlanSummary(
        snapshotId: 's',
        planVersion: 3,
        rootPath: '/',
        totalUnclassified: 10,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 0,
        estimatedPages: 0,
        estimatedTreeCredits: 0,
        estimatedTailCredits: 0,
      );
      expect(coveragePlanRequiresApi(summary), isFalse);
    },
  );

  test(
    'coverageJobBillingMatchesMode detects BYOK token job on Platform UI',
    () {
      const tokenJob = CoverageJobState(
        snapshotId: 's',
        rootPath: '/',
        planVersion: 3,
        cursor: 0,
        totalUnclassified: 10,
        analyzedFiles: 5,
        preClassifiedCount: 0,
        status: CoverageJobStatus.paused,
        usedTokens: 100,
        usedCredits: 0,
        budgetTokens: 50,
        budgetCredits: 0,
        updatedAtMs: 0,
      );
      expect(coverageJobBillingMatchesMode(AiMode.platform, tokenJob), isFalse);
      expect(coverageJobBillingMatchesMode(AiMode.byok, tokenJob), isTrue);
    },
  );

  test(
    'coverageSuggestedTokenBudgetRaise prefers Settings over stale job cap',
    () {
      expect(
        coverageSuggestedTokenBudgetRaise(
          jobBudgetTokens: 50,
          settingsBudgetTokens: 500000,
        ),
        500000,
      );
      expect(
        coverageSuggestedTokenBudgetRaise(
          jobBudgetTokens: 600000,
          settingsBudgetTokens: 500000,
        ),
        600000 + AiSettingsStore.defaultCoverageBudgetTokens ~/ 2,
      );
    },
  );

  test(
    'coverageResumePlanFromMemoryCache matches snapshot and plan version',
    () {
      const plan = CoveragePlanSummary(
        snapshotId: 'snap-a',
        planVersion: 3,
        rootPath: '/root',
        totalUnclassified: 10,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 10,
        estimatedPages: 1,
        seedNodeCount: 1,
      );
      const job = CoverageJobState(
        snapshotId: 'snap-a',
        rootPath: '/root',
        planVersion: 3,
        cursor: 0,
        totalUnclassified: 10,
        analyzedFiles: 5,
        preClassifiedCount: 0,
        status: CoverageJobStatus.paused,
        usedTokens: 1,
        usedCredits: 0,
        budgetTokens: 100,
        budgetCredits: 0,
        updatedAtMs: 1,
        treeQueueCursor: 2,
      );
      expect(
        coverageResumePlanFromMemoryCache(
          snapshotId: 'snap-a',
          job: job,
          cachedSnapshotId: 'snap-a',
          cachedSummary: plan,
        ),
        plan,
      );
      expect(
        coverageResumePlanFromMemoryCache(
          snapshotId: 'snap-a',
          job: job,
          cachedSnapshotId: 'snap-b',
          cachedSummary: plan,
        ),
        isNull,
      );
      const wrongVersion = CoverageJobState(
        snapshotId: 'snap-a',
        rootPath: '/root',
        planVersion: 2,
        cursor: 0,
        totalUnclassified: 10,
        analyzedFiles: 5,
        preClassifiedCount: 0,
        status: CoverageJobStatus.paused,
        usedTokens: 1,
        usedCredits: 0,
        budgetTokens: 100,
        budgetCredits: 0,
        updatedAtMs: 1,
      );
      expect(
        coverageResumePlanFromMemoryCache(
          snapshotId: 'snap-a',
          job: wrongVersion,
          cachedSnapshotId: 'snap-a',
          cachedSummary: plan,
        ),
        isNull,
      );
    },
  );

  test('coverageResumePlanFromMemoryCache rejects fingerprint mismatch', () {
    const fpA = CoverageSnapshotFingerprint(
      rootSizeBytes: 1,
      scannedAtMs: 1,
      pathsSeen: 1,
      dirsSeen: 0,
      filesSeen: 1,
      filesInSnapshot: 1,
      pathsSkipped: 0,
      truncated: false,
      incompleteReason: null,
    );
    const fpB = CoverageSnapshotFingerprint(
      rootSizeBytes: 2,
      scannedAtMs: 1,
      pathsSeen: 1,
      dirsSeen: 0,
      filesSeen: 1,
      filesInSnapshot: 1,
      pathsSkipped: 0,
      truncated: false,
      incompleteReason: null,
    );
    const plan = CoveragePlanSummary(
      snapshotId: 'snap-a',
      planVersion: 1,
      rootPath: '/',
      totalUnclassified: 1,
      preClassifiedCount: 0,
      groupRows: 0,
      fileRows: 1,
      estimatedPages: 1,
      fingerprint: fpB,
    );
    const job = CoverageJobState(
      snapshotId: 'snap-a',
      rootPath: '/',
      planVersion: 1,
      cursor: 0,
      totalUnclassified: 1,
      analyzedFiles: 1,
      preClassifiedCount: 0,
      status: CoverageJobStatus.paused,
      usedTokens: 0,
      usedCredits: 0,
      budgetTokens: 1,
      budgetCredits: 0,
      updatedAtMs: 0,
      fingerprint: fpA,
    );
    expect(
      coverageResumePlanFromMemoryCache(
        snapshotId: 'snap-a',
        job: job,
        cachedSnapshotId: 'snap-a',
        cachedSummary: plan,
      ),
      isNull,
    );
  });

  test('coverageIgnoreStalePausedJobState drops pre-resume paused emit', () {
    const paused = CoverageJobState(
      snapshotId: 's',
      rootPath: '/',
      planVersion: 1,
      cursor: 0,
      totalUnclassified: 1,
      analyzedFiles: 0,
      preClassifiedCount: 0,
      status: CoverageJobStatus.paused,
      usedTokens: 0,
      usedCredits: 0,
      budgetTokens: 1,
      budgetCredits: 0,
      updatedAtMs: 42,
    );
    expect(
      coverageIgnoreStalePausedJobState(
        state: paused,
        stalePausedUpdatedAtMs: 42,
      ),
      isTrue,
    );
    expect(
      coverageIgnoreStalePausedJobState(
        state: paused.copyWith(updatedAtMs: 99),
        stalePausedUpdatedAtMs: 42,
      ),
      isFalse,
    );
  });
}
