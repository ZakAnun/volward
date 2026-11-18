import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../analytics/analytics.dart';
import '../analytics/analytics_events.dart';
import '../l10n/generated/app_localizations.dart';
import '../snapshot_cache.dart';
import '../volward_session.dart';
import 'ai_debug_log.dart';
import 'ai_coverage_job_controller.dart';
import 'ai_coverage_service.dart';
import 'ai_provider.dart';
import 'byok_ai_provider.dart';
import 'platform_ai_provider.dart';
import 'ai_settings_store.dart';
import 'coverage_desktop_notify.dart';
import 'coverage_client_logic.dart';
import 'coverage_job_state.dart';
import 'coverage_lifecycle.dart';
import 'coverage_models.dart';
import 'coverage_notification_text.dart';
import 'native_coverage_engine.dart';
import 'session_ai_contract.dart';

typedef CoverageDesktopNotify =
    Future<void> Function({
      required String title,
      required String body,
      String? snapshotId,
    });

typedef CoverageServiceFactory =
    Future<AiCoverageService?> Function({
      required VolwardSession session,
      required AiProvider provider,
      CoverageResumePlanLoader? resumePlanLoader,
      String? catalogSnapshotId,
    });

enum StartCoverageBlockedReason { capBelowEstimate, insufficientAccountBalance }

sealed class StartFullCoverageResult {
  const StartFullCoverageResult();
}

final class StartFullCoverageStarted extends StartFullCoverageResult {
  const StartFullCoverageStarted();
}

final class StartFullCoverageUnavailable extends StartFullCoverageResult {
  const StartFullCoverageUnavailable();
}

final class StartCoverageBlocked extends StartFullCoverageResult {
  const StartCoverageBlocked(this.reason);
  final StartCoverageBlockedReason reason;

  static const reasonCapBelowEstimate = StartCoverageBlocked(
    StartCoverageBlockedReason.capBelowEstimate,
  );

  static const reasonInsufficientAccountBalance = StartCoverageBlocked(
    StartCoverageBlockedReason.insufficientAccountBalance,
  );
}

final class StartFullCoverageLocalOnly extends StartFullCoverageResult {
  const StartFullCoverageLocalOnly();
}

/// Coverage operations used by the analysis workspace.
abstract interface class AiCoverageJobs {
  bool get isAvailable;
  void addJobStateListener(void Function(CoverageJobState) listener);
  void removeJobStateListener(void Function(CoverageJobState) listener);
  Future<CoverageJobState?> loadJobState(String snapshotId);
  Future<CoveragePlanSummary?> planSummary(String snapshotId);
  void invalidatePlanSummaryCache();
  Future<AiCoverageService?> prepareService(AiProvider provider);
  Future<StartFullCoverageResult> startFullCoverage({
    required String snapshotId,
    required AiMode mode,
    required AiProvider provider,
    int? budgetCredits,
    CoveragePlanSummary? preloadedPlanSummary,
  });
  Future<void> pauseCoverage();
  Future<void> cancelCoverage(String snapshotId);
  Future<bool> tryResumeCoverage(String snapshotId);
  Future<bool> tryRaiseBudgetAndResume({
    required String snapshotId,
    required int budgetTokens,
    required int budgetCredits,
  });
}

/// Process-scoped owner for full-coverage jobs (Design §5.3).
class AiCoverageCoordinator
    with WidgetsBindingObserver
    implements AiCoverageJobs {
  AiCoverageCoordinator._({
    this._session,
    CoverageDesktopNotify? desktopNotify,
    CoverageServiceFactory? serviceFactory,
    bool Function(VolwardSession session)? isCoverageApiReady,
    Future<AiProvider?> Function()? resolveProvider,
  }) : _desktopNotify = desktopNotify ?? showCoverageDesktopNotification,
       _serviceFactory = serviceFactory ?? AiCoverageService.tryCreate,
       _isCoverageApiReady =
           isCoverageApiReady ?? ((session) => session.hasAiCoverageApi),
       _resolveProviderOverride = resolveProvider;

  static final AiCoverageCoordinator instance = AiCoverageCoordinator._();

  /// Creates an independent job owner for a page using its own Session.
  AiCoverageCoordinator.forSession(VolwardSession session)
    : this._(session: session);

  @visibleForTesting
  static bool debugForceAvailable = false;

  @visibleForTesting
  static Future<CoveragePlanSummary?> Function(String snapshotId)?
  debugPlanSummary;

  @visibleForTesting
  static bool debugTreatSnapshotReady = false;

  /// When true, [startFullCoverage] fails if [planSummary] returns null (tests).
  @visibleForTesting
  static bool debugRequirePlanSummary = false;

  @visibleForTesting
  static Future<CoverageJobState?> Function(String snapshotId)?
  debugLoadJobState;

  @visibleForTesting
  factory AiCoverageCoordinator.testing({
    CoverageDesktopNotify? desktopNotify,
    CoverageServiceFactory? serviceFactory,
    bool Function(VolwardSession session)? isCoverageApiReady,
    Future<AiProvider?> Function()? resolveProvider,
  }) => AiCoverageCoordinator._(
    desktopNotify: desktopNotify,
    serviceFactory: serviceFactory,
    isCoverageApiReady: isCoverageApiReady,
    resolveProvider: resolveProvider,
  );

  @visibleForTesting
  Future<void> debugNotify(CoverageJobState state, {AppLocalizations? l10n}) =>
      _maybeNotify(state, l10n: l10n);

  /// Pushes [state] to workspace listeners (tests only; production uses the service stream).
  @visibleForTesting
  void debugEmitJobState(CoverageJobState state) => _notifyListeners(state);

  final CoverageDesktopNotify _desktopNotify;
  final CoverageServiceFactory _serviceFactory;
  final bool Function(VolwardSession session) _isCoverageApiReady;
  final Future<AiProvider?> Function()? _resolveProviderOverride;

  VolwardSession? _session;
  bool _observingLifecycle = false;
  AiCoverageService? _service;
  AiProvider? _activeProvider;
  final Set<AiProvider> _ownedProviders = HashSet.identity();
  final Expando<bool> _disposedProviders = Expando<bool>();
  StreamSubscription<CoverageJobState>? _statesSub;
  Future<void> _serviceTail = Future<void>.value();
  Future<void> _sessionHandoff = Future<void>.value();
  int _sessionGeneration = 0;
  bool _retired = false;
  Future<void>? _detachedRetirement;
  final _listeners = <void Function(CoverageJobState state)>{};
  CoverageJobState? _lastTrackedState;
  String? _cachedPlanSnapshotId;
  CoveragePlanSummary? _cachedPlanSummary;

  Future<AiProvider?> _resolveProvider() {
    final override = _resolveProviderOverride;
    if (override != null) return override();
    final session = _session;
    if (session == null) return AiSettingsStore.instance.resolveProvider();
    return AiSettingsStore.instance.resolveProviderWithContract(
      () => SessionAiContract(session),
    );
  }

  @Deprecated('Use addJobStateListener/removeJobStateListener')
  set listener(void Function(CoverageJobState state)? callback) {
    _listeners.clear();
    if (callback != null) {
      _listeners.add(callback);
    }
  }

  @override
  void addJobStateListener(void Function(CoverageJobState state) listener) {
    _listeners.add(listener);
  }

  @override
  void removeJobStateListener(void Function(CoverageJobState state) listener) {
    _listeners.remove(listener);
  }

  bool get isAttached => _session != null;

  bool isAttachedTo(VolwardSession session) => identical(_session, session);

  @override
  bool get isAvailable =>
      debugForceAvailable || (_session?.hasAiCoverageApi ?? false);

  CoverageJobState? get currentState => _service?.state;

  Stream<CoverageJobState>? get states => _service?.states;

  void attach(VolwardSession session) => _attach(session);

  /// Rebinds the page owner without starting a readiness wait for a cold Session.
  void rebind(VolwardSession session) => _attach(session, waitForReady: false);

  /// Binds a Session while deferring job operations until the previous owner drains.
  void attachAfter(VolwardSession session, Future<void> previousRetirement) =>
      _attach(
        session,
        previousRetirement: previousRetirement,
        waitForReady: false,
      );

  void _attach(
    VolwardSession session, {
    Future<void>? previousRetirement,
    bool waitForReady = true,
  }) {
    if (identical(_session, session) && previousRetirement == null) return;
    unawaited(
      _retireService(previousRetirement: previousRetirement).catchError((
        Object error,
        StackTrace stack,
      ) {
        debugPrint('Coverage retirement failed: $error\n$stack');
      }),
    );
    invalidatePlanSummaryCache();
    _session = session;
    _retired = false;
    _detachedRetirement = null;
    if (_observingLifecycle) {
      unawaited(_tryAutoResumeSavedJobs());
    } else if (waitForReady || _isCoverageApiReady(session)) {
      _observeLifecycle();
    }
  }

  /// A page already observes readiness and can activate its job owner when ready.
  void observeLifecycleIfReady() {
    final session = _session;
    if (session != null && _isCoverageApiReady(session)) _observeLifecycle();
  }

  void _observeLifecycle() {
    if (_observingLifecycle) return;
    final session = _session!;
    _observingLifecycle = true;
    volwardAiDebugLog(
      'coordinator attach isAvailable=$isAvailable '
      'sessionReady=${session.ready} coverage=${session.hasAiCoverageApi} '
      'tree=${session.hasAiTreeCoverageApi}',
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_tryAutoResumeSavedJobs());
  }

  void detach() => unawaited(
    detachAndDrain().catchError((Object error, StackTrace stack) {
      debugPrint('Coverage retirement failed: $error\n$stack');
    }),
  );

  Future<void> detachAndDrain() {
    if (_retired && _detachedRetirement != null) return _detachedRetirement!;
    _stopObservingLifecycle();
    _session = null;
    _retired = true;
    invalidatePlanSummaryCache();
    return _detachedRetirement = _retireService();
  }

  void _stopObservingLifecycle() {
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
  }

  Future<void> _retireService({Future<void>? previousRetirement}) {
    _sessionGeneration++;
    final active = _takeService();
    final priorHandoff = _sessionHandoff;
    final predecessor = previousRetirement?.then<(Object, StackTrace)?>(
      (_) => null,
      onError: (Object error, StackTrace stack) => (error, stack),
    );
    final retirement = _enqueueServiceOperation(() async {
      await priorHandoff;
      Object? firstError;
      StackTrace? firstStack;
      try {
        if (active.service != null) {
          await _closeService(
            active.service!,
            active.provider,
            active.subscription,
          );
        }
      } catch (error, stack) {
        firstError = error;
        firstStack = stack;
      }
      final predecessorFailure = await predecessor;
      if (predecessorFailure != null) {
        firstError ??= predecessorFailure.$1;
        firstStack ??= predecessorFailure.$2;
      }
      if (firstError != null) {
        Error.throwWithStackTrace(firstError, firstStack!);
      }
    });
    // Later generations must wait for completion, but must not inherit errors.
    _sessionHandoff = retirement.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return retirement;
  }

  Future<T> _enqueueServiceOperation<T>(FutureOr<T> Function() action) {
    final operation = _serviceTail.then((_) => action());
    _serviceTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<T> _withActiveService<T>(
    AiCoverageService service,
    Future<T> Function() action, {
    required T unavailable,
  }) {
    final generation = _sessionGeneration;
    return _enqueueServiceOperation(() {
      if (generation != _sessionGeneration || !identical(_service, service)) {
        return unavailable;
      }
      return action();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (shouldMarkAppQuitOnLifecycle(state)) {
      unawaited(markAppQuit());
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_tryAutoResumeSavedJobs());
    }
  }

  @override
  Future<CoverageJobState?> loadJobState(String snapshotId) {
    final override = debugLoadJobState;
    if (override != null) return override(snapshotId);
    return CoverageJobStateStore(SnapshotCache.cacheDir()).load(snapshotId);
  }

  @override
  Future<CoveragePlanSummary?> planSummary(String snapshotId) async {
    final override = debugPlanSummary;
    if (override != null) {
      return override(snapshotId);
    }
    if (_cachedPlanSnapshotId == snapshotId && _cachedPlanSummary != null) {
      return _cachedPlanSummary;
    }
    final session = _session;
    final generation = _sessionGeneration;
    if (session == null || !_isCoverageApiReady(session)) return null;
    final engine = session.coverageEngine;
    if (engine == null) return null;
    try {
      final summary = session.hasAiTreeCoverageApi
          ? await engine.buildTreePlan(snapshotId)
          : await engine.buildPlan(snapshotId);
      if (generation != _sessionGeneration) return null;
      _cachedPlanSnapshotId = snapshotId;
      _cachedPlanSummary = summary;
      volwardAiDebugLog(
        'planSummary snapshot=$snapshotId planVersion=${summary.planVersion} '
        'localSafe=${summary.localSafeFiles} localKeep=${summary.localKeepFiles} '
        'tailFiles=${summary.tailFiles ?? summary.tailFileCount} '
        'treePending=${summary.treePendingFiles} '
        'minApi=${coveragePlanMinApiCalls(summary)}',
      );
      return summary;
    } catch (e) {
      volwardAiDebugLog('planSummary failed snapshot=$snapshotId error=$e');
      return null;
    }
  }

  @override
  void invalidatePlanSummaryCache() {
    _cachedPlanSnapshotId = null;
    _cachedPlanSummary = null;
  }

  Future<CoveragePlanSummary?> _tryResumePlanForJob(
    String snapshotId,
    CoverageJobState job,
  ) async {
    if (_cachedPlanSnapshotId == snapshotId && _cachedPlanSummary != null) {
      final freshJob =
          job.analyzedFiles == 0 &&
          job.cursor == 0 &&
          job.treeQueueCursor == 0 &&
          job.tailQueueCursor == 0;
      if (freshJob) {
        return _cachedPlanSummary;
      }
    }
    final fromMemory = coverageResumePlanFromMemoryCache(
      snapshotId: snapshotId,
      job: job,
      cachedSnapshotId: _cachedPlanSnapshotId,
      cachedSummary: _cachedPlanSummary,
    );
    if (fromMemory != null) return fromMemory;
    final session = _session;
    final engine = session?.coverageEngine;
    if (engine is NativeCoverageEngine) {
      return engine.tryReadMaterializedPlanSummary(
        snapshotId,
        tree: session!.hasAiTreeCoverageApi,
      );
    }
    return null;
  }

  @visibleForTesting
  void debugSetPlanSummaryCache(
    String snapshotId,
    CoveragePlanSummary summary,
  ) {
    _cachedPlanSnapshotId = snapshotId;
    _cachedPlanSummary = summary;
  }

  @visibleForTesting
  Future<CoveragePlanSummary?> debugTryResumePlanForJob(
    String snapshotId,
    CoverageJobState job,
  ) => _tryResumePlanForJob(snapshotId, job);

  @override
  Future<AiCoverageService?> prepareService(
    AiProvider provider, {
    String? catalogSnapshotId,
  }) {
    final generation = _sessionGeneration;
    final handoff = _sessionHandoff;
    return _enqueueServiceOperation(() async {
      await handoff;
      if (generation != _sessionGeneration) {
        _disposeUnownedProvider(provider);
        return null;
      }
      return _prepareService(provider, catalogSnapshotId: catalogSnapshotId);
    });
  }

  Future<AiCoverageService?> _prepareService(
    AiProvider provider, {
    String? catalogSnapshotId,
  }) async {
    try {
      return await _prepareServiceImpl(
        provider,
        catalogSnapshotId: catalogSnapshotId,
      );
    } catch (_) {
      _disposeUnownedProvider(provider);
      rethrow;
    }
  }

  Future<AiCoverageService?> _prepareServiceImpl(
    AiProvider provider, {
    String? catalogSnapshotId,
  }) async {
    final session = _session;
    if (session == null || !_isCoverageApiReady(session)) {
      _disposeUnownedProvider(provider);
      return null;
    }
    final generation = _sessionGeneration;
    if (_service != null && _sameProvider(_activeProvider, provider)) {
      if (catalogSnapshotId != null &&
          !_service!.isolateCatalogMatches(catalogSnapshotId)) {
        await _releaseService(keepProvider: provider);
      } else {
        if (!identical(provider, _activeProvider)) {
          _disposeUnownedProvider(provider);
        }
        return _service;
      }
    } else if (_service != null) {
      await _releaseService();
    }
    if (generation != _sessionGeneration) {
      _disposeUnownedProvider(provider);
      return null;
    }
    AiCoverageService? service;
    try {
      service = await _serviceFactory(
        session: session,
        provider: provider,
        resumePlanLoader: (snapshotId, job) async {
          if (generation != _sessionGeneration ||
              !identical(session, _session)) {
            return null;
          }
          final plan = await _tryResumePlanForJob(snapshotId, job);
          if (generation != _sessionGeneration ||
              !identical(session, _session)) {
            return null;
          }
          return plan;
        },
        catalogSnapshotId: catalogSnapshotId,
      );
    } catch (_) {
      _disposeUnownedProvider(provider);
      rethrow;
    }
    if (generation != _sessionGeneration) {
      if (service != null) {
        await _closeService(service, provider, null);
      } else {
        _disposeUnownedProvider(provider);
      }
      return null;
    }
    if (service == null) {
      _disposeUnownedProvider(provider);
      return null;
    }
    _service = service;
    _activeProvider = provider;
    _ownedProviders.add(provider);
    _statesSub?.cancel();
    final stream = _service?.states;
    if (stream != null) {
      _statesSub = stream.listen((state) {
        if (generation == _sessionGeneration && identical(_service, service)) {
          _onJobState(state);
        }
      }, onError: (_) {});
    }
    return _service;
  }

  @override
  Future<StartFullCoverageResult> startFullCoverage({
    required String snapshotId,
    required AiMode mode,
    required AiProvider provider,
    int? budgetCredits,
    CoveragePlanSummary? preloadedPlanSummary,
  }) async {
    final session = _session;
    final generation = _sessionGeneration;
    final service = await prepareService(
      provider,
      catalogSnapshotId: snapshotId,
    );
    if (service == null || generation != _sessionGeneration) {
      volwardAiDebugLog('startFullCoverage unavailable (prepareService null)');
      return const StartFullCoverageUnavailable();
    }
    final summary =
        preloadedPlanSummary ??
        (_cachedPlanSnapshotId == snapshotId ? _cachedPlanSummary : null) ??
        await planSummary(snapshotId);
    if (generation != _sessionGeneration || !identical(_service, service)) {
      return const StartFullCoverageUnavailable();
    }
    if (summary == null &&
        (debugRequirePlanSummary ||
            (session != null && session.hasAiTreeCoverageApi))) {
      volwardAiDebugLog(
        'startFullCoverage unavailable (plan summary null, treeApi=${session?.hasAiTreeCoverageApi})',
      );
      return const StartFullCoverageUnavailable();
    }
    if (summary != null &&
        summary.planVersion >= 3 &&
        !coveragePlanRequiresApi(summary)) {
      volwardAiDebugLog(
        'startFullCoverage → local-only plan v${summary.planVersion} '
        'localSafe=${summary.localSafeFiles} localKeep=${summary.localKeepFiles}',
      );
      return const StartFullCoverageLocalOnly();
    }
    volwardAiDebugLog(
      'startFullCoverage starting planVersion=${summary?.planVersion} '
      'minApi=${summary == null ? "?" : coveragePlanMinApiCalls(summary)} '
      'treeCredits=${summary?.estimatedTreeCredits} tailCredits=${summary?.estimatedTailCredits}',
    );
    final budget = await AiSettingsStore.instance.coverageBudgetForMode(mode);
    var budgetTokens = budget.tokens;
    var resolvedBudgetCredits = budgetCredits ?? budget.credits;
    if (mode == AiMode.platform) {
      final estimatedCredits = coveragePrecheckEstimatedCredits(summary) ?? 0;
      final configured = await AiSettingsStore.instance.coverageBudgetForMode(
        AiMode.platform,
      );
      var accountBalance = 0;
      final activeProvider = _activeProvider;
      if (activeProvider is PlatformAiProvider) {
        await activeProvider.queryQuota();
        accountBalance = activeProvider.lastCreditsRemaining ?? 0;
      }
      final gate = evaluateCoverageCapGate(
        estimatedCredits: estimatedCredits,
        configuredRunCapCredits: configured.credits,
        accountBalance: accountBalance,
      );
      if (gate == CoverageCapGate.capBelowBufferedEstimate) {
        return StartCoverageBlocked.reasonCapBelowEstimate;
      }
      if (gate == CoverageCapGate.insufficientAccountBalance) {
        return StartCoverageBlocked.reasonInsufficientAccountBalance;
      }
      if (budgetCredits == null) {
        resolvedBudgetCredits = await AiSettingsStore.instance
            .resolveRunBudgetCredits(
              estimatedCredits: estimatedCredits,
              accountBalance: accountBalance,
            );
      }
    }
    while (generation == _sessionGeneration && identical(_service, service)) {
      final active = service.state;
      if (active != null &&
          active.snapshotId != snapshotId &&
          active.status == CoverageJobStatus.running) {
        // Waiting on the service tail would prevent pause/cancel/retirement
        // from reaching the running job that must become idle first.
        await service.waitUntilIdle();
      }
      final result = await _withActiveService<StartFullCoverageResult?>(
        service,
        () async {
          final current = service.state;
          if (current != null &&
              current.snapshotId != snapshotId &&
              current.status == CoverageJobStatus.running) {
            return null;
          }
          unawaited(
            Analytics.instance.track(AnalyticsEvents.aiCoverageStarted, {
              'snapshot_id': snapshotId,
              'mode': mode.name,
            }),
          );
          await service.start(
            snapshotId,
            budgetTokens: budgetTokens,
            budgetCredits: resolvedBudgetCredits,
          );
          return const StartFullCoverageStarted();
        },
        unavailable: const StartFullCoverageUnavailable(),
      );
      if (result != null) return result;
    }
    return const StartFullCoverageUnavailable();
  }

  Future<void> ensureJobRunning(String snapshotId) async {
    final generation = _sessionGeneration;
    await _sessionHandoff;
    if (generation != _sessionGeneration) return;
    final active = _service?.state;
    if (active != null &&
        active.snapshotId != snapshotId &&
        active.status == CoverageJobStatus.running) {
      return;
    }
    final state = await loadJobState(snapshotId);
    if (state == null || generation != _sessionGeneration) return;
    final shouldResume =
        state.status == CoverageJobStatus.running ||
        (state.status == CoverageJobStatus.paused &&
            state.pauseReason == CoveragePauseReason.appQuit);
    if (!shouldResume || coverageJobNeedsClientLogicUpgrade(state)) return;
    await tryResumeCoverage(snapshotId);
  }

  @override
  Future<void> pauseCoverage() async {
    final service = _service;
    if (service == null) return;
    await _withActiveService<void>(service, () async {
      await service.pause();
    }, unavailable: null);
  }

  @override
  Future<void> cancelCoverage(String snapshotId) {
    final generation = _sessionGeneration;
    final handoff = _sessionHandoff;
    return _enqueueServiceOperation(() async {
      await handoff;
      if (generation != _sessionGeneration || _retired) return;
      final service = _service;
      if (service != null) {
        await service.cancel(snapshotId);
        return;
      }
      final store = CoverageJobStateStore(SnapshotCache.cacheDir());
      final state = await store.load(snapshotId);
      if (state == null || generation != _sessionGeneration) return;
      if (state.status != CoverageJobStatus.running &&
          state.status != CoverageJobStatus.paused) {
        return;
      }
      final cancelled = state.copyWith(
        status: CoverageJobStatus.cancelled,
        pauseReason: () => null,
      );
      await store.save(cancelled);
      if (generation == _sessionGeneration) _notifyListeners(cancelled);
    });
  }

  Future<void> resumeCoverage(String snapshotId) async {
    await tryResumeCoverage(snapshotId);
  }

  @override
  Future<bool> tryResumeCoverage(String snapshotId) async {
    final generation = _sessionGeneration;
    final service = await _serviceForSnapshot(snapshotId);
    if (service == null || generation != _sessionGeneration) return false;
    if (!await _waitForCoverageSnapshotReady(snapshotId)) return false;
    if (generation != _sessionGeneration) return false;
    return _withActiveService(service, () async {
      await service.resume(snapshotId);
      return true;
    }, unavailable: false);
  }

  Future<void> raiseBudgetAndResume({
    required String snapshotId,
    required int budgetTokens,
    required int budgetCredits,
  }) async {
    await tryRaiseBudgetAndResume(
      snapshotId: snapshotId,
      budgetTokens: budgetTokens,
      budgetCredits: budgetCredits,
    );
  }

  @override
  Future<bool> tryRaiseBudgetAndResume({
    required String snapshotId,
    required int budgetTokens,
    required int budgetCredits,
  }) async {
    final generation = _sessionGeneration;
    final service = await _serviceForSnapshot(snapshotId);
    if (service == null || generation != _sessionGeneration) return false;
    return _withActiveService(service, () async {
      await service.raiseBudgetAndResume(
        snapshotId: snapshotId,
        budgetTokens: budgetTokens,
        budgetCredits: budgetCredits,
      );
      return true;
    }, unavailable: false);
  }

  Future<void> markAppQuit() async {
    final service = _service;
    if (service == null) return;
    await _withActiveService<void>(
      service,
      service.markAppQuit,
      unavailable: null,
    );
  }

  /// Waits until Rust has loaded the snapshot index for [snapshotId] (avoids
  /// `error:no index or snapshot loaded` during early app startup).
  Future<bool> _waitForCoverageSnapshotReady(String snapshotId) async {
    if (debugTreatSnapshotReady) return true;
    final session = _session;
    if (session == null) return false;
    if (session.isAiCoverageSnapshotReady(snapshotId)) return true;
    return waitUntilReady(
      isReady: () => session.isAiCoverageSnapshotReady(snapshotId),
      addListener: session.addListener,
      removeListener: session.removeListener,
      timeout: const Duration(minutes: 5),
    );
  }

  Future<void> _tryAutoResumeSavedJobs() async {
    final session = _session;
    if (session == null) return;
    final generation = _sessionGeneration;
    await _sessionHandoff;
    if (generation != _sessionGeneration) return;
    final ready = await waitUntilReady(
      isReady: () => _isCoverageApiReady(session),
      addListener: session.addListener,
      removeListener: session.removeListener,
    );
    if (!ready || generation != _sessionGeneration) return;
    final active = _service?.state;
    if (active != null && active.status == CoverageJobStatus.running) {
      return;
    }
    final provider = await _resolveProvider();
    if (provider == null) return;
    try {
      if (generation != _sessionGeneration) return;
      final dir = SnapshotCache.cacheDir();
      if (!await dir.exists()) return;
      final resumable = <CoverageJobState>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (generation != _sessionGeneration) return;
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        const prefix = 'ai_coverage_job_';
        if (!name.startsWith(prefix) || !name.endsWith('.json')) continue;
        final snapshotId = name.substring(
          prefix.length,
          name.length - '.json'.length,
        );
        final state = await CoverageJobStateStore(dir).load(snapshotId);
        if (state == null) continue;
        final shouldResume =
            state.status == CoverageJobStatus.running ||
            (state.status == CoverageJobStatus.paused &&
                state.pauseReason == CoveragePauseReason.appQuit);
        if (!shouldResume || coverageJobNeedsClientLogicUpgrade(state)) {
          continue;
        }
        resumable.add(state);
      }
      if (resumable.isEmpty || generation != _sessionGeneration) return;
      resumable.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      final state = resumable.first;
      if (!await tryResumeCoverage(state.snapshotId)) {
        debugPrint(
          'AiCoverageCoordinator: defer auto-resume until index is loaded '
          'for ${state.snapshotId}',
        );
      }
    } finally {
      _disposeUnownedProvider(provider);
    }
  }

  Future<AiCoverageService?> _serviceForSnapshot(String snapshotId) {
    final generation = _sessionGeneration;
    final handoff = _sessionHandoff;
    return _enqueueServiceOperation(() async {
      await handoff;
      if (generation != _sessionGeneration) return null;
      final current = _service;
      if (current != null) {
        final state = current.state;
        if (state != null &&
            state.snapshotId != snapshotId &&
            state.status == CoverageJobStatus.running) {
          return null;
        }
        if (state?.snapshotId == snapshotId &&
            _activeProvider != null &&
            current.isolateCatalogMatches(snapshotId)) {
          return current;
        }
        if (!current.isolateCatalogMatches(snapshotId)) {
          await _releaseService();
        }
      }
      if (generation != _sessionGeneration) return null;
      final provider = await _resolveProvider();
      if (provider == null) return null;
      if (generation != _sessionGeneration) {
        _disposeUnownedProvider(provider);
        return null;
      }
      return _prepareService(provider, catalogSnapshotId: snapshotId);
    });
  }

  Future<void> _releaseService({AiProvider? keepProvider}) async {
    final active = _takeService();
    if (active.service == null) return;
    final keep = identical(active.provider, keepProvider);
    try {
      await _closeService(
        active.service!,
        keep ? null : active.provider,
        active.subscription,
      );
    } finally {
      if (keep && active.provider != null) {
        _ownedProviders.remove(active.provider);
      }
    }
  }

  ({
    AiCoverageService? service,
    AiProvider? provider,
    StreamSubscription<CoverageJobState>? subscription,
  })
  _takeService() {
    final active = (
      service: _service,
      provider: _activeProvider,
      subscription: _statesSub,
    );
    _service = null;
    _activeProvider = null;
    _statesSub = null;
    return active;
  }

  Future<void> _closeService(
    AiCoverageService service,
    AiProvider? provider,
    StreamSubscription<CoverageJobState>? subscription,
  ) async {
    Object? firstError;
    StackTrace? firstStack;
    Future<void> attempt(FutureOr<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }

    await attempt(service.markAppQuit);
    await attempt(service.waitUntilIdle);
    await attempt(service.dispose);
    await attempt(service.waitUntilIdle);
    if (provider != null) {
      _ownedProviders.remove(provider);
      await attempt(() => _disposeUnownedProvider(provider));
    }
    if (subscription != null) await attempt(subscription.cancel);
    if (firstError != null) Error.throwWithStackTrace(firstError!, firstStack!);
  }

  bool _sameProvider(AiProvider? left, AiProvider right) {
    if (left == null) return false;
    return coverageProviderKey(left) == coverageProviderKey(right);
  }

  void _disposeUnownedProvider(AiProvider provider) {
    if (_ownedProviders.contains(provider) ||
        _disposedProviders[provider] == true) {
      return;
    }
    _disposedProviders[provider] = true;
    if (provider is ByokAiProvider) {
      provider.dispose();
    } else if (provider is PlatformAiProvider) {
      provider.dispose();
    }
  }

  void _onJobState(CoverageJobState state) {
    _notifyListeners(state);
    _trackAnalytics(state);
    unawaited(_maybeNotify(state));
  }

  void _notifyListeners(CoverageJobState state) {
    for (final listener in _listeners) {
      listener(state);
    }
  }

  void _trackAnalytics(CoverageJobState state) {
    final previous = _lastTrackedState;
    _lastTrackedState = state;
    if (previous?.snapshotId == state.snapshotId &&
        previous?.status == state.status) {
      return;
    }
    if (state.status == CoverageJobStatus.completed) {
      unawaited(
        Analytics.instance.track(AnalyticsEvents.aiCoverageCompleted, {
          'snapshot_id': state.snapshotId,
          'analyzed_files': state.analyzedFiles,
          'total_unclassified': state.totalUnclassified,
        }),
      );
      return;
    }
    if (state.status == CoverageJobStatus.paused &&
        state.pauseReason == CoveragePauseReason.failed) {
      unawaited(
        Analytics.instance.track(AnalyticsEvents.aiCoverageFailed, {
          'snapshot_id': state.snapshotId,
        }),
      );
    }
  }

  Future<void> _maybeNotify(
    CoverageJobState state, {
    AppLocalizations? l10n,
  }) async {
    final strings = l10n ?? coverageNotifyLocalizations();
    final snapshotId = state.snapshotId;
    if (state.status == CoverageJobStatus.completed) {
      final copy = coverageCompleteNotification(strings, state);
      await _desktopNotify(
        title: copy.title,
        body: copy.body,
        snapshotId: snapshotId,
      );
      return;
    }
    if (state.status == CoverageJobStatus.paused) {
      final reason = state.pauseReason;
      if (reason == CoveragePauseReason.budget) {
        final copy = coverageBudgetPausedNotification(strings, state);
        await _desktopNotify(
          title: copy.title,
          body: copy.body,
          snapshotId: snapshotId,
        );
      } else if (reason == CoveragePauseReason.failed) {
        final copy = coverageFailedNotification(strings);
        await _desktopNotify(
          title: copy.title,
          body: copy.body,
          snapshotId: snapshotId,
        );
      }
    }
  }
}

String coverageProviderKey(AiProvider provider) {
  if (provider is ByokAiProvider) {
    return 'byok:${provider.apiKey}';
  }
  if (provider is PlatformAiProvider) {
    return 'platform:${provider.token}';
  }
  return '${provider.runtimeType}@${identityHashCode(provider)}';
}
