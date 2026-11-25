import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../ai/ai_coverage_coordinator.dart';
import '../../../ai/ai_coverage_service.dart';
import '../../../ai/ai_provider.dart';
import '../../../ai/ai_settings_store.dart';
import '../../../ai/coverage_client_logic.dart';
import '../../../ai/coverage_job_state.dart';
import '../../../ai/coverage_models.dart';
import '../../../ai/coverage_verdict_store.dart';
import '../../../snapshot_cache.dart';
import '../ports/workspace_ports.dart';
import '../views/ai_analysis_workspace_view_state.dart';
import 'ai_analysis_coverage_flow.dart';
import 'ai_analysis_workspace_controller.dart';

/// Compatibility alias over the real port result type.
typedef AiWorkspaceCoverageStartResult = StartFullCoverageResult;

CoverageVerdictStore _defaultCoverageVerdictStore() =>
    CoverageVerdictStore(SnapshotCache.cacheDir());

/// Owns full-coverage plan, job and verdict-page state.
///
/// The page controller owns cross-owner phase and navigation decisions and is
/// the only writer of these fields. UI effects and result-state writes remain
/// with the page controller, which supplies callbacks where a port result must
/// be translated into UI state.
class AiAnalysisCoverageController extends ChangeNotifier {
  AiAnalysisCoverageController({
    required WorkspaceCoverageJobsPort jobs,
    required WorkspaceSettingsPort settings,
    required AiAnalysisWorkspaceController owner,
    required String snapshotId,
    Object? coverageOwner,
    @visibleForTesting CoverageVerdictStore Function()? verdictStoreFactory,
  }) : this._(
         jobs,
         settings,
         owner,
         snapshotId,
         coverageOwner,
         verdictStoreFactory ?? _defaultCoverageVerdictStore,
       );

  AiAnalysisCoverageController._(
    this._jobs,
    this._settings,
    this._owner,
    this._snapshotId,
    this._coverageOwner,
    this._verdictStoreFactory,
  ) : _ownerId = _coverageOwner?.toString() ?? _snapshotId;

  @visibleForTesting
  factory AiAnalysisCoverageController.forTest({
    required WorkspaceCoverageJobsPort jobs,
    required WorkspaceSettingsPort settings,
    required AiAnalysisWorkspaceController owner,
    required String snapshotId,
    Object? coverageOwner,
  }) {
    return AiAnalysisCoverageController(
      jobs: jobs,
      settings: settings,
      owner: owner,
      snapshotId: snapshotId,
      coverageOwner: coverageOwner,
    );
  }

  WorkspaceCoverageJobsPort _jobs;
  WorkspaceSettingsPort _settings;
  final AiAnalysisWorkspaceController _owner;
  final CoverageVerdictStore Function() _verdictStoreFactory;
  String _snapshotId;
  Object? _coverageOwner;
  String? _ownerId;
  AiMode _precheckMode = AiMode.off;
  int? _precheckPlatformCredits;
  String? _planUnavailableMessage;

  int _planGeneration = 0;
  int _activeControls = 0;
  Future<void>? _controlTail;

  CoverageJobState? jobState;
  bool useFullCoverage = false;
  bool hydrating = false;
  bool hydrated = false;
  int? budgetCredits;
  int? estimatedCredits;
  CoveragePlanSummary? planSummary;
  bool planLoadInFlight = false;
  bool planBannerLoadAttempted = false;
  String? planLoadError;
  int? runBudgetCredits;
  bool coverageCapBelowEstimate = false;
  int verdictPageCount = 2;
  int verdictByteOffset = 0;
  int _refreshSequence = 0;
  List<CoverageVerdict> verdictRows = const [];
  bool verdictPageLoadInFlight = false;
  DateTime? lastVerdictRefreshAt;
  bool userEngagedFullRun = false;
  bool uiPrefersAnalyzingPhase = false;
  int? stalePausedUpdatedAtMs;
  bool pauseInFlight = false;
  CoverageJobState? pendingJobState;
  bool? lastRaiseBudgetSucceeded;
  bool _disposed = false;

  static const verdictPageSize = 500;

  AiWorkspaceCoverageState get coverageState => AiWorkspaceCoverageState(
    jobState: jobState,
    planSummary: planSummary,
    useFullCoverage: useFullCoverage,
    runBudgetCredits: runBudgetCredits,
    coverageCapBelowEstimate: coverageCapBelowEstimate,
    pauseInFlight: pauseInFlight,
    planLoadInFlight: planLoadInFlight,
    verdictPageCount: verdictPageCount,
    verdictRows: verdictRows,
    verdictPageLoadInFlight: verdictPageLoadInFlight,
  );

  AiWorkspaceActivityState get activityState => AiWorkspaceActivityState(
    coverageRunning: jobState?.status == CoverageJobStatus.running,
  );

  int get planGeneration => _planGeneration;
  bool get controlQueueEmpty => _activeControls == 0;
  WorkspaceCoverageJobsPort get jobs => _jobs;
  WorkspaceSettingsPort get settings => _settings;
  String get snapshotId => _snapshotId;
  Object? get coverageOwner => _coverageOwner;

  bool get isCurrentOwner {
    final owned = _ownerId == null || _owner.activeOwnerId == _ownerId;
    return owned;
  }

  void configure({
    required WorkspaceCoverageJobsPort jobs,
    required WorkspaceSettingsPort settings,
    required String snapshotId,
    required Object? coverageOwner,
  }) {
    _jobs = jobs;
    _settings = settings;
    _snapshotId = snapshotId;
    _coverageOwner = coverageOwner;
    final nextOwnerId = coverageOwner?.toString() ?? snapshotId;
    if (nextOwnerId != _ownerId) {
      _ownerId = nextOwnerId;
      _planGeneration++;
      jobState = null;
      planSummary = null;
      planBannerLoadAttempted = false;
      planLoadInFlight = false;
      planLoadError = null;
      hydrating = false;
      hydrated = false;
      budgetCredits = null;
      estimatedCredits = null;
      runBudgetCredits = null;
      coverageCapBelowEstimate = false;
      verdictByteOffset = 0;
      verdictPageCount = 2;
      verdictRows = const [];
      pauseInFlight = false;
      stalePausedUpdatedAtMs = null;
      uiPrefersAnalyzingPhase = false;
      userEngagedFullRun = false;
    }
    _touch();
  }

  /// Supplies the mode, platform-credit balance and already-resolved
  /// unavailable-message needed by the zero-argument [hydratePrecheck] entry
  /// point. The message is a plain value, never a context-capturing callback.
  void prepareHydration({
    required AiMode mode,
    required int? platformCredits,
    required String planUnavailableMessage,
  }) {
    _precheckMode = mode;
    _precheckPlatformCredits = platformCredits;
    _planUnavailableMessage = planUnavailableMessage;
  }

  bool isCurrent(int generation) => _owner.isCurrent(generation);

  Future<void> hydratePrecheck() async {
    final startedPlanGeneration = _planGeneration;
    final jobs = _jobs;
    final owner = _coverageOwner;
    final snapshotId = _snapshotId;
    final generation = _owner.operationGeneration;
    final mode = _precheckMode;
    final platformCredits = _precheckPlatformCredits;
    final planUnavailableMessage = _planUnavailableMessage;
    final budget = await _settings.coverageBudgetForMode(mode);
    if (!_stillCurrent(jobs, owner, snapshotId, generation) ||
        _planGeneration != startedPlanGeneration) {
      return;
    }
    budgetCredits = budget.credits;
    hydrated = true;
    hydrating = true;

    final summary = await jobs.planSummary(snapshotId);
    if (!_stillCurrent(jobs, owner, snapshotId, generation) ||
        _planGeneration != startedPlanGeneration) {
      return;
    }
    final estimated = coveragePrecheckEstimatedCredits(summary);
    int? runBudget;
    if (mode == AiMode.platform &&
        estimated != null &&
        platformCredits != null) {
      runBudget = await _settings.resolveRunBudgetCredits(
        estimatedCredits: estimated,
        accountBalance: platformCredits,
      );
    }
    if (!_stillCurrent(jobs, owner, snapshotId, generation) ||
        _planGeneration != startedPlanGeneration) {
      return;
    }
    budgetCredits = budget.credits;
    planSummary = summary;
    estimatedCredits = estimated;
    runBudgetCredits = runBudget;
    hydrated = true;
    hydrating = false;
    coverageCapBelowEstimate = runCapBelowBufferedEstimate(
      mode: mode,
      platformCredits: platformCredits,
    );
    planLoadError = summary == null ? planUnavailableMessage : null;
    _touch();
  }

  bool runCapBelowBufferedEstimate({
    required AiMode mode,
    required int? platformCredits,
  }) {
    return evaluateCapGate(mode: mode, platformCredits: platformCredits) ==
        CoverageCapGate.capBelowBufferedEstimate;
  }

  bool canStartCoverage({
    required AiMode mode,
    required int? platformCredits,
    required bool useFullCoverage,
  }) {
    if (mode != AiMode.platform) return true;
    if (platformCredits == null) return false;
    final estimated = estimatedCredits;
    if (useFullCoverage && hydrating && estimated == null) {
      return true;
    }
    if (useFullCoverage && estimated == null) return false;
    if (estimated == null) return true;
    if (platformCredits < estimated) return false;
    return evaluateCapGate(mode: mode, platformCredits: platformCredits) !=
        CoverageCapGate.insufficientAccountBalance;
  }

  CoverageCapGate evaluateCapGate({
    required AiMode mode,
    required int? platformCredits,
  }) {
    if (mode != AiMode.platform) return CoverageCapGate.ok;
    final estimated = estimatedCredits;
    final cap = budgetCredits;
    final balance = platformCredits;
    if (estimated == null || cap == null || balance == null) {
      return CoverageCapGate.ok;
    }
    return evaluateCoverageCapGate(
      estimatedCredits: estimated,
      configuredRunCapCredits: cap,
      accountBalance: balance,
    );
  }

  Future<void> ensurePlanSummaryLoaded({required bool useFullCoverage}) async {
    if (!useFullCoverage || planSummary != null) return;
    final startedPlanGeneration = _planGeneration;
    final jobs = _jobs;
    final owner = _coverageOwner;
    final snapshotId = _snapshotId;
    final summary = await jobs.planSummary(snapshotId);
    if (!identical(jobs, _jobs) ||
        !identical(owner, _coverageOwner) ||
        snapshotId != _snapshotId ||
        _planGeneration != startedPlanGeneration ||
        !isCurrentOwner) {
      return;
    }
    planSummary = summary;
    estimatedCredits = coveragePrecheckEstimatedCredits(summary);
    _touch();
  }

  Future<CoverageJobState?> loadJobState() async {
    final cached = jobState;
    if (cached != null && cached.snapshotId == _snapshotId) return cached;
    return _jobs.loadJobState(_snapshotId);
  }

  Future<void> syncActiveJobAfterPrecheck(int generation) async {
    if (!_jobs.isAvailable) return;
    final jobs = _jobs;
    final owner = _coverageOwner;
    final snapshotId = _snapshotId;
    final state = await jobs.loadJobState(snapshotId);
    if (!_stillCurrent(jobs, owner, snapshotId, generation)) return;
    if (state == null || state.snapshotId != snapshotId) return;
    final showsBanner =
        state.status == CoverageJobStatus.running ||
        state.status == CoverageJobStatus.paused;
    if (!showsBanner) return;
    jobState = state;
    _touch();
  }

  Future<AiCoverageService?> prepareService(AiProvider provider) {
    return _jobs.prepareService(provider);
  }

  bool hasRestorableProgress(CoverageJobState state) {
    if (state.snapshotId != _snapshotId) return false;
    if (state.status == CoverageJobStatus.running ||
        state.status == CoverageJobStatus.idle) {
      return false;
    }
    return state.analyzedFiles > 0 ||
        state.localResolvedFiles > 0 ||
        state.usedTokens > 0 ||
        state.usedCredits > 0;
  }

  Future<bool> verdictStoreHasRows() async {
    final store = _verdictStoreFactory();
    return (await store.fileByteLength(_snapshotId)) > 0;
  }

  Future<void> loadNextVerdictPage({
    required int generation,
    required void Function(int nextPageCount, List<CoverageVerdict> rows)
    onRows,
  }) async {
    if (verdictPageLoadInFlight) return;
    verdictPageLoadInFlight = true;
    try {
      final nextPageCount = verdictPageCount + 1;
      final store = _verdictStoreFactory();
      final rows = await store.readPages(
        _snapshotId,
        pageCount: nextPageCount,
        pageSize: verdictPageSize,
      );
      if (!_stillCurrent(_jobs, _coverageOwner, _snapshotId, generation)) {
        return;
      }
      if (rows.length <= verdictRows.length) return;
      verdictPageCount = nextPageCount;
      verdictRows = rows;
      _touch();
      onRows(nextPageCount, rows);
    } finally {
      verdictPageLoadInFlight = false;
    }
  }

  void bumpVerdictPagesForTerminal(
    CoverageJobState state, {
    required int maxPages,
  }) {
    if (!useFullCoverage || state.analyzedFiles <= 0) return;
    final needed = (state.analyzedFiles / verdictPageSize).ceil();
    final target = needed.clamp(2, maxPages);
    if (target > verdictPageCount) verdictPageCount = target;
    _touch();
  }

  bool jobStateShowsBanner(CoverageJobState? state, {bool debug = false}) {
    if (!debug && !useFullCoverage) return false;
    if (state == null || state.snapshotId != _snapshotId) return false;
    return state.status != CoverageJobStatus.idle &&
        state.status != CoverageJobStatus.cancelled &&
        state.status != CoverageJobStatus.completed;
  }

  bool isTerminal(CoverageJobState state) {
    return state.status == CoverageJobStatus.paused ||
        state.status == CoverageJobStatus.completed ||
        state.status == CoverageJobStatus.cancelled;
  }

  Future<AiWorkspaceCoverageStartResult> startFullCoverage({
    required AiMode mode,
    required AiProvider provider,
  }) async {
    return _runControl(
      () => _jobs.startFullCoverage(
        snapshotId: _snapshotId,
        mode: mode,
        provider: provider,
        budgetCredits: runBudgetCredits,
        preloadedPlanSummary: planSummary,
      ),
    );
  }

  Future<void> pause() async {
    await _runControl(() => _jobs.pauseCoverage());
  }

  Future<bool> resume() async {
    return _runControl(() async {
      return _jobs.tryResumeCoverage(_snapshotId);
    });
  }

  Future<void> cancel() async {
    await _runControl(() async {
      await _jobs.cancelCoverage(_snapshotId);
    });
  }

  Future<bool> raiseBudgetAndResume({
    required int budgetTokens,
    required int budgetCredits,
  }) async {
    return _runControl(() async {
      return _jobs.tryRaiseBudgetAndResume(
        snapshotId: _snapshotId,
        budgetTokens: budgetTokens,
        budgetCredits: budgetCredits,
      );
    });
  }

  Future<void> raiseBudget(int credits) async {
    lastRaiseBudgetSucceeded = await raiseBudgetAndResume(
      budgetTokens: 0,
      budgetCredits: credits,
    );
  }

  Future<void> loadMoreVerdicts() async {
    await loadNextVerdictPage(
      generation: _owner.operationGeneration,
      onRows: (_, __) {},
    );
  }

  Future<void> restart() async {
    beginRestart();
  }

  void invalidatePlanSummaryCache() => _jobs.invalidatePlanSummaryCache();

  void beginRestart() {
    _planGeneration++;
    planSummary = null;
    planBannerLoadAttempted = false;
    jobState = null;
    hydrating = false;
    hydrated = false;
    budgetCredits = null;
    estimatedCredits = null;
    runBudgetCredits = null;
    coverageCapBelowEstimate = false;
    _touch();
  }

  void cancelPendingJobCoalesce() {
    pendingJobState = null;
  }

  /// Reads Coverage verdict rows from the snapshot store, applying the page
  /// byte-offset and local-backfill rules owned by this controller. Returns
  /// the rows to surface; the caller owns result application and UI phase.
  ///
  /// [backfillLocalVerdicts] is the page-supplied native/local backfill step.
  /// [generation] is the workspace operation generation to guard staleness.
  Future<List<CoverageVerdict>> refreshVerdictsFromStore({
    required int generation,
    required bool incremental,
    required bool allowNativeLocalBackfill,
    required bool preferReadAll,
    required bool lightweightAnalyzingUi,
    required int displayPreClassifiedCount,
    required int heavyResultsLayoutThreshold,
    required Future<int> Function(String snapshotId, String directory)
    backfillLocalVerdicts,
  }) async {
    final sequence = ++_refreshSequence;
    if (lightweightAnalyzingUi) return verdictRows;
    final jobs = _jobs;
    final owner = _coverageOwner;
    final snapshotId = _snapshotId;
    bool isCurrent() =>
        sequence == _refreshSequence &&
        !_disposed &&
        identical(jobs, _jobs) &&
        identical(owner, _coverageOwner) &&
        snapshotId == _snapshotId &&
        isCurrentOwner;

    final store = _verdictStoreFactory();
    List<CoverageVerdict> coverageVerdicts;
    if (incremental) {
      final chunk = await store.readAppendedSince(
        snapshotId,
        verdictByteOffset,
      );
      if (!isCurrent()) return verdictRows;
      verdictByteOffset = chunk.fileLength;
      if (chunk.appended.isEmpty) return verdictRows;
      coverageVerdicts = aiCoverageMergeVerdictRows(
        verdictRows,
        chunk.appended,
        heavyThreshold: heavyResultsLayoutThreshold,
      );
    } else {
      final snapshot = await store.readSnapshot(
        snapshotId,
        pageCount: verdictPageCount,
        pageSize: verdictPageSize,
        preferAll: preferReadAll,
      );
      if (!isCurrent()) return verdictRows;
      coverageVerdicts = snapshot.rows;
      verdictByteOffset = snapshot.end;
      if (coverageVerdicts.isEmpty) {
        if (verdictByteOffset > 0) {
          return verdictRows;
        }
        if (!allowNativeLocalBackfill) {
          return verdictRows;
        }
        final localExpected =
            (planSummary?.localSafeFiles ?? 0) +
            (planSummary?.localKeepFiles ?? 0);
        final job = jobState;
        final jobExpectsLocal =
            job != null &&
            job.snapshotId == snapshotId &&
            (job.localResolvedFiles > 0 || job.analyzedFiles > 0);
        if (localExpected > 0 ||
            jobExpectsLocal ||
            displayPreClassifiedCount > 0) {
          final written = await backfillLocalVerdicts(
            snapshotId,
            store.directory.path,
          );
          if (!isCurrent()) return verdictRows;
          if (written > 0) {
            final backfilled = await store.readSnapshot(
              snapshotId,
              pageCount: verdictPageCount,
              pageSize: verdictPageSize,
              preferAll: false,
            );
            if (!isCurrent()) return verdictRows;
            coverageVerdicts = backfilled.rows;
            verdictByteOffset = backfilled.end;
          }
        }
      }
    }
    return coverageVerdicts;
  }

  Future<T> _runControl<T>(Future<T> Function() operation) async {
    _activeControls++;
    final previous = _controlTail;
    final completer = Completer<void>();
    _controlTail = completer.future;
    if (previous != null) {
      await previous;
    }
    try {
      return await operation();
    } finally {
      completer.complete();
      _activeControls--;
    }
  }

  bool _stillCurrent(
    WorkspaceCoverageJobsPort jobs,
    Object? owner,
    String snapshotId,
    int generation,
  ) {
    return identical(jobs, _jobs) &&
        identical(owner, _coverageOwner) &&
        snapshotId == _snapshotId &&
        isCurrentOwner &&
        _owner.isCurrent(generation);
  }

  void _touch() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
