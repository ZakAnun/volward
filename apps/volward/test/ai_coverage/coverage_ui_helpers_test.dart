import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_models.dart';
import 'package:volward/ai/coverage_ui_helpers.dart';
import 'package:volward/ai/coverage_verdict_store.dart';

void main() {
  const treePlan = CoveragePlanSummary(
    snapshotId: 'snapshot',
    planVersion: 3,
    rootPath: '/root',
    totalUnclassified: 20,
    preClassifiedCount: 0,
    groupRows: 0,
    fileRows: 0,
    estimatedPages: 0,
    treePendingFiles: 12,
    tailFiles: 8,
  );

  CoverageJobState job({
    CoverageJobStatus status = CoverageJobStatus.running,
    CoveragePauseReason? pauseReason,
    int totalUnclassified = 20,
    int? analyzedFiles,
    int localRuleFiles = 0,
    int? localPlannedFiles,
    int aiResolvedFiles = 0,
    bool localPhaseComplete = false,
  }) {
    return CoverageJobState(
      snapshotId: 'snapshot',
      rootPath: '/root',
      planVersion: 3,
      cursor: 0,
      totalUnclassified: totalUnclassified,
      analyzedFiles: analyzedFiles ?? localRuleFiles + aiResolvedFiles,
      preClassifiedCount: 0,
      status: status,
      pauseReason: pauseReason,
      usedTokens: 0,
      usedCredits: 0,
      budgetTokens: 0,
      budgetCredits: 0,
      updatedAtMs: 1,
      localRuleFiles: localRuleFiles,
      localPlannedFiles: localPlannedFiles,
      aiResolvedFiles: aiResolvedFiles,
      localPhaseComplete: localPhaseComplete,
    );
  }

  test(
    'buildClassificationProvenanceSummary separates sources and running AI',
    () {
      final summary = buildClassificationProvenanceSummary(
        job: job(localRuleFiles: 4, aiResolvedFiles: 7),
        plan: treePlan,
        bootstrapPreclassifiedCount: 3,
        hasProvider: true,
        isLocalOnlyPlan: false,
      );

      expect(summary.bootstrapLocalCount, 3);
      expect(summary.localRuleCount, 4);
      expect(summary.aiResolvedCount, 7);
      expect(summary.aiPlannedCount, 20);
      expect(summary.phase, ClassificationAiPhase.running);
    },
  );

  test(
    'buildClassificationProvenanceSummary resolves terminal and local-only phases',
    () {
      expect(
        buildClassificationProvenanceSummary(
          job: job(status: CoverageJobStatus.completed),
          plan: treePlan,
          bootstrapPreclassifiedCount: 0,
          hasProvider: true,
          isLocalOnlyPlan: false,
        ).phase,
        ClassificationAiPhase.completed,
      );
      expect(
        buildClassificationProvenanceSummary(
          job: job(
            status: CoverageJobStatus.paused,
            pauseReason: CoveragePauseReason.failed,
          ),
          plan: treePlan,
          bootstrapPreclassifiedCount: 0,
          hasProvider: true,
          isLocalOnlyPlan: false,
        ).phase,
        ClassificationAiPhase.failed,
      );
      expect(
        buildClassificationProvenanceSummary(
          job: job(status: CoverageJobStatus.paused),
          plan: treePlan,
          bootstrapPreclassifiedCount: 0,
          hasProvider: true,
          isLocalOnlyPlan: false,
        ).phase,
        ClassificationAiPhase.paused,
      );
      expect(
        buildClassificationProvenanceSummary(
          job: null,
          plan: treePlan,
          bootstrapPreclassifiedCount: 2,
          hasProvider: false,
          isLocalOnlyPlan: true,
        ).phase,
        ClassificationAiPhase.notRequired,
      );
    },
  );

  test(
    'buildClassificationProvenanceSummary keeps old or absent plans unknown',
    () {
      final summary = buildClassificationProvenanceSummary(
        job: job(),
        plan: null,
        bootstrapPreclassifiedCount: 0,
        hasProvider: true,
        isLocalOnlyPlan: false,
      );

      expect(summary.localRuleCount, 0);
      expect(summary.aiResolvedCount, 0);
      expect(summary.aiPlannedCount, isNull);
      expect(summary.phase, ClassificationAiPhase.running);
    },
  );

  test(
    'buildClassificationProvenanceSummary reports not started without a provider or job',
    () {
      final summary = buildClassificationProvenanceSummary(
        job: null,
        plan: null,
        bootstrapPreclassifiedCount: 0,
        hasProvider: false,
        isLocalOnlyPlan: false,
      );

      expect(summary.phase, ClassificationAiPhase.notStarted);
    },
  );

  test('coverage run presentation rejects a job from another snapshot', () {
    final presentation = buildCoverageRunPresentation(
      snapshotId: 'current',
      job: job(),
      plan: treePlan,
    );

    expect(presentation.localPhase, CoverageLocalPhase.notStarted);
    expect(presentation.localProgressFraction, isNull);
    expect(presentation.aiPhase, ClassificationAiPhase.notStarted);
  });

  test(
    'coverage run presentation keeps AI progress hidden until local rules finish',
    () {
      const plan = CoveragePlanSummary(
        snapshotId: 'snapshot',
        planVersion: 3,
        rootPath: '/root',
        totalUnclassified: 20,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 0,
        estimatedPages: 0,
        localSafeFiles: 12,
        localKeepFiles: 8,
        treePendingFiles: 12,
        tailFiles: 8,
      );
      final presentation = buildCoverageRunPresentation(
        snapshotId: 'snapshot',
        job: job(localRuleFiles: 5),
        plan: plan,
      );

      expect(presentation.localPhase, CoverageLocalPhase.running);
      expect(presentation.localProgressFraction, 0.25);
      expect(presentation.aiPhase, ClassificationAiPhase.notStarted);
      expect(presentation.aiProgressFraction, isNull);
    },
  );

  test('coverage run presentation preserves a failed local terminal state', () {
    final presentation = buildCoverageRunPresentation(
      snapshotId: 'snapshot',
      job: job(
        status: CoverageJobStatus.paused,
        pauseReason: CoveragePauseReason.failed,
        localRuleFiles: 5,
      ),
      plan: treePlan,
    );

    expect(presentation.localPhase, CoverageLocalPhase.failed);
    expect(presentation.aiPhase, ClassificationAiPhase.failed);
    expect(presentation.aiProgressFraction, isNull);
  });

  test('coverage run presentation starts AI only after local completion', () {
    final presentation = buildCoverageRunPresentation(
      snapshotId: 'snapshot',
      job: job(
        localRuleFiles: 20,
        localPlannedFiles: 20,
        aiResolvedFiles: 4,
        localPhaseComplete: true,
      ),
      plan: const CoveragePlanSummary(
        snapshotId: 'snapshot',
        planVersion: 3,
        rootPath: '/root',
        totalUnclassified: 20,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 0,
        estimatedPages: 0,
        localSafeFiles: 12,
        localKeepFiles: 8,
        treePendingFiles: 12,
        tailFiles: 8,
      ),
    );

    expect(presentation.localPhase, CoverageLocalPhase.completed);
    expect(presentation.aiPhase, ClassificationAiPhase.running);
    expect(presentation.aiProgressFraction, 0.2);
  });

  test(
    'completed job with an incomplete local count is not local complete',
    () {
      final presentation = buildCoverageRunPresentation(
        snapshotId: 'snapshot',
        job: job(
          status: CoverageJobStatus.completed,
          localRuleFiles: 0,
          localPlannedFiles: 20,
        ),
        plan: const CoveragePlanSummary(
          snapshotId: 'snapshot',
          planVersion: 3,
          rootPath: '/root',
          totalUnclassified: 20,
          preClassifiedCount: 0,
          groupRows: 0,
          fileRows: 0,
          estimatedPages: 0,
          localSafeFiles: 12,
          localKeepFiles: 8,
          treePendingFiles: 0,
          tailFiles: 0,
        ),
      );

      expect(presentation.localPhase, CoverageLocalPhase.incomplete);
      expect(presentation.localProgressFraction, 0);
      expect(presentation.aiPhase, ClassificationAiPhase.notStarted);
    },
  );

  test('terminal incomplete coverage reports a partial completion truth', () {
    final truth = coverageCompletionTruth(
      job(
        status: CoverageJobStatus.completed,
        totalUnclassified: 4610,
        analyzedFiles: 317,
      ),
    );

    expect(truth.phase, CoverageCompletionPhase.partial);
    expect(truth.analyzedFiles, 317);
    expect(truth.totalFiles, 4610);
    expect(truth.remainingFiles, 4293);
  });

  test('terminal fully covered job reports a complete completion truth', () {
    final truth = coverageCompletionTruth(
      job(
        status: CoverageJobStatus.completed,
        totalUnclassified: 4610,
        analyzedFiles: 4610,
      ),
    );

    expect(truth.phase, CoverageCompletionPhase.completed);
    expect(truth.remainingFiles, 0);
  });

  test('classification progress presentation exposes bounded AI progress', () {
    const provenance = ClassificationProvenanceSummary(
      bootstrapLocalCount: 3,
      localRuleCount: 4,
      aiResolvedCount: 7,
      aiPlannedCount: 20,
      phase: ClassificationAiPhase.running,
    );

    final presentation = buildClassificationProgressPresentation(provenance);

    expect(presentation.progressFraction, 0.35);
    expect(presentation.progressPercent, 35);
    expect(presentation.showsAiProgress, isTrue);
  });

  test(
    'classification progress presentation suppresses unreliable progress',
    () {
      final unknown = buildClassificationProgressPresentation(
        const ClassificationProvenanceSummary(
          bootstrapLocalCount: 0,
          localRuleCount: 0,
          aiResolvedCount: 7,
          aiPlannedCount: null,
          phase: ClassificationAiPhase.running,
        ),
      );
      final localOnly = buildClassificationProgressPresentation(
        const ClassificationProvenanceSummary(
          bootstrapLocalCount: 0,
          localRuleCount: 4,
          aiResolvedCount: 0,
          aiPlannedCount: 0,
          phase: ClassificationAiPhase.notRequired,
        ),
      );
      final stalePlan = buildClassificationProgressPresentation(
        const ClassificationProvenanceSummary(
          bootstrapLocalCount: 0,
          localRuleCount: 0,
          aiResolvedCount: 30,
          aiPlannedCount: 20,
          phase: ClassificationAiPhase.running,
        ),
      );

      expect(unknown.progressFraction, isNull);
      expect(localOnly.progressFraction, isNull);
      expect(stalePlan.progressFraction, 1);
      expect(stalePlan.progressPercent, 100);
    },
  );

  test('computeCoverageSourceStats counts file and group sources', () {
    const verdicts = [
      CoverageVerdict(
        path: '/a',
        verdict: 'keep',
        confidence: 'high',
        reason: 'r',
        coverageSource: 'file',
        sizeBytes: 1,
      ),
      CoverageVerdict(
        path: '/b',
        verdict: 'keep',
        confidence: 'high',
        reason: 'r',
        coverageSource: 'group:/b',
        sizeBytes: 2,
      ),
    ];

    final stats = computeCoverageSourceStats(
      verdicts: verdicts,
      preClassifiedCount: 3,
    );

    expect(stats.fileVerdicts, 1);
    expect(stats.groupVerdicts, 1);
    expect(stats.localPreClassified, 3);
  });

  test('unanalyzedCandidateVerdicts skips paths with verdicts', () {
    const candidates = [
      AiCandidate(path: '/a', sizeBytes: 1, isDir: false),
      AiCandidate(path: '/b', sizeBytes: 2, isDir: false),
    ];

    final pending = unanalyzedCandidateVerdicts(
      candidates: candidates,
      verdictPaths: const {'/a'},
      reason: 'waiting',
    );

    expect(pending, hasLength(1));
    expect(pending.single.path, '/b');
    expect(pending.single.verdict, 'unanalyzed');
  });

  test('buildUnanalyzedDisplayVerdicts adds aggregate beyond preview', () {
    final previewCandidates = List.generate(
      3,
      (index) =>
          AiCandidate(path: '/preview/$index', sizeBytes: 1, isDir: false),
    );

    final pending = buildUnanalyzedDisplayVerdicts(
      pendingFileCount: 200,
      previewCandidates: previewCandidates,
      verdictPaths: const {},
      itemReason: 'waiting',
      aggregateSummaryReason: (remaining) =>
          'Plus $remaining more files awaiting analysis',
    );

    expect(previewCandidates, hasLength(3));
    expect(pending, hasLength(4));
    expect(pending.last.verdict, 'unanalyzed');
    expect(pending.last.reason, 'Plus 197 more files awaiting analysis');
    expect(pending.last.path, startsWith('coverage://pending/'));
  });
}
