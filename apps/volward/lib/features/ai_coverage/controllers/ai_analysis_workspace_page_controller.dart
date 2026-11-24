// ignore_for_file: annotate_overrides, library_private_types_in_public_api

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../ai/ai_analysis_gateway.dart';
import '../../../ai/ai_coverage_coordinator.dart';
import '../../../ai/ai_provider.dart';
import '../../../ai/ai_result_groups.dart';
import '../../../ai/ai_result_overview.dart';
import '../../../ai/ai_settings_store.dart';
import '../../../ai/coverage_client_logic.dart';
import '../../../ai/coverage_job_state.dart';
import '../../../ai/coverage_verdict_store.dart';
import '../../../widgets/ai_results_hub.dart';
import '../ai_analysis_workspace_config.dart';
import 'ai_analysis_workspace_controller.dart';
import '../ports/workspace_ports.dart';
import '../views/ai_analysis_workspace_view_actions.dart';
import '../views/ai_analysis_workspace_view_state.dart';
import '../views/ai_analysis_workspace_messages.dart';
import '../views/ai_analysis_workspace_fallback_messages.dart';
import 'ai_analysis_workspace_actions_adapter.dart';
import 'ai_analysis_workspace_host_mixin.dart';
import 'ai_analysis_workspace_lifecycle_flow.dart';
import 'ai_analysis_workspace_page_surface.dart';
import 'ai_analysis_bootstrap_controller.dart';
import 'ai_analysis_coverage_budget_flow.dart';
import 'ai_analysis_coverage_controller.dart';
import 'ai_analysis_coverage_flow.dart';
import 'ai_analysis_coverage_job_flow.dart';
import 'ai_analysis_coverage_start_flow.dart';
import 'ai_analysis_delete_controller.dart';
import 'ai_analysis_quick_flow.dart';
import 'ai_analysis_results_flow.dart';
import 'ai_analysis_workspace_presentation_prep.dart';
import 'ai_analysis_results_controller.dart';
import 'ai_analysis_workspace_result_helpers.dart';
import 'ai_analysis_workspace_reporting_flow.dart' as reporting_flow;
import 'ai_analysis_workspace_view_state_assembler.dart';

enum _Phase { loading, precheck, privacy, analyzing, results, deleting, error }

class AiAnalysisWorkspacePageController extends ChangeNotifier
    with AiAnalysisWorkspaceHostMixin
    implements AiAnalysisWorkspacePageSurface {
  AiAnalysisWorkspacePageController(this.page);

  AiAnalysisWorkspaceConfig page;
  bool disposed = false;
  late final AiAnalysisWorkspaceMessages messages;

  AiWorkspaceDisplayState get displayState => workspaceController.displayState;
  bool get initialized => workspaceInitialized;
  int get candidateCount => bootstrapController.unknown.length;
  bool get candidatesPending => bootstrapController.candidatesPending;

  AiAnalysisWorkspaceViewState buildViewState() {
    return AiAnalysisWorkspaceViewStateAssembler.buildViewState(this);
  }

  AiAnalysisWorkspaceViewActions? viewActionsCache;

  AiAnalysisWorkspaceViewActions get viewActions =>
      viewActionsCache ??= AiAnalysisWorkspaceViewActionsAdapter(this);

  AiResultsProjection get resultsProjection =>
      resultsController.buildProjection(
        AiAnalysisWorkspaceViewStateAssembler.buildProjectionInput(this),
      );

  // View-state source: one-line forwards consumed by the assembler.
  bool shouldShowCompactActivityCard() =>
      workspaceShouldShowCompactActivityCard(this);

  AiCoverageFlowContext get coverageFlowContext => AiCoverageFlowContext(
    phase: displayState,
    analyzing: analyzing,
    useFullCoverage: useFullCoverage,
    uiPrefersAnalyzingPhase: coverageUiPrefersAnalyzingPhase,
    userEngagedFullRun: coverageUserEngagedFullRun,
    verdictsNotEmpty: verdicts.isNotEmpty,
    resultsHubMode: computeResultsHubMode(),
    deferJobUiForScroll: deferCoverageJobUiForScroll,
    pauseInFlight: coveragePauseInFlight,
    jobState: coverageController.jobState,
    pendingJobState: pendingCoverageJobState,
  );

  void mutate(VoidCallback update) {
    if (disposed) return;
    update();
    notifyListeners();
  }

  static const maxDefaultExpandedResultRows = 96;
  int get heavyResultsLayoutThresholdValue => 200;

  _Phase _phaseValue = _Phase.results;
  bool workspaceInitialized = false;
  WorkspaceResultsView resultsView = WorkspaceResultsView.overview;
  WorkspaceDirectoryTypeFilter directoryTypeFilterPublicValue =
      WorkspaceDirectoryTypeFilter.safe;
  String? error;
  bool loadedEmptySuggestions = false;
  bool analyzing = false;
  bool? scopeExpandedManual;
  bool get deleting => deleteController.busy;
  late final AiAnalysisWorkspaceController workspaceController;
  late final AiAnalysisBootstrapController bootstrapController;
  late final AiAnalysisCoverageController coverageController;
  late final AiAnalysisResultsController resultsController;
  late final AiAnalysisDeleteController deleteController;
  late AiWorkspacePorts ports;

  WorkspaceDirectoryTypeFilter get directoryTypeFilterPublic =>
      directoryTypeFilterPublicValue;

  void setDirectoryTypeFilterValue(WorkspaceDirectoryTypeFilter filter) {
    directoryTypeFilterPublicValue = filter;
  }

  List<AiVerdict> get verdicts => resultsController.verdicts;
  Set<String> get selected => resultsController.selected;
  Map<String, WorkspaceReviewDecision> get reviewDecisions =>
      resultsController.reviewDecisions;
  Set<String> get expandedGroupPaths => resultsController.expandedGroupPaths;
  Map<String, int> get expandedGroupItemLimits =>
      resultsController.expandedGroupItemLimits;
  Set<String> get expandedReviewPaths => resultsController.expandedReviewPaths;

  int? get partialDeleteFailedCount =>
      deleteController.partialDeleteFailedCount;
  int? get partialDeleteFreedBytes => deleteController.partialDeleteFreedBytes;
  List<String> get retryTargets => deleteController.retryTargets;

  String get resultsQuery => resultsController.query;
  WorkspaceResultFilter get resultFilterMode => resultsController.filter;
  String? get resultsDirectoryFilter => resultsController.directoryFilter;
  String? get reviewQueueDirectoryFilter =>
      resultsController.reviewQueueDirectoryFilter;
  int? get reviewQueueSessionInitialPending =>
      resultsController.reviewQueueSessionInitialPending;
  WorkspaceResultSort get resultSortMode => resultsController.sort;

  /// While true, defer coverage job [setState] until scroll ends (avoids jank).
  bool deferCoverageJobUiForScroll = false;

  /// Initial Full Coverage results load after job ends (more load on scroll).
  static const maxCoverageVerdictPagesOnTerminal = 40;
  Timer? jobStateCoalesceTimer;
  bool resultsLayoutPending = false;
  int resultsLayoutGeneration = 0;
  bool resultsUserScrolling = false;
  List<CoverageVerdict>? pendingVerdictRowsAfterScroll;
  bool pendingVerdictRowsPreserveUi = true;

  bool get useFullCoverage => coverageController.useFullCoverage;
  set useFullCoverage(bool value) => coverageController.useFullCoverage = value;
  int? get coverageBudgetCredits => coverageController.budgetCredits;
  set coverageBudgetCredits(int? value) =>
      coverageController.budgetCredits = value;
  bool get coverageUserEngagedFullRun => coverageController.userEngagedFullRun;
  set coverageUserEngagedFullRun(bool value) =>
      coverageController.userEngagedFullRun = value;
  bool get coverageUiPrefersAnalyzingPhase =>
      coverageController.uiPrefersAnalyzingPhase;
  set coverageUiPrefersAnalyzingPhase(bool value) =>
      coverageController.uiPrefersAnalyzingPhase = value;
  int? get coverageStalePausedUpdatedAtMs =>
      coverageController.stalePausedUpdatedAtMs;
  set coverageStalePausedUpdatedAtMs(int? value) =>
      coverageController.stalePausedUpdatedAtMs = value;
  bool get coveragePauseInFlight => coverageController.pauseInFlight;
  set coveragePauseInFlight(bool value) =>
      coverageController.pauseInFlight = value;
  bool get coverageCapBelowEstimate =>
      coverageController.coverageCapBelowEstimate;
  set coverageCapBelowEstimate(bool value) =>
      coverageController.coverageCapBelowEstimate = value;
  CoverageJobState? get pendingCoverageJobState =>
      coverageController.pendingJobState;
  set pendingCoverageJobState(CoverageJobState? value) =>
      coverageController.pendingJobState = value;

  AiCoverageJobs get coverageJobs => ports.coverageJobs;
  AiMode get mode => bootstrapController.mode;
  bool get hasProvider => bootstrapController.hasProvider;
  int? get platformCredits => bootstrapController.platformCredits;
  List<Map<String, dynamic>> get preClassified =>
      bootstrapController.preClassified;
  int? get preClassifiedTotalCount =>
      bootstrapController.preClassifiedTotalCount;
  int? get unknownTotalCount => bootstrapController.unknownTotalCount;
  List<AiCandidate> get unknown => bootstrapController.unknown;
  bool get candidatesBootstrapPending => bootstrapController.candidatesPending;
  String? get unknownCandidatesSpillPath =>
      bootstrapController.unknownCandidatesSpillPath;
  int get estimatedTokens => bootstrapController.estimatedTokens;
  int get estimatedByokBatchTokens =>
      bootstrapController.estimatedByokBatchTokens;
  bool get hasExistingResult => bootstrapController.hasExistingResult;
  bool get truncated => bootstrapController.truncated;
  int get candidatesBeforeCap => bootstrapController.candidatesBeforeCap;
  String get rootPath => bootstrapController.rootPath;
  Map<String, int> get sizeByPath => bootstrapController.sizeByPath;
  _Phase get runtimePhase => _phaseValue;

  set runtimePhase(_Phase value) {
    _phaseValue = value;
    if (!workspaceInitialized) return;
    workspaceController.updateDisplayState(_displayStateForPhase(value));
  }

  AiWorkspaceDisplayState get displayPhase => displayState;

  void setDisplayPhase(AiWorkspaceDisplayState value) {
    runtimePhase = switch (value) {
      AiWorkspaceDisplayState.loading => _Phase.loading,
      AiWorkspaceDisplayState.precheck => _Phase.precheck,
      AiWorkspaceDisplayState.privacy => _Phase.privacy,
      AiWorkspaceDisplayState.analyzing => _Phase.analyzing,
      AiWorkspaceDisplayState.results => _Phase.results,
      AiWorkspaceDisplayState.deleting => _Phase.deleting,
      AiWorkspaceDisplayState.error => _Phase.error,
    };
  }

  static AiWorkspaceDisplayState _displayStateForPhase(_Phase phase) {
    return switch (phase) {
      _Phase.loading => AiWorkspaceDisplayState.loading,
      _Phase.precheck => AiWorkspaceDisplayState.precheck,
      _Phase.privacy => AiWorkspaceDisplayState.privacy,
      _Phase.analyzing => AiWorkspaceDisplayState.analyzing,
      _Phase.results => AiWorkspaceDisplayState.results,
      _Phase.deleting => AiWorkspaceDisplayState.deleting,
      _Phase.error => AiWorkspaceDisplayState.error,
    };
  }

  int beginOperation() => workspaceController.beginOperation();
  bool isCurrent(int generation) =>
      !disposed && workspaceController.isCurrent(generation);

  WorkspaceAnalyticsPort get analytics => ports.analytics;

  void setScopeExpandedManual(bool? value) {
    scopeExpandedManual = value;
  }

  void setLoadedEmptySuggestions(bool value) {
    loadedEmptySuggestions = value;
  }

  Future<void> invalidateConclusionNarrative() async {
    _invalidateConclusionNarrative();
  }

  void resetForBootstrap() {
    workspaceResetForBootstrap(this);
  }

  void resetResultsScroll() => _resetResultsScroll();

  bool get canStartCoverage => workspaceCanStartCoverage(this);

  bool get canStartWorkspaceAnalysis =>
      workspaceCanStartWorkspaceAnalysis(this);

  void handleWorkspaceBack() {
    resultsHandleBack(this);
  }

  void toggleEmbeddedScopeExpanded() {
    resultsToggleEmbeddedScopeExpanded(this);
  }

  List<AiVerdict> _preClassifiedVerdicts({required bool deletable}) {
    return preClassifiedVerdicts(preClassified, deletable: deletable);
  }

  List<AiResultGroup> _normalizedResultGroups() {
    return resultsProjection.normalizedGroups;
  }

  Set<String> scanRootDirectories() {
    return scanRootFirstLevelDirectoryPaths(
      rootPath: rootPath,
      unknown: unknown,
      preClassified: preClassified,
      coverageVerdictRows: coverageController.verdictRows,
      verdicts: verdicts,
    );
  }

  bool _isPendingReview(AiVerdict item) {
    return isPendingReview(item, reviewDecisions);
  }

  bool get showsFilteredItems =>
      resultsQuery.trim().isNotEmpty ||
      resultFilterMode != WorkspaceResultFilter.all ||
      (resultsDirectoryFilter != null && resultsDirectoryFilter!.isNotEmpty);

  void enterOverviewHub() {
    resultsEnterOverviewHub(this);
  }

  void openDetailPage({String? directoryPath}) {
    resultsOpenDetailPage(this, directoryPath: directoryPath);
  }

  ResultsHubMode computeResultsHubMode() {
    final job = coverageController.jobState ?? page.debugCoverageJobState;
    final coverageRunning =
        job != null &&
        job.snapshotId == page.snapshotId &&
        job.status == CoverageJobStatus.running;
    return resolveResultsHubMode(
      analyzing: analyzing,
      hasAnalyzedVerdicts: verdicts.isNotEmpty,
      coverageRunning: coverageRunning,
      coverageCompletion: coverageCompletionTruth(
        job?.snapshotId == page.snapshotId ? job : null,
      ).phase,
    );
  }

  ResultsHubMode get resultsHubMode => computeResultsHubMode();

  void enterResultsPhase({bool showOverview = true}) {
    final entering =
        runtimePhase != _Phase.results && runtimePhase != _Phase.deleting;
    runtimePhase = _Phase.results;
    if (showOverview &&
        (entering || resultsView == WorkspaceResultsView.overview)) {
      resultsView = WorkspaceResultsView.overview;
    }
  }

  void openReviewQueue({String? directoryPath}) {
    resultsOpenReviewQueue(this, directoryPath: directoryPath);
  }

  void openDetailList({
    WorkspaceResultFilter? initialFilter,
    String? directoryPath,
  }) {
    resultsOpenDetailList(
      this,
      initialFilter: initialFilter,
      directoryPath: directoryPath,
    );
  }

  bool get coverageResultsLoadTruncated {
    final job = coverageController.jobState;
    if (job == null || job.snapshotId != page.snapshotId) {
      return false;
    }
    return job.analyzedFiles > verdicts.length;
  }

  AiResultOverviewBuildInput buildConclusionOverviewInput() {
    final groups = _normalizedResultGroups();
    final verdicts = groups.expand((group) => group.items);
    final fingerprint = coverageController.jobState?.fingerprint;
    final job = coverageController.jobState;
    return AiResultOverviewBuildInput(
      targetLabel: page.targetLabel,
      rootPath: rootPath,
      verdicts: verdicts,
      sizeByPath: sizeByPath,
      rootSizeBytesHint: fingerprint != null && fingerprint.rootSizeBytes > 0
          ? fingerprint.rootSizeBytes
          : null,
      truncated:
          truncated ||
          (fingerprint?.truncated ?? false) ||
          coverageResultsLoadTruncated,
      fullCoverage: useFullCoverage,
      maxDirectories: 64,
      isPendingReview: _isPendingReview,
      analyzedItemCountOverride: coverageResultsLoadTruncated
          ? job?.analyzedFiles
          : null,
    );
  }

  Future<void> loadNarrativeSettings() async {
    await resultsLoadNarrativeSettings(this);
  }

  void _invalidateConclusionNarrative() {
    resultsInvalidateConclusionNarrative(this);
  }

  Future<void> runConclusionNarrativeInternal({
    required bool fresh,
    bool manual = false,
    AiProvider? provider,
  }) async {
    await resultsMaybeRunConclusionNarrative(
      this,
      fresh: fresh,
      manual: manual,
      provider: provider,
    );
  }

  bool get runCapBelowBufferedEstimate {
    return coverageController.runCapBelowBufferedEstimate(
      mode: mode,
      platformCredits: platformCredits,
    );
  }

  bool get coveragePlanIsLocalOnly {
    final summary = coverageController.planSummary;
    if (summary == null || summary.planVersion < 3) return false;
    return !coveragePlanRequiresApi(summary);
  }

  int get displayPreClassifiedCount =>
      preClassifiedTotalCount ?? preClassified.length;

  int get displayUnknownCount => unknownTotalCount ?? unknown.length;

  Future<void> ensureUnknownCandidatesLoaded() async {
    await bootstrapController.ensureUnknownCandidatesLoaded();
    if (!disposed) mutate(() {});
  }

  List<String> computeDirectoryPathsForGrouping() {
    return directoryPathsForGrouping(
      unknown: unknown,
      preClassified: preClassified,
    );
  }

  Future<void> applyHeavyResultsPresentation({
    required List<AiVerdict> verdicts,
    required bool preserveUiState,
    Map<String, WorkspaceReviewDecision>? savedReview,
    Set<String>? savedSelected,
    Set<String>? savedExpandedGroups,
    Set<String>? savedExpandedReviews,
    void Function()? resetPresentation,
  }) async {
    final layoutGeneration = ++resultsLayoutGeneration;
    if (!disposed) {
      mutate(() => resultsLayoutPending = true);
    }
    final prep = await compute(
      prepareResultsPresentationIsolate,
      ResultsPresentationPrepInput(
        verdicts: verdicts,
        sizeByPath: Map<String, int>.from(sizeByPath),
        rootPath: rootPath,
        directoryPaths: computeDirectoryPathsForGrouping(),
        maxAutoExpandedRows: maxDefaultExpandedResultRows,
        preClassified: List<Map<String, dynamic>>.from(preClassified),
        firstLevelDirectoryPaths: scanRootDirectories().toList(),
        fullCoverageLayout: useFullCoverage,
      ),
    );
    if (disposed || layoutGeneration != resultsLayoutGeneration) return;
    mutate(() {
      resultsController.setNormalizedGroupsCache(prep.normalizedGroups);
      resultsLayoutPending = false;
      if (!preserveUiState) resetPresentation?.call();
      final review = <String, WorkspaceReviewDecision>{};
      if (preserveUiState && savedReview != null) {
        review.addAll(savedReview);
        for (final verdict in verdicts) {
          if (verdict.verdict == 'review_needed' &&
              !review.containsKey(verdict.path)) {
            review[verdict.path] = WorkspaceReviewDecision.pending;
          }
        }
      } else {
        for (final verdict in verdicts) {
          if (verdict.verdict == 'review_needed') {
            review[verdict.path] = WorkspaceReviewDecision.pending;
          }
        }
      }
      final selectedPaths = preserveUiState && savedSelected != null
          ? savedSelected
          : prep.selectedPaths;
      final expandedGroups = preserveUiState && savedExpandedGroups != null
          ? savedExpandedGroups
          : prep.expandedGroupPaths;
      final expandedReviews = preserveUiState && savedExpandedReviews != null
          ? savedExpandedReviews
          : const <String>{};
      resultsController.applyVerdicts(
        verdicts,
        selectedPaths: selectedPaths,
        reviewDecisions: review,
        expandedGroupPaths: expandedGroups,
        expandedReviewPaths: expandedReviews,
      );
      if (preserveUiState && savedSelected != null) {
        syncSelectedToKnownPaths();
      }
      invalidateVisibleGroups();
      bootstrapController.markExistingResult(verdicts.isNotEmpty);
    });
  }

  void initialize({bool bootstrap = true}) {
    ports =
        page.ports ??
        AiWorkspacePorts.fromCoverageJobs(coverageJobs: page.coverageJobs);
    messages = page.messages ?? const AiAnalysisWorkspaceFallbackMessages();
    workspaceController = AiAnalysisWorkspaceController(
      ownerId: page.coverageOwner?.toString() ?? page.snapshotId,
      onBusyChanged: handleBusyChanged,
    );
    bootstrapController = AiAnalysisBootstrapController(
      page: page,
      owner: workspaceController,
      previousResultLoader: loadSavedAnalysisRaw,
      hasSavedResult: savedAnalysisFileExists,
    );
    coverageController = AiAnalysisCoverageController(
      jobs: ports.coverageJobs,
      settings: ports.settings,
      owner: workspaceController,
      snapshotId: page.snapshotId,
      coverageOwner: page.coverageOwner,
    );
    resultsController = AiAnalysisResultsController(
      owner: workspaceController,
      settings: ports.settings,
      ownerId: page.coverageOwner?.toString() ?? page.snapshotId,
    );
    deleteController = AiAnalysisDeleteController(
      owner: workspaceController,
      ownerId: page.coverageOwner?.toString() ?? page.snapshotId,
    );
    bootstrapController.addListener(_handleBootstrapChanged);
    coverageController.addListener(_handleCoverageChanged);
    resultsController.addListener(_handleResultsChanged);
    deleteController.addListener(_handleDeleteChanged);
    workspaceInitialized = true;
    workspaceController.updateDisplayState(_displayStateForPhase(_phaseValue));
    coverageJobs.addJobStateListener(onCoverageJobState);
    if (bootstrap) {
      runBootstrap();
    }
  }

  @visibleForTesting
  Future<void> bootstrapForTest() => runBootstrap();

  void _handleBootstrapChanged() {
    if (!disposed) notifyListeners();
  }

  void _handleCoverageChanged() {
    if (!disposed) notifyListeners();
  }

  void _handleResultsChanged() {
    if (!disposed) notifyListeners();
  }

  void _handleDeleteChanged() {
    if (!disposed) notifyListeners();
  }

  void handleBusyChanged(bool busy) {
    if (busy) {
      page.onDeletingChanged(true);
      return;
    }
    page.presenter?.schedulePostFrame(() {
      if (!disposed) page.onDeletingChanged(false);
    });
  }

  void dispose() {
    disposed = true;
    coverageJobs.removeJobStateListener(onCoverageJobState);
    jobStateCoalesceTimer?.cancel();
    bootstrapController.removeListener(_handleBootstrapChanged);
    bootstrapController.dispose();
    coverageController.removeListener(_handleCoverageChanged);
    coverageController.dispose();
    resultsController.removeListener(_handleResultsChanged);
    resultsController.dispose();
    deleteController.removeListener(_handleDeleteChanged);
    deleteController.dispose();
    workspaceController.dispose();
    super.dispose();
  }

  void _resetResultsScroll() {
    page.onResetResultsScroll?.call();
  }

  void resetResultsPresentation() {
    page.onClearResultsSearch?.call();
    resultsController.setQuery('');
    resultsController.setFilter(WorkspaceResultFilter.all);
    resultsController.setSort(WorkspaceResultSort.priority);
    resultsController.setDirectoryFilter(null);
    invalidateVisibleGroups();
  }

  void invalidateResultGroups() {
    resultsController.setNormalizedGroupsCache(null);
    invalidateVisibleGroups();
  }

  void invalidateVisibleGroups() {}

  Set<String> knownResultItemPaths() {
    return {
      ...verdicts.map((verdict) => verdict.path),
      ..._preClassifiedVerdicts(deletable: true).map((verdict) => verdict.path),
      ..._preClassifiedVerdicts(
        deletable: false,
      ).map((verdict) => verdict.path),
    };
  }

  void syncSelectedToKnownPaths() {
    // While JSONL pages are still loading, [verdicts] is only a subset — do not
    // drop selections for paths that simply have not arrived yet.
    if (coverageResultsLoadTruncated) return;
    final known = knownResultItemPaths();
    resultsController.removeSelectionWhere(
      (path) => !known.contains(path),
      notify: false,
    );
  }

  void queueCoverageVerdictRowsUntilScrollIdle(
    List<CoverageVerdict> rows, {
    required bool preserveUiState,
  }) {
    pendingVerdictRowsAfterScroll = rows;
    pendingVerdictRowsPreserveUi = preserveUiState;
  }

  void flushPendingCoverageVerdictRowsAfterScroll() {
    final pending = pendingVerdictRowsAfterScroll;
    if (pending == null) return;
    pendingVerdictRowsAfterScroll = null;
    applyCoverageVerdictRows(
      pending,
      preserveUiState: pendingVerdictRowsPreserveUi,
    );
  }

  void updateConfig(AiAnalysisWorkspaceConfig oldPage) {
    workspaceUpdateConfig(this, oldPage);
  }

  Future<void> runBootstrap() async {
    await quickBootstrap(this);
  }

  /// Refreshes mode, provider, quota, and coverage plan estimate without rebuilding candidates.
  Future<void> runBootstrapPrecheckContext(int generation) async {
    await quickBootstrapPrecheckContext(this, generation);
  }

  Future<bool> runLoadPreviousResult({int? bootstrapGeneration}) async {
    return quickLoadPreviousResult(
      this,
      bootstrapGeneration: bootstrapGeneration,
    );
  }

  Future<String?> loadSavedAnalysisRaw({
    required String cacheKey,
    required String snapshotId,
  }) async {
    return quickLoadSavedAnalysisRaw(
      cacheKey: cacheKey,
      snapshotId: snapshotId,
    );
  }

  Future<void> runStartAnalysis() async {
    await quickStartAnalysis(this);
  }

  bool coverageJobStateShowsBanner(CoverageJobState? state) {
    return coverageController.jobStateShowsBanner(
      state,
      debug: page.debugCoverageJobState != null,
    );
  }

  void scheduleCoveragePlanSummaryForBannerIfNeeded() {
    coverageSchedulePlanSummaryForBanner(this);
  }

  bool shouldShowResultsLocalPreviewHint() {
    return aiCoverageShouldShowResultsLocalPreviewHint(coverageFlowContext);
  }

  Future<void> openLocalOnlyResults() async {
    await coverageOpenLocalOnlyResults(this);
  }

  bool isLightweightAnalyzingUi() {
    return aiCoverageIsLightweightAnalyzing(coverageFlowContext);
  }

  List<CoverageVerdict> coverageJobBannerVerdictRows() {
    return aiCoverageJobBannerVerdictRows(
      coverageFlowContext,
      coverageController.verdictRows,
    );
  }

  bool freezeActivityMotionForJob(CoverageJobState? job) {
    return aiCoverageFreezeActivityMotion(
      job,
      pauseInFlight: coveragePauseInFlight,
    );
  }

  bool _shouldDeferCoverageJobUiDuringScroll() {
    return aiCoverageShouldDeferJobUiDuringScroll(coverageFlowContext);
  }

  void onResultsScrollStart() {
    if (runtimePhase == _Phase.results || runtimePhase == _Phase.deleting) {
      resultsUserScrolling = true;
    }
    if (_shouldDeferCoverageJobUiDuringScroll()) {
      deferCoverageJobUiForScroll = true;
    }
  }

  void onResultsScrollEnd({double? pixels, double? maxScrollExtent}) {
    if (deferCoverageJobUiForScroll) {
      deferCoverageJobUiForScroll = false;
      flushPendingCoverageJobStateAfterScroll();
    }
    if (runtimePhase == _Phase.results || runtimePhase == _Phase.deleting) {
      resultsUserScrolling = false;
      page.presenter?.schedulePostFrame(() {
        if (disposed) return;
        flushPendingCoverageVerdictRowsAfterScroll();
        maybeLoadMoreCoverageVerdicts(
          pixels: pixels,
          maxScrollExtent: maxScrollExtent,
        );
      });
    }
  }

  void flushPendingCoverageJobStateAfterScroll() {
    if (pendingCoverageJobState == null || disposed) return;
    jobStateCoalesceTimer?.cancel();
    jobStateCoalesceTimer = null;
    // ScrollEndNotification is dispatched during layout; never setState here.
    page.presenter?.schedulePostFrame(() {
      if (disposed || deferCoverageJobUiForScroll) return;
      final pending = pendingCoverageJobState;
      if (pending == null) return;
      // Consume before applying so a later scroll-end does not replay it;
      // terminal states already painted during defer are deduped in paint.
      pendingCoverageJobState = null;
      unawaited(applyCoverageJobState(pending));
    });
  }

  void maybeLoadMoreCoverageVerdicts({
    double? pixels,
    double? maxScrollExtent,
  }) {
    coverageJobMaybeLoadMore(
      this,
      pixels: pixels,
      maxScrollExtent: maxScrollExtent,
    );
  }

  void onCoverageJobState(CoverageJobState state) {
    coverageJobOnState(this, state);
  }

  Future<void> pauseFullCoverageFromBanner() async {
    if (coveragePauseInFlight) return;
    final generation = workspaceController.operationGeneration;
    final wasAnalyzing = analyzing;
    final wasPrefersAnalyzing = coverageUiPrefersAnalyzingPhase;
    mutate(() {
      coveragePauseInFlight = true;
      analyzing = false;
      coverageUiPrefersAnalyzingPhase = false;
    });
    void undoOptimisticPause() {
      if (!isCurrent(generation)) return;
      mutate(() {
        coveragePauseInFlight = false;
        analyzing = wasAnalyzing;
        coverageUiPrefersAnalyzingPhase = wasPrefersAnalyzing;
      });
    }

    try {
      await coverageController.pause();
    } catch (_) {
      // Job-state listeners are async; stay on the optimistic pausing UI
      // until a paused emit arrives. Only restore if the pause call fails.
      undoOptimisticPause();
    }
  }

  void markCoverageRunEngaged() {
    coverageStalePausedUpdatedAtMs =
        coverageController.jobState?.status == CoverageJobStatus.paused
        ? coverageController.jobState!.updatedAtMs
        : null;
    coverageUserEngagedFullRun = true;
    coverageUiPrefersAnalyzingPhase = true;
    // A new run must never inherit a stale optimistic pausing flag.
    coveragePauseInFlight = false;
    analyzing = true;
    runtimePhase = _Phase.analyzing;
    error = null;
  }

  Future<void> applyCoverageJobState(CoverageJobState state) async {
    await coverageJobApplyState(this, state);
  }

  AiWorkspaceCoverage get coverageAccess {
    final gateway = page.gateway;
    if (gateway is AiWorkspaceCoverage) return gateway as AiWorkspaceCoverage;
    return const ProductionAiAnalysisGateway();
  }

  Future<void> refreshVerdictsInternal({
    bool incremental = false,
    bool allowNativeLocalBackfill = true,
    bool preferReadAll = false,
  }) async {
    final generation = workspaceController.operationGeneration;
    final rows = await coverageController.refreshVerdictsFromStore(
      generation: generation,
      incremental: incremental,
      allowNativeLocalBackfill: allowNativeLocalBackfill,
      preferReadAll: preferReadAll,
      lightweightAnalyzingUi: isLightweightAnalyzingUi(),
      displayPreClassifiedCount: displayPreClassifiedCount,
      heavyResultsLayoutThreshold: heavyResultsLayoutThresholdValue,
      backfillLocalVerdicts: coverageAccess.backfillLocalVerdicts,
    );
    if (!isCurrent(generation) || disposed) return;
    await applyCoverageVerdictRowsAsync(rows, preserveUiState: incremental);
    if (resultsLayoutPending && verdicts.isEmpty) {
      mutate(() => resultsLayoutPending = false);
    }
  }

  void applyCoverageVerdictRows(
    List<CoverageVerdict> coverageVerdicts, {
    bool preserveUiState = false,
  }) {
    if (resultsUserScrolling &&
        preserveUiState &&
        (runtimePhase == _Phase.results || runtimePhase == _Phase.deleting)) {
      queueCoverageVerdictRowsUntilScrollIdle(
        coverageVerdicts,
        preserveUiState: preserveUiState,
      );
      return;
    }
    unawaited(
      coverageJobApplyVerdictRows(
        this,
        coverageVerdicts,
        preserveUiState: preserveUiState,
      ),
    );
  }

  Future<void> applyCoverageVerdictRowsAsync(
    List<CoverageVerdict> coverageVerdicts, {
    bool preserveUiState = false,
  }) async {
    await coverageJobApplyVerdictRows(
      this,
      coverageVerdicts,
      preserveUiState: preserveUiState,
    );
  }

  Future<void> startFullCoverageAnalysis() async {
    await coverageStartFullAnalysis(this);
  }

  Future<void> raiseConfiguredCoverageCap() async {
    await coverageRaiseConfiguredCap(this);
  }

  bool jobBillingMismatch(CoverageJobState job) =>
      coverageJobBillingModeMismatch(this, job);

  String? jobBillingMismatchMessage(CoverageJobState job) {
    return coverageJobBillingModeMismatchBannerMessage(this, job);
  }

  List<AiVerdict> unanalyzedVerdicts() {
    return reporting_flow.unanalyzedVerdicts(
      useFullCoverage: useFullCoverage,
      jobState: coverageController.jobState,
      unknown: unknown,
      verdicts: verdicts,
      l10n: messages.l10n,
    );
  }

  Future<void> deleteSelected() async {
    await resultsDeleteSelected(this);
  }

  void toggle(String path, bool? selected) {
    resultsToggleSelection(this, path, selected);
  }

  void confirmReviewDecision(String path, WorkspaceReviewDecision decision) {
    resultsConfirmReviewDecision(this, path, decision);
  }

  void toggleSafeGroupPaths(List<String> paths, bool selected) {
    resultsToggleSafeGroupPaths(this, paths, selected);
  }

  void toggleGroupExpandedAction(String path) {
    resultsToggleGroupExpanded(this, path);
  }

  void showMoreItemsInGroupAction(String groupPath, int total) {
    resultsShowMoreItemsInGroup(this, groupPath, total);
  }

  void toggleReviewExpandedAction(String path) {
    resultsToggleReviewExpanded(this, path);
  }

  void resetResultsFilters() {
    resultsResetFilters(this);
  }

  void backToConclusions() {
    resultsBackToConclusions(this);
  }

  Set<String> defaultExpandedGroupPaths() {
    return expandedGroupPathsForPresentation(
      _normalizedResultGroups(),
      maxAutoExpandedRows: maxDefaultExpandedResultRows,
    );
  }

  void bumpCoverageVerdictPagesForTerminal(CoverageJobState state) {
    coverageController.bumpVerdictPagesForTerminal(
      state,
      maxPages: maxCoverageVerdictPagesOnTerminal,
    );
  }

  void setResultsQuery(String value) {
    resultsSetQuery(this, value);
  }

  void setResultsDirectoryFilter(String? path) {
    resultsSetDirectoryFilter(this, path);
  }

  void setResultFilterMode(WorkspaceResultFilter mode) {
    resultsSetFilter(this, mode);
  }

  void setResultSortMode(WorkspaceResultSort mode) {
    resultsSetSort(this, mode);
  }

  void setDirectoryTypeFilter(WorkspaceDirectoryTypeFilter filter) {
    resultsSetDirectoryTypeFilter(this, filter);
  }

  int get selectedBytes =>
      selected.fold(0, (total, path) => total + (sizeByPath[path] ?? 0));

  String formatBytes(num? bytes) => formatBytesValue(bytes);
}
