import '../../../ai/ai_provider.dart';
import '../../../ai/ai_settings_store.dart';
import '../../../ai/ai_analysis_activity_model.dart';
import '../../../ai/coverage_job_state.dart';
import '../../../ai/coverage_models.dart';
import '../../../ai/coverage_ui_helpers.dart';
import '../../../ai/coverage_verdict_store.dart';
import '../../../ai/ai_result_groups.dart';
import '../../../ai/ai_result_overview.dart';
import '../models/ai_analysis_workspace_display_state.dart';

/// Public result filters mirroring the workspace's filter segments.
enum WorkspaceResultFilter { all, review, selected, safeToRemove, keep }

/// Public result sort orders.
enum WorkspaceResultSort { priority, size }

/// Public review decisions applied to individual result items.
enum WorkspaceReviewDecision { pending, include, keep }

/// Public results navigation modes.
enum WorkspaceResultsView { overview, reviewQueue, detailList }

/// Public directory-type segments shown on the conclusions page.
enum WorkspaceDirectoryTypeFilter { safe, review, keep }

/// Context-free status shown on the workspace header hub chip.
enum WorkspaceHubStatus { awaitingAnalysis, analyzing, partial, ready }

/// Immutable snapshot of bootstrap and candidate loading state.
final class AiWorkspaceBootstrapState {
  const AiWorkspaceBootstrapState({
    this.candidatesPending = true,
    this.hasProvider = false,
    this.hasExistingResult = false,
    this.loadedFromCache = false,
    this.truncated = false,
    this.estimatedTokens = 0,
    this.rootPath = '',
    this.resultCacheKey = '',
    this.error,
  });

  final bool candidatesPending;
  final bool hasProvider;
  final bool hasExistingResult;
  final bool loadedFromCache;
  final bool truncated;
  final int estimatedTokens;
  final String rootPath;
  final String resultCacheKey;
  final String? error;
}

/// Immutable snapshot of precheck and coverage-estimate context.
final class AiWorkspacePrecheckState {
  const AiWorkspacePrecheckState({
    this.snapshotId = '',
    this.mode = AiMode.off,
    this.useFullCoverage = false,
    this.platformCredits,
    this.estimatedCoverageCredits,
    this.coverageBudgetCredits,
    this.coverageHydrating = false,
    this.coverageHydrated = false,
    this.planLoadError,
    this.hasProvider = false,
    this.candidatesBootstrapPending = false,
    this.error,
    this.unknown = const [],
    this.preClassified = const [],
    this.displayUnknownCount = 0,
    this.displayPreClassifiedCount = 0,
    this.estimatedTokens = 0,
    this.estimatedByokBatchTokens = 0,
    this.truncated = false,
    this.candidatesBeforeCap = 0,
    this.unknownCandidatesSpillPath,
    this.narrativeEnabled = false,
  });

  final String snapshotId;
  final AiMode mode;
  final bool useFullCoverage;
  final int? platformCredits;
  final int? estimatedCoverageCredits;
  final int? coverageBudgetCredits;
  final bool coverageHydrating;
  final bool coverageHydrated;
  final String? planLoadError;
  final bool hasProvider;
  final bool candidatesBootstrapPending;
  final String? error;
  final List<AiCandidate> unknown;
  final List<Map<String, dynamic>> preClassified;
  final int displayUnknownCount;
  final int displayPreClassifiedCount;
  final int estimatedTokens;
  final int estimatedByokBatchTokens;
  final bool truncated;
  final int candidatesBeforeCap;
  final String? unknownCandidatesSpillPath;
  final bool narrativeEnabled;
}

/// Immutable snapshot of full-coverage job and verdict-page state.
final class AiWorkspaceCoverageState {
  AiWorkspaceCoverageState({
    this.jobState,
    this.planSummary,
    this.useFullCoverage = false,
    this.runBudgetCredits,
    this.coverageCapBelowEstimate = false,
    this.pauseInFlight = false,
    this.planLoadInFlight = false,
    this.verdictPageCount = 2,
    List<CoverageVerdict> verdictRows = const [],
    this.verdictPageLoadInFlight = false,
  }) : verdictRows = List.unmodifiable(verdictRows);

  final CoverageJobState? jobState;
  final CoveragePlanSummary? planSummary;
  final bool useFullCoverage;
  final int? runBudgetCredits;
  final bool coverageCapBelowEstimate;
  final bool pauseInFlight;
  final bool planLoadInFlight;
  final int verdictPageCount;
  final List<CoverageVerdict> verdictRows;
  final bool verdictPageLoadInFlight;
}

/// Immutable snapshot of the coverage job progress banner.
final class AiWorkspaceCoverageBannerState {
  AiWorkspaceCoverageBannerState({
    required this.job,
    List<CoverageVerdict> verdictRows = const [],
    this.planSummary,
    this.showPausedBeforeProgressNotice = false,
    this.billingModeMismatch = false,
    this.billingModeMismatchMessage,
  }) : verdictRows = List.unmodifiable(verdictRows);

  final CoverageJobState job;
  final List<CoverageVerdict> verdictRows;
  final CoveragePlanSummary? planSummary;
  final bool showPausedBeforeProgressNotice;
  final bool billingModeMismatch;
  final String? billingModeMismatchMessage;
}

/// Immutable snapshot of analysis activity and progress.
final class AiWorkspaceActivityState {
  const AiWorkspaceActivityState({
    this.analyzing = false,
    this.coverageRunning = false,
    this.macroPhase = AiActivityMacroPhase.loading,
    this.useFullCoverage = false,
    this.candidatesBootstrapPending = false,
    this.coverageHydrating = false,
    this.coverageHydrated = false,
    this.resultsLayoutPending = false,
    this.resumingJob = false,
    this.candidateCount = 0,
    this.mode = AiMode.off,
    this.job,
    this.pauseInFlight = false,
    this.freezeActiveMotion = false,
    this.showCompact = false,
  });

  final bool analyzing;
  final bool coverageRunning;
  final AiActivityMacroPhase macroPhase;
  final bool useFullCoverage;
  final bool candidatesBootstrapPending;
  final bool coverageHydrating;
  final bool coverageHydrated;
  final bool resultsLayoutPending;
  final bool resumingJob;
  final int candidateCount;
  final AiMode mode;
  final CoverageJobState? job;
  final bool pauseInFlight;
  final bool freezeActiveMotion;
  final bool showCompact;
}

/// Immutable snapshot of normalized results, selection and query state.
final class AiWorkspaceResultsState {
  AiWorkspaceResultsState({
    List<AiVerdict> verdicts = const [],
    Set<String> selectedPaths = const {},
    Map<String, WorkspaceReviewDecision> reviewDecisions = const {},
    Set<String> expandedGroupPaths = const {},
    Map<String, int> expandedGroupItemLimits = const {},
    Set<String> expandedReviewPaths = const {},
    Map<String, int> sizeByPath = const {},
    List<AiResultGroup> groups = const [],
    List<AiWorkspaceVisibleResultGroup> visibleGroups = const [],
    this.overview,
    this.safeBytes = 0,
    this.safeItemCount = 0,
    this.reviewCount = 0,
    this.selectedBytes = 0,
    this.directoryBucketCount = 0,
    this.showsFilteredItems = false,
    this.loadedEmptySuggestions = false,
    this.hasExistingResult = false,
    this.coveragePlanIsLocalOnly = true,
    this.canStartWorkspaceAnalysis = false,
    this.resultsLayoutPending = false,
    this.showsLocalPreviewHint = false,
    this.classificationProvenance = const ClassificationProvenanceSummary(
      bootstrapLocalCount: 0,
      localRuleCount: 0,
      aiResolvedCount: 0,
      aiPlannedCount: null,
      phase: ClassificationAiPhase.notStarted,
    ),
    this.coverageRunPresentation = const CoverageRunPresentation(
      localPhase: CoverageLocalPhase.notStarted,
      localResolvedFiles: 0,
      localPlannedFiles: null,
      localProgressFraction: null,
      aiPhase: ClassificationAiPhase.notStarted,
      aiResolvedFiles: 0,
      aiPlannedFiles: null,
      aiProgressFraction: null,
    ),
    this.errorMessage,
    this.directoryTypeFilter = WorkspaceDirectoryTypeFilter.safe,
    this.reviewQueueDirectoryFilter,
    this.reviewQueueInitialPending = 0,
    this.reviewQueueDecided = 0,
    List<AiVerdict> reviewQueuePending = const [],
    this.query = '',
    this.directoryFilter,
    this.filter = WorkspaceResultFilter.all,
    this.sort = WorkspaceResultSort.priority,
  }) : verdicts = List.unmodifiable(verdicts),
       selectedPaths = Set.unmodifiable(selectedPaths),
       reviewDecisions = Map.unmodifiable(reviewDecisions),
       expandedGroupPaths = Set.unmodifiable(expandedGroupPaths),
       expandedGroupItemLimits = Map.unmodifiable(expandedGroupItemLimits),
       expandedReviewPaths = Set.unmodifiable(expandedReviewPaths),
       sizeByPath = Map.unmodifiable(sizeByPath),
       groups = List.unmodifiable(groups),
       visibleGroups = List.unmodifiable(visibleGroups),
       reviewQueuePending = List.unmodifiable(reviewQueuePending);

  final List<AiVerdict> verdicts;
  final Set<String> selectedPaths;
  final Map<String, WorkspaceReviewDecision> reviewDecisions;
  final Set<String> expandedGroupPaths;
  final Map<String, int> expandedGroupItemLimits;
  final Set<String> expandedReviewPaths;
  final Map<String, int> sizeByPath;
  final List<AiResultGroup> groups;
  final List<AiWorkspaceVisibleResultGroup> visibleGroups;
  final AiAnalysisConclusionOverview? overview;
  final int safeBytes;
  final int safeItemCount;
  final int reviewCount;
  final int selectedBytes;
  final int directoryBucketCount;
  final bool showsFilteredItems;
  final bool loadedEmptySuggestions;
  final bool hasExistingResult;
  final bool coveragePlanIsLocalOnly;
  final bool canStartWorkspaceAnalysis;
  final bool resultsLayoutPending;
  final bool showsLocalPreviewHint;
  final ClassificationProvenanceSummary classificationProvenance;
  final CoverageRunPresentation coverageRunPresentation;
  final String? errorMessage;
  final WorkspaceDirectoryTypeFilter directoryTypeFilter;
  final String? reviewQueueDirectoryFilter;
  final int reviewQueueInitialPending;
  final int reviewQueueDecided;
  final List<AiVerdict> reviewQueuePending;
  final String query;
  final String? directoryFilter;
  final WorkspaceResultFilter filter;
  final WorkspaceResultSort sort;
}

/// Immutable visible group row used by the results list view.
final class AiWorkspaceVisibleResultGroup {
  const AiWorkspaceVisibleResultGroup({
    required this.group,
    required this.items,
    required this.totalBytes,
    required this.actionableCount,
  });

  final AiResultGroup group;
  final List<AiVerdict> items;
  final int totalBytes;
  final int actionableCount;
}

/// Immutable snapshot of the optional conclusion narrative.
final class AiWorkspaceNarrativeState {
  const AiWorkspaceNarrativeState({
    this.enabled = false,
    this.auto = true,
    this.loading = false,
    this.text,
    this.signature,
    this.generation = 0,
  });

  final bool enabled;
  final bool auto;
  final bool loading;
  final String? text;
  final String? signature;
  final int generation;
}

/// Immutable snapshot of delete progress and retry state.
final class AiWorkspaceDeleteState {
  AiWorkspaceDeleteState({
    this.busy = false,
    List<String> retryTargets = const [],
    this.partialDeleteFailedCount,
    this.partialDeleteFreedBytes,
  }) : retryTargets = List.unmodifiable(retryTargets);

  final bool busy;
  final List<String> retryTargets;
  final int? partialDeleteFailedCount;
  final int? partialDeleteFreedBytes;
}

/// Immutable snapshot of the page-level phase and results navigation.
final class AiWorkspaceOverviewState {
  const AiWorkspaceOverviewState({
    this.displayState = AiWorkspaceDisplayState.loading,
    this.resultsView = WorkspaceResultsView.overview,
    this.deleting = false,
    this.analyzing = false,
    this.phaseStep = 1,
    this.hubStatus,
    this.scopeExpandedManual,
  });

  final AiWorkspaceDisplayState displayState;
  final WorkspaceResultsView resultsView;
  final bool deleting;
  final bool analyzing;
  final int phaseStep;
  final WorkspaceHubStatus? hubStatus;
  final bool? scopeExpandedManual;
}

/// Immutable aggregate of every workspace state section.
final class AiAnalysisWorkspaceViewState {
  AiAnalysisWorkspaceViewState({
    AiWorkspaceBootstrapState? bootstrap,
    AiWorkspacePrecheckState? precheck,
    AiWorkspaceCoverageState? coverage,
    AiWorkspaceActivityState? activity,
    AiWorkspaceResultsState? results,
    AiWorkspaceNarrativeState? narrative,
    AiWorkspaceDeleteState? delete,
    AiWorkspaceOverviewState? overview,
    this.coverageBanner,
  }) : bootstrap = bootstrap ?? const AiWorkspaceBootstrapState(),
       precheck = precheck ?? const AiWorkspacePrecheckState(),
       coverage = coverage ?? AiWorkspaceCoverageState(),
       activity = activity ?? const AiWorkspaceActivityState(),
       results = results ?? AiWorkspaceResultsState(),
       narrative = narrative ?? const AiWorkspaceNarrativeState(),
       delete = delete ?? AiWorkspaceDeleteState(),
       overview = overview ?? const AiWorkspaceOverviewState();

  final AiWorkspaceBootstrapState bootstrap;
  final AiWorkspacePrecheckState precheck;
  final AiWorkspaceCoverageState coverage;
  final AiWorkspaceActivityState activity;
  final AiWorkspaceResultsState results;
  final AiWorkspaceNarrativeState narrative;
  final AiWorkspaceDeleteState delete;
  final AiWorkspaceOverviewState overview;
  final AiWorkspaceCoverageBannerState? coverageBanner;

  AiAnalysisWorkspaceViewState copyWith({
    AiWorkspaceBootstrapState? bootstrap,
    AiWorkspacePrecheckState? precheck,
    AiWorkspaceCoverageState? coverage,
    AiWorkspaceActivityState? activity,
    AiWorkspaceResultsState? results,
    AiWorkspaceNarrativeState? narrative,
    AiWorkspaceDeleteState? delete,
    AiWorkspaceOverviewState? overview,
    AiWorkspaceCoverageBannerState? coverageBanner,
  }) {
    return AiAnalysisWorkspaceViewState(
      bootstrap: bootstrap ?? this.bootstrap,
      precheck: precheck ?? this.precheck,
      coverage: coverage ?? this.coverage,
      activity: activity ?? this.activity,
      results: results ?? this.results,
      narrative: narrative ?? this.narrative,
      delete: delete ?? this.delete,
      overview: overview ?? this.overview,
      coverageBanner: coverageBanner ?? this.coverageBanner,
    );
  }
}
