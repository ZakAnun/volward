// ignore_for_file: annotate_overrides, unnecessary_overrides

import 'dart:async';

import '../../../ai/ai_analysis_gateway.dart';
import '../../../ai/ai_provider.dart';
import '../../../ai/ai_result_overview.dart';
import '../../../ai/ai_settings_store.dart';
import '../../../ai/coverage_job_state.dart';
import '../../../ai/coverage_models.dart';
import '../../../ai/coverage_pause_messages.dart';
import '../../../ai/coverage_verdict_store.dart';
import '../models/ai_analysis_workspace_display_state.dart';
import '../ports/workspace_ports.dart';
import '../views/ai_analysis_workspace_presenter.dart';
import '../views/ai_analysis_workspace_view_state.dart';
import 'ai_analysis_bootstrap_controller.dart';
import 'ai_analysis_coverage_budget_flow.dart';
import 'ai_analysis_coverage_controller.dart';
import 'ai_analysis_coverage_job_flow.dart';
import 'ai_analysis_coverage_start_flow.dart';
import 'ai_analysis_quick_flow.dart';
import 'ai_analysis_results_flow.dart';
import 'ai_analysis_workspace_actions_adapter.dart';
import 'ai_analysis_workspace_page_surface.dart';
import 'ai_analysis_workspace_view_state_assembler.dart';

/// Interface wiring for [AiAnalysisWorkspacePageController]. Members that the
/// page already exposes under the exact interface signature are satisfied by
/// the page body; this mixin only forwards the mapped surface members.
mixin AiAnalysisWorkspaceHostMixin
    implements
        AiAnalysisWorkspacePageSurface,
        AiCoverageBudgetFlowHost,
        AiCoverageJobFlowHost,
        AiCoverageStartFlowHost,
        AiQuickFlowHost,
        AiResultsFlowHost,
        AiAnalysisWorkspaceViewStateSource,
        AiAnalysisWorkspaceActionsTarget {
  // View-state source mappings ---------------------------------------------
  AiWorkspaceBootstrapState get bootstrapState =>
      bootstrapController.bootstrapState;
  AiWorkspacePrecheckState get precheckOwnerState =>
      bootstrapController.precheckState;
  AiWorkspaceCoverageState get coverageState =>
      coverageController.coverageState;
  AiWorkspaceNarrativeState get narrativeState =>
      resultsController.narrativeState;
  bool get coverageHydrating => coverageController.hydrating;
  bool get coverageHydrated => coverageController.hydrated;
  bool get showsLocalPreviewHint => shouldShowResultsLocalPreviewHint();
  List<AiCandidate> get unknownCandidates => unknown;
  bool get pauseInFlight => coveragePauseInFlight;
  bool get stalePausedJob => coverageStalePausedUpdatedAtMs != null;
  int? get estimatedCoverageCredits => coverageController.estimatedCredits;
  String? get coveragePlanLoadError => coverageController.planLoadError;
  String get targetLabel => page.targetLabel;
  WorkspaceResultFilter get resultFilter => resultFilterMode;
  WorkspaceResultSort get resultSort => resultSortMode;
  WorkspaceDirectoryTypeFilter get directoryTypeFilter =>
      directoryTypeFilterPublic;
  List<CoverageVerdict> get coverageVerdictRows =>
      coverageController.verdictRows;
  CoverageJobState? get coverageJobState => coverageController.jobState;
  CoveragePlanSummary? get coveragePlanSummary =>
      coverageController.planSummary;
  CoverageJobState? get bannerJob =>
      coverageController.jobState ?? page.debugCoverageJobState;
  List<CoverageVerdict> get bannerVerdictRows => coverageJobBannerVerdictRows();
  bool showsBanner(CoverageJobState? state) =>
      coverageJobStateShowsBanner(state);
  bool freezeActivityMotion(CoverageJobState? job) =>
      freezeActivityMotionForJob(job);
  bool jobBillingModeMismatch(CoverageJobState job) => jobBillingMismatch(job);
  String? jobBillingModeMismatchMessage(CoverageJobState job) =>
      jobBillingMismatchMessage(job);
  bool showCompactActivityCard() => shouldShowCompactActivityCard();

  // Coverage job flow mappings ----------------------------------------------
  String get snapshotId => page.snapshotId;
  Object? get coverageOwner => page.coverageOwner;
  AiAnalysisWorkspacePresenter? get presenter => page.presenter;
  int get operationGeneration => workspaceController.operationGeneration;
  AiWorkspaceDisplayState get phase => displayPhase;
  set phase(AiWorkspaceDisplayState value) => setDisplayPhase(value);
  bool get uiPrefersAnalyzingPhase => coverageUiPrefersAnalyzingPhase;
  set uiPrefersAnalyzingPhase(bool value) =>
      coverageUiPrefersAnalyzingPhase = value;
  bool get userEngagedFullRun => coverageUserEngagedFullRun;
  int? get stalePausedUpdatedAtMs => coverageStalePausedUpdatedAtMs;
  set stalePausedUpdatedAtMs(int? value) =>
      coverageStalePausedUpdatedAtMs = value;
  set pauseInFlight(bool value) => coveragePauseInFlight = value;
  bool get lightweightAnalyzingUi => isLightweightAnalyzingUi();
  int get verdictPageCount => coverageController.verdictPageCount;
  void bumpVerdictPagesForTerminal(CoverageJobState state) =>
      bumpCoverageVerdictPagesForTerminal(state);
  void schedulePlanSummaryForBannerIfNeeded() =>
      scheduleCoveragePlanSummaryForBannerIfNeeded();
  void queueVerdictRowsUntilScrollIdle(
    List<CoverageVerdict> rows, {
    required bool preserveUiState,
  }) => queueCoverageVerdictRowsUntilScrollIdle(
    rows,
    preserveUiState: preserveUiState,
  );
  String? failedReasonForState(CoverageJobState state) {
    if (state.pauseReason != CoveragePauseReason.failed) return null;
    return messages.l10n.aiCoverageFailedReason(
      coverageFailedReasonCategory(
        messages.l10n,
        state.pauseDetail,
        pauseMessage: state.pauseMessage,
      ),
    );
  }

  Future<void> refreshVerdictsFromStore({required bool incremental}) {
    return refreshVerdictsInternal(incremental: incremental);
  }

  Future<void> maybeRunConclusionNarrative({required bool fresh}) {
    return runConclusionNarrativeInternal(fresh: fresh);
  }

  // Budget flow mappings ----------------------------------------------------
  WorkspaceSettingsPort get settings => ports.settings;
  AiAnalysisGateway get gateway => page.gateway;
  int get coverageOperationGeneration =>
      workspaceController.operationGeneration;
  bool isCoverageCurrent(int generation) => isCurrent(generation);
  bool get coverageDisposed => disposed;
  AiMode get coverageMode => mode;
  void markCoverageRunEngaged() => mutate(markCoverageRunEngaged);

  // Start flow mappings -----------------------------------------------------
  AiAnalysisBootstrapController get bootstrap => bootstrapController;
  AiAnalysisCoverageController get coverage => coverageController;
  CoverageJobState? get debugCoverageJobState => page.debugCoverageJobState;
  void setResultsViewOverview() => resultsView = WorkspaceResultsView.overview;
  Future<bool> loadPreviousResult({required int generation}) =>
      runLoadPreviousResult(bootstrapGeneration: generation);
  Future<void> refreshVerdictsFromStoreWithOptions({
    required bool incremental,
    required bool allowNativeLocalBackfill,
    required bool preferReadAll,
  }) {
    return refreshVerdictsInternal(
      incremental: incremental,
      allowNativeLocalBackfill: allowNativeLocalBackfill,
      preferReadAll: preferReadAll,
    );
  }

  // Quick flow mappings -----------------------------------------------------
  int get heavyResultsLayoutThreshold => heavyResultsLayoutThresholdValue;

  // Results flow mappings ---------------------------------------------------
  AiResultOverviewBuildInput get conclusionOverviewInput =>
      buildConclusionOverviewInput();
  bool get openExternalDetailPageSupported => page.onOpenDetailPage != null;
  void openExternalDetailPage(String path) => page.onOpenDetailPage!(path);
  void exitHost() => page.onExit();
  void deleteCompleted() => page.onDeleteCompleted();
  void setDeleteBusy(bool busy) => handleBusyChanged(busy);
  String formatBytesValue(num? bytes) => formatBytes(bytes);
  void applyDirectoryTypeFilter(WorkspaceDirectoryTypeFilter filter) =>
      setDirectoryTypeFilterValue(filter);

  // Actions target ----------------------------------------------------------
  Future<void> initializeWorkspace() async => initialize();
  Future<void> retryWorkspace() => runBootstrap();
  Future<void> loadPreviousResultWorkspace() async => runLoadPreviousResult();
  Future<void> startAnalysisWorkspace({required bool fullCoverage}) {
    useFullCoverage = fullCoverage;
    return runStartAnalysis();
  }

  Future<void> pauseCoverageWorkspace() => pauseFullCoverageFromBanner();
  Future<void> resumeCoverageWorkspace() => coverageResume(this);
  Future<void> cancelCoverageWorkspace() => coverageCancel(this);
  Future<void> restartCoverageWorkspace() => coverageRestart(this);
  Future<void> raiseCoverageBudgetWorkspace(int credits) =>
      coverageRaiseBudget(this, suggestedCredits: credits);
  Future<void> refreshPrecheckWorkspace() =>
      runBootstrapPrecheckContext(beginOperation());
  Future<void> loadUnknownCandidateSampleWorkspace() =>
      ensureUnknownCandidatesLoaded();
  Future<void> raiseConfiguredCoverageCapWorkspace() =>
      raiseConfiguredCoverageCap();
  Future<void> openLocalOnlyResultsWorkspace() => openLocalOnlyResults();
  void setResultsQueryWorkspace(String value) => resultsSetQuery(this, value);
  void setResultsDirectoryFilterWorkspace(String? path) =>
      resultsSetDirectoryFilter(this, path);
  void setResultFilterWorkspace(WorkspaceResultFilter filter) =>
      resultsSetFilter(this, filter);
  void setResultSortWorkspace(WorkspaceResultSort sort) =>
      resultsSetSort(this, sort);
  void setDirectoryTypeFilterWorkspace(WorkspaceDirectoryTypeFilter filter) =>
      resultsSetDirectoryTypeFilter(this, filter);
  void setReviewDecisionWorkspace(
    String path,
    WorkspaceReviewDecision decision,
  ) => resultsConfirmReviewDecision(this, path, decision);
  void toggleSelectionWorkspace(String path) =>
      resultsToggleSelection(this, path, !selected.contains(path));
  void setSelectionWorkspace(String path, bool selected) =>
      resultsToggleSelection(this, path, selected);
  void toggleSafeGroupWorkspace(List<String> paths, bool selected) =>
      resultsToggleSafeGroupPaths(this, paths, selected);
  void toggleGroupExpandedWorkspace(String path) =>
      resultsToggleGroupExpanded(this, path);
  void showMoreItemsInGroupWorkspace(String groupPath, int total) =>
      resultsShowMoreItemsInGroup(this, groupPath, total);
  void toggleReviewExpandedWorkspace(String path) =>
      resultsToggleReviewExpanded(this, path);
  void resetResultsFiltersWorkspace() => resultsResetFilters(this);
  void backToConclusionsWorkspace() => resultsBackToConclusions(this);
  void openOverviewWorkspace() => enterOverviewHub();
  void openReviewQueueWorkspace({String? directoryPath}) =>
      openReviewQueue(directoryPath: directoryPath);
  void openDetailListWorkspace({
    WorkspaceResultFilter? initialFilter,
    String? directoryPath,
  }) {
    openDetailList(initialFilter: initialFilter, directoryPath: directoryPath);
  }

  void toggleScopeExpandedWorkspace() => toggleEmbeddedScopeExpanded();
  void goBackWorkspace() => handleWorkspaceBack();
  void notifyResultsScrollStartWorkspace() => onResultsScrollStart();
  void notifyResultsScrollEndWorkspace({
    double? pixels,
    double? maxScrollExtent,
  }) => onResultsScrollEnd(pixels: pixels, maxScrollExtent: maxScrollExtent);
  Future<void> generateNarrativeWorkspace() =>
      runConclusionNarrativeInternal(fresh: false, manual: true);
  Future<void> deleteSelectedWorkspace() => deleteSelected();
  Future<void> retryFailedDeletesWorkspace() => deleteSelected();
  void exitWorkspace() => page.onExit();
}
