import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../ai/ai_analysis_gateway.dart';
import '../../../ai/ai_coverage_coordinator.dart';
import '../../../ai/ai_provider.dart';
import '../../../ai/ai_result_overview.dart';
import '../../../ai/ai_settings_store.dart';
import '../../../ai/coverage_job_state.dart';
import '../../../ai/coverage_verdict_store.dart';
import '../ai_analysis_workspace_config.dart';
import '../ports/workspace_ports.dart';
import '../views/ai_analysis_workspace_messages.dart';
import '../views/ai_analysis_workspace_view_state.dart';
import '../../../widgets/ai_results_hub.dart';
import 'ai_analysis_bootstrap_controller.dart';
import 'ai_analysis_coverage_controller.dart';
import 'ai_analysis_delete_controller.dart';
import 'ai_analysis_results_controller.dart';
import 'ai_analysis_workspace_controller.dart';

/// Public runtime surface of the AI workspace page controller. Flow hosts,
/// the view-state assembler and the actions adapter are wired against this
/// interface so the page file only owns composition, lifecycle and state.
abstract interface class AiAnalysisWorkspacePageSurface {
  AiAnalysisWorkspaceConfig get page;
  AiAnalysisWorkspaceMessages get messages;
  bool get disposed;
  bool get workspaceInitialized;
  AiWorkspaceDisplayState get displayState;
  AiWorkspaceDisplayState get displayPhase;
  void setDisplayPhase(AiWorkspaceDisplayState value);

  AiAnalysisWorkspaceController get workspaceController;
  AiAnalysisBootstrapController get bootstrapController;
  AiAnalysisCoverageController get coverageController;
  AiAnalysisResultsController get resultsController;
  AiAnalysisDeleteController get deleteController;
  AiWorkspacePorts get ports;
  set ports(AiWorkspacePorts value);
  AiCoverageJobs get coverageJobs;

  bool get analyzing;
  set analyzing(bool value);
  String? get error;
  set error(String? value);
  bool get deleting;
  bool get useFullCoverage;
  set useFullCoverage(bool value);
  bool get hasProvider;
  bool get candidatesBootstrapPending;
  bool get loadedEmptySuggestions;
  set loadedEmptySuggestions(bool value);
  bool? get scopeExpandedManual;
  set scopeExpandedManual(bool? value);
  bool get coveragePlanIsLocalOnly;
  bool get canStartWorkspaceAnalysis;
  bool get showsFilteredItems;
  bool get coverageResultsLoadTruncated;
  bool get hasExistingResult;
  bool get truncated;
  bool get runCapBelowBufferedEstimate;

  int? get coverageBudgetCredits;
  set coverageBudgetCredits(int? value);
  bool get coverageCapBelowEstimate;
  set coverageCapBelowEstimate(bool value);
  bool get coverageUiPrefersAnalyzingPhase;
  set coverageUiPrefersAnalyzingPhase(bool value);
  bool get coverageUserEngagedFullRun;
  set coverageUserEngagedFullRun(bool value);
  int? get coverageStalePausedUpdatedAtMs;
  set coverageStalePausedUpdatedAtMs(int? value);
  bool get coveragePauseInFlight;
  set coveragePauseInFlight(bool value);

  bool get deferCoverageJobUiForScroll;
  set deferCoverageJobUiForScroll(bool value);
  bool get resultsUserScrolling;
  set resultsUserScrolling(bool value);
  bool get resultsLayoutPending;
  set resultsLayoutPending(bool value);
  Timer? get jobStateCoalesceTimer;
  set jobStateCoalesceTimer(Timer? value);
  CoverageJobState? get pendingCoverageJobState;
  set pendingCoverageJobState(CoverageJobState? value);
  List<CoverageVerdict>? get pendingVerdictRowsAfterScroll;
  set pendingVerdictRowsAfterScroll(List<CoverageVerdict>? value);
  bool get pendingVerdictRowsPreserveUi;
  set pendingVerdictRowsPreserveUi(bool value);

  WorkspaceResultsView get resultsView;
  set resultsView(WorkspaceResultsView value);
  WorkspaceDirectoryTypeFilter get directoryTypeFilterPublic;
  void setDirectoryTypeFilterValue(WorkspaceDirectoryTypeFilter filter);

  AiMode get mode;
  int? get platformCredits;
  int? get estimatedTokens;
  int? get estimatedByokBatchTokens;
  int get candidatesBeforeCap;
  int get displayUnknownCount;
  int get displayPreClassifiedCount;
  String? get rootPath;
  String? get unknownCandidatesSpillPath;
  String? get reviewQueueDirectoryFilter;
  String? get resultsDirectoryFilter;
  String get resultsQuery;
  String get targetLabel;

  List<AiCandidate> get unknown;
  List<Map<String, dynamic>> get preClassified;
  List<AiVerdict> get verdicts;
  Set<String> get selected;
  Map<String, WorkspaceReviewDecision> get reviewDecisions;
  Set<String> get expandedGroupPaths;
  Map<String, int> get expandedGroupItemLimits;
  Set<String> get expandedReviewPaths;
  Map<String, int> get sizeByPath;
  List<String> get retryTargets;
  int? get partialDeleteFailedCount;
  int? get partialDeleteFreedBytes;
  int? get reviewQueueSessionInitialPending;

  WorkspaceResultFilter get resultFilterMode;
  WorkspaceResultSort get resultSortMode;
  int? get selectedBytes;
  int get verdictPageCount;
  int get heavyResultsLayoutThresholdValue;
  AiWorkspaceCoverage get coverageAccess;

  void mutate(VoidCallback update);
  int beginOperation();
  bool isCurrent(int generation);
  void notifyListeners();

  void initialize({bool bootstrap});
  Future<void> runBootstrap();
  Future<void> runBootstrapPrecheckContext(int generation);
  Future<bool> runLoadPreviousResult({int? bootstrapGeneration});
  Future<void> runStartAnalysis();

  void resetForBootstrap();
  void resetResultsScroll();
  void setScopeExpandedManual(bool? value);
  Future<void> invalidateConclusionNarrative();
  Future<void> loadNarrativeSettings();
  Future<void> runConclusionNarrativeInternal({
    required bool fresh,
    bool manual,
    AiProvider? provider,
  });

  void enterOverviewHub();
  void enterResultsPhase({required bool showOverview});
  void handleWorkspaceBack();
  void toggleEmbeddedScopeExpanded();
  void openDetailPage({String? directoryPath});
  void openReviewQueue({String? directoryPath});
  void openDetailList({
    WorkspaceResultFilter? initialFilter,
    String? directoryPath,
  });
  ResultsHubMode get resultsHubMode;
  bool isLightweightAnalyzingUi();
  bool shouldShowResultsLocalPreviewHint();
  bool shouldShowCompactActivityCard();
  List<AiVerdict> unanalyzedVerdicts();
  List<CoverageVerdict> coverageJobBannerVerdictRows();
  bool coverageJobStateShowsBanner(CoverageJobState? state);
  bool freezeActivityMotionForJob(CoverageJobState? job);
  bool jobBillingMismatch(CoverageJobState job);
  String? jobBillingMismatchMessage(CoverageJobState job);
  AiResultOverviewBuildInput buildConclusionOverviewInput();
  AiResultsProjection get resultsProjection;

  void bumpCoverageVerdictPagesForTerminal(CoverageJobState state);
  void scheduleCoveragePlanSummaryForBannerIfNeeded();
  void invalidateResultGroups();
  void invalidateVisibleGroups();
  void resetResultsPresentation();
  void syncSelectedToKnownPaths();
  Set<String> defaultExpandedGroupPaths();
  void queueCoverageVerdictRowsUntilScrollIdle(
    List<CoverageVerdict> rows, {
    required bool preserveUiState,
  });
  Future<void> applyHeavyResultsPresentation({
    required List<AiVerdict> verdicts,
    required bool preserveUiState,
    required Map<String, WorkspaceReviewDecision>? savedReview,
    required Set<String>? savedSelected,
    required Set<String>? savedExpandedGroups,
    required Set<String>? savedExpandedReviews,
  });
  Future<void> refreshVerdictsInternal({
    bool incremental,
    bool allowNativeLocalBackfill,
    bool preferReadAll,
  });

  void markCoverageRunEngaged();
  Future<void> startFullCoverageAnalysis();
  Future<void> pauseFullCoverageFromBanner();
  void onResultsScrollStart();
  void onResultsScrollEnd({double? pixels, double? maxScrollExtent});
  Future<void> ensureUnknownCandidatesLoaded();
  Future<void> raiseConfiguredCoverageCap();
  Future<void> openLocalOnlyResults();
  Future<void> deleteSelected();
  void onCoverageJobState(CoverageJobState state);
  void handleBusyChanged(bool busy);
  String formatBytes(num? bytes);
  WorkspaceAnalyticsPort get analytics;
}
