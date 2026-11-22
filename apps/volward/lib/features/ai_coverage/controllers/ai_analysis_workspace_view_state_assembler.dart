import '../../../ai/ai_analysis_activity_model.dart';
import '../../../ai/ai_provider.dart';
import '../../../ai/coverage_job_state.dart';
import '../../../ai/coverage_models.dart';
import '../../../ai/coverage_ui_helpers.dart';
import '../../../ai/coverage_verdict_store.dart';
import '../../../ai/ai_settings_store.dart';
import '../../../widgets/ai_results_hub.dart';
import '../models/ai_analysis_workspace_display_state.dart';
import '../views/ai_analysis_workspace_messages.dart';
import '../views/ai_analysis_workspace_view_state.dart';
import 'ai_analysis_workspace_result_helpers.dart';
import 'ai_analysis_results_controller.dart';

/// Context-free snapshot the page controller exposes to the view-state
/// assembler. Every getter is a one-line forward; assembly logic lives here
/// so the page controller stays a composition and delegation layer.
abstract interface class AiAnalysisWorkspaceViewStateSource {
  AiAnalysisWorkspaceMessages get messages;
  AiAnalysisResultsController get resultsController;

  AiWorkspaceBootstrapState get bootstrapState;
  AiWorkspacePrecheckState get precheckOwnerState;
  AiWorkspaceCoverageState get coverageState;
  AiWorkspaceNarrativeState get narrativeState;

  bool get useFullCoverage;
  bool get hasProvider;
  bool get candidatesBootstrapPending;
  bool get coverageHydrating;
  bool get coverageHydrated;
  bool get analyzing;
  bool get deleting;
  bool get resultsLayoutPending;
  bool get pauseInFlight;
  bool get stalePausedJob;
  bool get showsFilteredItems;
  bool get loadedEmptySuggestions;
  bool get hasExistingResult;
  bool get coveragePlanIsLocalOnly;
  bool get canStartWorkspaceAnalysis;
  bool get showsLocalPreviewHint;
  bool get coverageResultsLoadTruncated;
  bool get truncated;

  int? get estimatedCoverageCredits;
  int? get coverageBudgetCredits;
  int? get selectedBytes;
  int get displayUnknownCount;
  int get displayPreClassifiedCount;
  int get estimatedTokens;
  int get estimatedByokBatchTokens;
  int get candidatesBeforeCap;
  int? get reviewQueueSessionInitialPending;

  String? get error;
  String? get coveragePlanLoadError;
  String? get unknownCandidatesSpillPath;
  String? get reviewQueueDirectoryFilter;
  String? get resultsDirectoryFilter;
  String? get rootPath;
  String get resultsQuery;
  String get targetLabel;

  AiMode get mode;
  AiWorkspaceDisplayState get displayState;
  WorkspaceResultsView get resultsView;
  WorkspaceResultFilter get resultFilter;
  WorkspaceResultSort get resultSort;
  WorkspaceDirectoryTypeFilter get directoryTypeFilter;
  bool? get scopeExpandedManual;

  List<AiCandidate> get unknownCandidates;
  List<Map<String, dynamic>> get preClassified;
  List<AiVerdict> get verdicts;
  List<CoverageVerdict> get coverageVerdictRows;
  Set<String> get selected;
  Map<String, WorkspaceReviewDecision> get reviewDecisions;
  Set<String> get expandedGroupPaths;
  Map<String, int> get expandedGroupItemLimits;
  Set<String> get expandedReviewPaths;
  Map<String, int> get sizeByPath;
  List<String> get retryTargets;

  int? get partialDeleteFailedCount;
  int? get partialDeleteFreedBytes;
  int? get platformCredits;

  CoverageJobState? get coverageJobState;
  CoverageJobState? get debugCoverageJobState;
  CoveragePlanSummary? get coveragePlanSummary;
  CoverageJobState? get bannerJob;
  List<CoverageVerdict> get bannerVerdictRows;

  bool showsBanner(CoverageJobState? state);
  bool freezeActivityMotion(CoverageJobState? job);
  bool jobBillingModeMismatch(CoverageJobState job);
  String? jobBillingModeMismatchMessage(CoverageJobState job);
  bool showCompactActivityCard();
  ResultsHubMode get resultsHubMode;
  List<AiVerdict> unanalyzedVerdicts();
}

/// Owns every immutable view-state projection. No widgets, no controller.
abstract final class AiAnalysisWorkspaceViewStateAssembler {
  static AiAnalysisWorkspaceViewState buildViewState(
    AiAnalysisWorkspaceViewStateSource source,
  ) {
    return AiAnalysisWorkspaceViewState(
      bootstrap: source.bootstrapState,
      precheck: buildPrecheckState(source),
      coverage: source.coverageState,
      activity: buildActivityState(source),
      results: buildResultsState(source),
      narrative: source.narrativeState,
      delete: AiWorkspaceDeleteState(
        busy: source.deleting,
        retryTargets: source.retryTargets,
        partialDeleteFailedCount: source.partialDeleteFailedCount,
        partialDeleteFreedBytes: source.partialDeleteFreedBytes,
      ),
      overview: buildOverviewState(source),
      coverageBanner: buildCoverageBannerState(source),
    );
  }

  static AiWorkspacePrecheckState buildPrecheckState(
    AiAnalysisWorkspaceViewStateSource source,
  ) {
    final precheck = source.precheckOwnerState;
    return AiWorkspacePrecheckState(
      snapshotId: precheck.snapshotId,
      mode: precheck.mode,
      useFullCoverage: source.useFullCoverage,
      platformCredits: precheck.platformCredits,
      estimatedCoverageCredits: source.estimatedCoverageCredits,
      coverageBudgetCredits: source.coverageBudgetCredits,
      coverageHydrating: source.coverageHydrating,
      coverageHydrated: source.coverageHydrated,
      planLoadError: source.coveragePlanLoadError,
      hasProvider: source.hasProvider,
      candidatesBootstrapPending: source.candidatesBootstrapPending,
      error: source.error,
      unknown: source.unknownCandidates,
      preClassified: source.preClassified,
      displayUnknownCount: source.displayUnknownCount,
      displayPreClassifiedCount: source.displayPreClassifiedCount,
      estimatedTokens: source.estimatedTokens,
      estimatedByokBatchTokens: source.estimatedByokBatchTokens,
      truncated: source.truncated,
      candidatesBeforeCap: source.candidatesBeforeCap,
      unknownCandidatesSpillPath: source.unknownCandidatesSpillPath,
      narrativeEnabled: source.narrativeState.enabled,
    );
  }

  static AiWorkspaceActivityState buildActivityState(
    AiAnalysisWorkspaceViewStateSource source,
  ) {
    final job = source.coverageJobState ?? source.debugCoverageJobState;
    final coverageJob =
        (source.useFullCoverage || source.debugCoverageJobState != null) &&
            job != null &&
            job.snapshotId == source.precheckOwnerState.snapshotId
        ? job
        : null;
    return AiWorkspaceActivityState(
      analyzing: source.analyzing,
      coverageRunning:
          source.coverageState.jobState?.status == CoverageJobStatus.running,
      macroPhase: _activityMacroPhase(source),
      useFullCoverage: source.useFullCoverage,
      candidatesBootstrapPending: source.candidatesBootstrapPending,
      coverageHydrating: source.coverageHydrating,
      coverageHydrated: source.coverageHydrated,
      resultsLayoutPending: source.resultsLayoutPending,
      resumingJob: source.stalePausedJob,
      candidateCount:
          coverageJob?.totalUnclassified ?? source.unknownCandidates.length,
      mode: source.mode,
      job: coverageJob,
      pauseInFlight: source.pauseInFlight,
      freezeActiveMotion: source.freezeActivityMotion(coverageJob),
      showCompact: source.showCompactActivityCard(),
    );
  }

  static AiWorkspaceOverviewState buildOverviewState(
    AiAnalysisWorkspaceViewStateSource source,
  ) {
    return AiWorkspaceOverviewState(
      displayState: source.displayState,
      resultsView: source.resultsView,
      deleting: source.deleting,
      analyzing: source.analyzing,
      phaseStep: _phaseStep(source),
      hubStatus: _hubStatus(source),
      scopeExpandedManual: source.scopeExpandedManual,
    );
  }

  static AiWorkspaceCoverageBannerState? buildCoverageBannerState(
    AiAnalysisWorkspaceViewStateSource source,
  ) {
    final job = source.bannerJob;
    if (job == null || !source.showsBanner(job)) return null;
    final billingMismatch = source.jobBillingModeMismatch(job);
    return AiWorkspaceCoverageBannerState(
      job: job,
      verdictRows: source.bannerVerdictRows,
      planSummary: source.coveragePlanSummary,
      showPausedBeforeProgressNotice:
          source.displayState == AiWorkspaceDisplayState.results,
      billingModeMismatch: billingMismatch,
      billingModeMismatchMessage: billingMismatch
          ? source.jobBillingModeMismatchMessage(job)
          : null,
    );
  }

  static AiWorkspaceResultsState buildResultsState(
    AiAnalysisWorkspaceViewStateSource source,
  ) {
    final activeSnapshotId = source.precheckOwnerState.snapshotId;
    final job = source.coverageJobState ?? source.debugCoverageJobState;
    final activeJob = job?.snapshotId == activeSnapshotId ? job : null;
    final plan = source.coveragePlanSummary;
    final activePlan = plan?.snapshotId == activeSnapshotId ? plan : null;
    final pending = pendingReviewVerdicts(
      verdicts: source.verdicts,
      reviewDecisions: source.reviewDecisions,
      sort: source.resultSort,
      sizeByPath: source.sizeByPath,
      directoryPath: source.reviewQueueDirectoryFilter,
    );
    final initialCount =
        source.reviewQueueSessionInitialPending ?? pending.length;
    final input = buildProjectionInput(source);
    final projection = source.resultsController.buildProjection(input);
    return AiWorkspaceResultsState(
      verdicts: source.verdicts,
      selectedPaths: source.selected,
      reviewDecisions: source.reviewDecisions,
      expandedGroupPaths: source.expandedGroupPaths,
      expandedGroupItemLimits: source.expandedGroupItemLimits,
      expandedReviewPaths: source.expandedReviewPaths,
      sizeByPath: source.sizeByPath,
      groups: projection.normalizedGroups,
      visibleGroups: projection.visibleGroups,
      overview: projection.overview,
      safeBytes: projection.safeBytes,
      reviewCount: projection.reviewCount,
      selectedBytes: source.selectedBytes ?? 0,
      directoryBucketCount: projection.directoryBucketCount,
      showsFilteredItems: source.showsFilteredItems,
      loadedEmptySuggestions: source.loadedEmptySuggestions,
      hasExistingResult: source.hasExistingResult,
      coveragePlanIsLocalOnly: source.coveragePlanIsLocalOnly,
      canStartWorkspaceAnalysis: source.canStartWorkspaceAnalysis,
      resultsLayoutPending: source.resultsLayoutPending,
      showsLocalPreviewHint: source.showsLocalPreviewHint,
      classificationProvenance: buildClassificationProvenanceSummary(
        job: activeJob,
        plan: activePlan,
        bootstrapPreclassifiedCount: source.displayPreClassifiedCount,
        hasProvider: source.hasProvider,
        isLocalOnlyPlan: source.coveragePlanIsLocalOnly,
      ),
      errorMessage: source.error,
      directoryTypeFilter: source.directoryTypeFilter,
      reviewQueueDirectoryFilter: source.reviewQueueDirectoryFilter,
      reviewQueueInitialPending: initialCount,
      reviewQueueDecided: (initialCount - pending.length).clamp(
        0,
        initialCount,
      ),
      reviewQueuePending: pending,
      query: source.resultsQuery,
      directoryFilter: source.resultsDirectoryFilter,
      filter: source.resultFilter,
      sort: source.resultSort,
    );
  }

  static AiActivityMacroPhase _activityMacroPhase(
    AiAnalysisWorkspaceViewStateSource source,
  ) {
    return switch (source.displayState) {
      AiWorkspaceDisplayState.loading => AiActivityMacroPhase.loading,
      AiWorkspaceDisplayState.analyzing => AiActivityMacroPhase.analyzing,
      AiWorkspaceDisplayState.results when source.analyzing =>
        AiActivityMacroPhase.analyzing,
      _ => AiActivityMacroPhase.resultsBusy,
    };
  }

  static int _phaseStep(AiAnalysisWorkspaceViewStateSource source) {
    return switch (source.displayState) {
      AiWorkspaceDisplayState.loading || AiWorkspaceDisplayState.error => 1,
      AiWorkspaceDisplayState.precheck => 2,
      AiWorkspaceDisplayState.privacy || AiWorkspaceDisplayState.analyzing => 3,
      AiWorkspaceDisplayState.results ||
      AiWorkspaceDisplayState.deleting => source.analyzing ? 3 : 4,
    };
  }

  static WorkspaceHubStatus? _hubStatus(
    AiAnalysisWorkspaceViewStateSource source,
  ) {
    if (source.resultsView != WorkspaceResultsView.overview) return null;
    if (source.displayState != AiWorkspaceDisplayState.results &&
        source.displayState != AiWorkspaceDisplayState.precheck &&
        source.displayState != AiWorkspaceDisplayState.analyzing) {
      return null;
    }
    return switch (source.resultsHubMode) {
      ResultsHubMode.awaitingAnalysis => WorkspaceHubStatus.awaitingAnalysis,
      ResultsHubMode.analyzing => WorkspaceHubStatus.analyzing,
      ResultsHubMode.ready => WorkspaceHubStatus.ready,
    };
  }

  static AiResultsProjectionInput buildProjectionInput(
    AiAnalysisWorkspaceViewStateSource source,
  ) {
    final fingerprint = source.coverageJobState?.fingerprint;
    return AiResultsProjectionInput(
      verdicts: source.verdicts,
      selected: source.selected,
      reviewDecisions: source.reviewDecisions,
      expandedGroupPaths: source.expandedGroupPaths,
      expandedGroupItemLimits: source.expandedGroupItemLimits,
      expandedReviewPaths: source.expandedReviewPaths,
      sizeByPath: source.sizeByPath,
      searchTextByPath: {
        for (final verdict in source.verdicts)
          verdict.path: _resultSearchText(source, verdict),
      },
      preClassified: source.preClassified,
      unanalyzedVerdicts: source.unanalyzedVerdicts(),
      rootPath: source.rootPath ?? '',
      targetLabel: source.targetLabel,
      useFullCoverage: source.useFullCoverage,
      truncated:
          source.truncated ||
          (fingerprint?.truncated ?? false) ||
          source.coverageResultsLoadTruncated,
      rootSizeBytesHint: fingerprint != null && fingerprint.rootSizeBytes > 0
          ? fingerprint.rootSizeBytes
          : null,
      filter: source.resultFilter,
      sort: source.resultSort,
      query: source.resultsQuery,
      directoryFilter: source.resultsDirectoryFilter,
      showsFilteredItems: source.showsFilteredItems,
      heavyResultsLayoutThreshold: 200,
      aiResultGroupDisplayItemCap: 512,
      firstLevelDirectoryPaths: scanRootFirstLevelDirectoryPaths(
        rootPath: source.rootPath ?? '',
        unknown: source.unknownCandidates,
        preClassified: source.preClassified,
        coverageVerdictRows: source.coverageVerdictRows,
        verdicts: source.verdicts,
      ),
      directoryPathsForGrouping: directoryPathsForGrouping(
        unknown: source.unknownCandidates,
        preClassified: source.preClassified,
      ).toSet(),
      coverageResultsLoadTruncated: source.coverageResultsLoadTruncated,
      analyzedItemCountOverride: source.coverageResultsLoadTruncated
          ? source.coverageJobState?.analyzedFiles
          : null,
    );
  }

  static String _resultSearchText(
    AiAnalysisWorkspaceViewStateSource source,
    AiVerdict item,
  ) {
    return [
      item.path,
      item.reason,
      item.cleanupSource ?? '',
      _cleanupSourceLabel(source, item) ?? '',
      item.cleanupHint ?? '',
      _retentionHintLabel(source, item) ?? '',
      _cleanupMetaLabel(source, item) ?? '',
    ].join('\n');
  }

  static String? _cleanupMetaLabel(
    AiAnalysisWorkspaceViewStateSource source,
    AiVerdict item,
  ) {
    final parts = <String>[
      if (_cleanupSourceLabel(source, item) case final value?) value,
      if (_retentionHintLabel(source, item) case final value?) value,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String? _cleanupSourceLabel(
    AiAnalysisWorkspaceViewStateSource source,
    AiVerdict item,
  ) {
    final value = item.cleanupSource;
    if (value == null || value.isEmpty) return null;
    final l10n = source.messages.l10n;
    return switch (value) {
      'ai_tool_cache' => l10n.aiCleanupSourceAiToolCache,
      'ai_generated_output' => l10n.aiCleanupSourceAiGeneratedOutput,
      'system_temp' => l10n.aiCleanupSourceSystemTemp,
      _ => value,
    };
  }

  static String? _retentionHintLabel(
    AiAnalysisWorkspaceViewStateSource source,
    AiVerdict item,
  ) {
    final parts = <String>[
      if (item.retentionDays != null)
        source.messages.l10n.aiCleanupRetentionDays(item.retentionDays!),
      if (item.cleanupHint case final hint? when hint.isNotEmpty) hint,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
