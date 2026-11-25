import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_verdict_store.dart';
import 'package:volward/features/ai_coverage/controllers/ai_analysis_coverage_flow.dart';
import 'package:volward/features/ai_coverage/models/ai_analysis_workspace_display_state.dart';
import 'package:volward/widgets/ai_results_hub.dart';

void main() {
  const running = CoverageJobState(
    snapshotId: 'snap',
    rootPath: '/',
    planVersion: 3,
    cursor: 0,
    totalUnclassified: 10,
    analyzedFiles: 2,
    preClassifiedCount: 0,
    status: CoverageJobStatus.running,
    pauseReason: CoveragePauseReason.manual,
    usedTokens: 0,
    usedCredits: 0,
    budgetTokens: 0,
    budgetCredits: 0,
    updatedAtMs: 1,
  );

  const paused = CoverageJobState(
    snapshotId: 'snap',
    rootPath: '/',
    planVersion: 3,
    cursor: 0,
    totalUnclassified: 10,
    analyzedFiles: 2,
    preClassifiedCount: 0,
    status: CoverageJobStatus.paused,
    pauseReason: CoveragePauseReason.manual,
    usedTokens: 0,
    usedCredits: 0,
    budgetTokens: 0,
    budgetCredits: 0,
    updatedAtMs: 2,
  );

  test(
    'lightweight analyzing only applies to a running full-coverage phase',
    () {
      expect(
        aiCoverageIsLightweightAnalyzing(
          const AiCoverageFlowContext(
            phase: AiWorkspaceDisplayState.analyzing,
            analyzing: true,
            useFullCoverage: true,
            uiPrefersAnalyzingPhase: true,
            userEngagedFullRun: true,
            verdictsNotEmpty: false,
            resultsHubMode: ResultsHubMode.analyzing,
            deferJobUiForScroll: false,
            pauseInFlight: false,
            jobState: running,
            pendingJobState: null,
          ),
        ),
        isTrue,
      );
    },
  );

  test('terminal coalesce delay is zero and paused freezes activity', () {
    const context = AiCoverageFlowContext(
      phase: AiWorkspaceDisplayState.results,
      analyzing: false,
      useFullCoverage: true,
      uiPrefersAnalyzingPhase: false,
      userEngagedFullRun: true,
      verdictsNotEmpty: true,
      resultsHubMode: ResultsHubMode.ready,
      deferJobUiForScroll: false,
      pauseInFlight: false,
      jobState: paused,
      pendingJobState: paused,
    );
    expect(aiCoverageJobCoalesceDelayMs(context), 0);
    expect(
      aiCoverageFreezeActivityMotion(paused, pauseInFlight: false),
      isTrue,
    );
    expect(aiCoverageShouldShowResultsLocalPreviewHint(context), isTrue);
  });

  test('banner verdict rows are hidden in lightweight analyzing mode', () {
    const context = AiCoverageFlowContext(
      phase: AiWorkspaceDisplayState.analyzing,
      analyzing: true,
      useFullCoverage: true,
      uiPrefersAnalyzingPhase: true,
      userEngagedFullRun: true,
      verdictsNotEmpty: true,
      resultsHubMode: ResultsHubMode.analyzing,
      deferJobUiForScroll: false,
      pauseInFlight: false,
      jobState: running,
      pendingJobState: null,
    );
    final rows = [
      const CoverageVerdict(
        path: '/a',
        sizeBytes: 1,
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: '',
        coverageSource: 'ai',
      ),
    ];
    expect(aiCoverageJobBannerVerdictRows(context, rows), isEmpty);
  });

  test('terminal job status covers paused completed and cancelled', () {
    const pausedJob = CoverageJobState(
      snapshotId: 'snap',
      rootPath: '/',
      planVersion: 3,
      cursor: 0,
      totalUnclassified: 0,
      analyzedFiles: 0,
      preClassifiedCount: 0,
      status: CoverageJobStatus.paused,
      pauseReason: CoveragePauseReason.manual,
      usedTokens: 0,
      usedCredits: 0,
      budgetTokens: 0,
      budgetCredits: 0,
      updatedAtMs: 1,
    );
    expect(aiCoverageJobStateIsTerminal(pausedJob), isTrue);
    expect(
      aiCoverageJobStateIsTerminal(
        const CoverageJobState(
          snapshotId: 'snap',
          rootPath: '/',
          planVersion: 3,
          cursor: 0,
          totalUnclassified: 0,
          analyzedFiles: 0,
          preClassifiedCount: 0,
          status: CoverageJobStatus.running,
          pauseReason: CoveragePauseReason.manual,
          usedTokens: 0,
          usedCredits: 0,
          budgetTokens: 0,
          budgetCredits: 0,
          updatedAtMs: 2,
        ),
      ),
      isFalse,
    );
  });

  test('verdict rows merge by path and sort small result sets', () {
    final merged = aiCoverageMergeVerdictRows(
      const [
        CoverageVerdict(
          path: '/a',
          sizeBytes: 1,
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: '',
          coverageSource: 'ai',
        ),
      ],
      const [
        CoverageVerdict(
          path: '/b',
          sizeBytes: 2,
          verdict: 'review_needed',
          confidence: 'medium',
          reason: '',
          coverageSource: 'ai',
        ),
        CoverageVerdict(
          path: '/a',
          sizeBytes: 9,
          verdict: 'keep',
          confidence: 'high',
          reason: '',
          coverageSource: 'ai',
        ),
      ],
      heavyThreshold: 200,
    );
    expect(merged.map((row) => row.path), ['/a', '/b']);
    expect(merged.first.sizeBytes, 9);
  });
}
