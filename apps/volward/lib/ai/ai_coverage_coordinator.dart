import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../analytics/analytics.dart';
import '../analytics/analytics_events.dart';
import '../l10n/generated/app_localizations.dart';
import '../snapshot_cache.dart';
import '../volward_session.dart';
import 'ai_coverage_service.dart';
import 'ai_provider.dart';
import 'byok_ai_provider.dart';
import 'platform_ai_provider.dart';
import 'ai_settings_store.dart';
import 'coverage_desktop_notify.dart';
import 'coverage_job_state.dart';
import 'coverage_lifecycle.dart';
import 'coverage_notification_text.dart';

typedef CoverageDesktopNotify =
    Future<void> Function({required String title, required String body});

typedef CoverageServiceFactory =
    AiCoverageService? Function({
      required VolwardSession session,
      required AiProvider provider,
    });

/// Process-scoped owner for full-coverage jobs (Design §5.3).
class AiCoverageCoordinator with WidgetsBindingObserver {
  AiCoverageCoordinator._({
    CoverageDesktopNotify? desktopNotify,
    CoverageServiceFactory? serviceFactory,
    bool Function(VolwardSession session)? isCoverageApiReady,
    Future<AiProvider?> Function()? resolveProvider,
  }) : _desktopNotify = desktopNotify ?? showCoverageDesktopNotification,
       _serviceFactory = serviceFactory ?? AiCoverageService.tryCreate,
       _isCoverageApiReady =
           isCoverageApiReady ?? ((session) => session.hasAiCoverageApi),
       _resolveProvider =
           resolveProvider ?? AiSettingsStore.instance.resolveProvider;

  static final AiCoverageCoordinator instance = AiCoverageCoordinator._();

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

  final CoverageDesktopNotify _desktopNotify;
  final CoverageServiceFactory _serviceFactory;
  final bool Function(VolwardSession session) _isCoverageApiReady;
  final Future<AiProvider?> Function() _resolveProvider;

  VolwardSession? _session;
  AiCoverageService? _service;
  AiProvider? _activeProvider;
  StreamSubscription<CoverageJobState>? _statesSub;
  Future<void> _prepareServiceTail = Future<void>.value();
  final _listeners = <void Function(CoverageJobState state)>{};
  CoverageJobState? _lastTrackedState;

  @Deprecated('Use addJobStateListener/removeJobStateListener')
  set listener(void Function(CoverageJobState state)? callback) {
    _listeners.clear();
    if (callback != null) {
      _listeners.add(callback);
    }
  }

  void addJobStateListener(void Function(CoverageJobState state) listener) {
    _listeners.add(listener);
  }

  void removeJobStateListener(void Function(CoverageJobState state) listener) {
    _listeners.remove(listener);
  }

  bool get isAttached => _session != null;

  bool get isAvailable => _session?.hasAiCoverageApi ?? false;

  CoverageJobState? get currentState => _service?.state;

  Stream<CoverageJobState>? get states => _service?.states;

  void attach(VolwardSession session) {
    if (identical(_session, session)) return;
    _session = session;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_tryAutoResumeSavedJobs());
  }

  void detach() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(markAppQuit());
    unawaited(_releaseService());
    _session = null;
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

  Future<CoverageJobState?> loadJobState(String snapshotId) =>
      CoverageJobStateStore(SnapshotCache.cacheDir()).load(snapshotId);

  Future<AiCoverageService?> prepareService(AiProvider provider) {
    final operation = _prepareServiceTail.then(
      (_) => _prepareService(provider),
    );
    _prepareServiceTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<AiCoverageService?> _prepareService(AiProvider provider) async {
    final session = _session;
    if (session == null || !_isCoverageApiReady(session)) return null;
    if (_service != null && _sameProvider(_activeProvider, provider)) {
      if (!identical(provider, _activeProvider)) {
        _disposeProvider(provider);
      }
      return _service;
    }
    await _releaseService();
    _service = _serviceFactory(session: session, provider: provider);
    _activeProvider = provider;
    _statesSub?.cancel();
    final stream = _service?.states;
    if (stream != null) {
      _statesSub = stream.listen(_onJobState, onError: (_) {});
    }
    return _service;
  }

  Future<bool> startFullCoverage({
    required String snapshotId,
    required AiMode mode,
    required AiProvider provider,
  }) async {
    final service = await prepareService(provider);
    if (service == null) return false;
    final budget = await AiSettingsStore.instance.coverageBudgetForMode(mode);
    unawaited(
      Analytics.instance.track(AnalyticsEvents.aiCoverageStarted, {
        'snapshot_id': snapshotId,
        'mode': mode.name,
      }),
    );
    await service.start(
      snapshotId,
      budgetTokens: budget.tokens,
      budgetCredits: budget.credits,
    );
    return true;
  }

  Future<void> ensureJobRunning(String snapshotId) async {
    final active = _service?.state;
    if (active != null &&
        active.snapshotId != snapshotId &&
        active.status == CoverageJobStatus.running) {
      return;
    }
    final state = await loadJobState(snapshotId);
    if (state == null) return;
    final shouldResume =
        state.status == CoverageJobStatus.running ||
        (state.status == CoverageJobStatus.paused &&
            state.pauseReason == CoveragePauseReason.appQuit);
    if (!shouldResume) return;
    final provider = await _resolveProvider();
    if (provider == null) return;
    final service = await prepareService(provider);
    if (service == null) return;
    await service.resume(snapshotId);
  }

  Future<void> pauseCoverage() async {
    await _service?.pause();
  }

  Future<void> cancelCoverage(String snapshotId) async {
    final service = _service;
    if (service != null) {
      await service.cancel(snapshotId);
      return;
    }
    final store = CoverageJobStateStore(SnapshotCache.cacheDir());
    final state = await store.load(snapshotId);
    if (state == null) return;
    if (state.status != CoverageJobStatus.running &&
        state.status != CoverageJobStatus.paused) {
      return;
    }
    final cancelled = state.copyWith(
      status: CoverageJobStatus.cancelled,
      pauseReason: () => null,
    );
    await store.save(cancelled);
    _notifyListeners(cancelled);
  }

  Future<void> resumeCoverage(String snapshotId) async {
    final service = await _serviceForSnapshot(snapshotId);
    if (service == null) return;
    await service.resume(snapshotId);
  }

  Future<bool> tryResumeCoverage(String snapshotId) async {
    final service = await _serviceForSnapshot(snapshotId);
    if (service == null) return false;
    await service.resume(snapshotId);
    return true;
  }

  Future<void> raiseBudgetAndResume({
    required String snapshotId,
    required int budgetTokens,
    required int budgetCredits,
  }) async {
    final service = await _serviceForSnapshot(snapshotId);
    if (service == null) return;
    await service.raiseBudgetAndResume(
      snapshotId: snapshotId,
      budgetTokens: budgetTokens,
      budgetCredits: budgetCredits,
    );
  }

  Future<bool> tryRaiseBudgetAndResume({
    required String snapshotId,
    required int budgetTokens,
    required int budgetCredits,
  }) async {
    final service = await _serviceForSnapshot(snapshotId);
    if (service == null) return false;
    await service.raiseBudgetAndResume(
      snapshotId: snapshotId,
      budgetTokens: budgetTokens,
      budgetCredits: budgetCredits,
    );
    return true;
  }

  Future<void> markAppQuit() async {
    await _service?.markAppQuit();
  }

  Future<void> _tryAutoResumeSavedJobs() async {
    final session = _session;
    if (session == null) return;
    final ready = await waitUntilReady(
      isReady: () => _isCoverageApiReady(session),
      addListener: session.addListener,
      removeListener: session.removeListener,
    );
    if (!ready) return;
    final active = _service?.state;
    if (active != null && active.status == CoverageJobStatus.running) {
      return;
    }
    final provider = await _resolveProvider();
    if (provider == null) return;
    final dir = SnapshotCache.cacheDir();
    if (!await dir.exists()) return;
    final resumable = <CoverageJobState>[];
    await for (final entity in dir.list(followLinks: false)) {
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
      if (!shouldResume) continue;
      resumable.add(state);
    }
    if (resumable.isEmpty) return;
    resumable.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    final state = resumable.first;
    final service = await prepareService(provider);
    if (service == null) return;
    await service.resume(state.snapshotId);
  }

  Future<AiCoverageService?> _serviceForSnapshot(String snapshotId) async {
    final current = _service;
    if (current != null) {
      final state = current.state;
      if (state != null &&
          state.snapshotId != snapshotId &&
          state.status == CoverageJobStatus.running) {
        return null;
      }
      if (state?.snapshotId == snapshotId && _activeProvider != null) {
        return current;
      }
    }
    final provider = await _resolveProvider();
    if (provider == null) return null;
    return prepareService(provider);
  }

  Future<void> _releaseService() async {
    final old = _service;
    if (old == null) return;
    await old.markAppQuit();
    await old.waitUntilIdle();
    old.dispose();
    final provider = _activeProvider;
    if (provider != null) {
      _disposeProvider(provider);
    }
    _statesSub?.cancel();
    _statesSub = null;
    _service = null;
    _activeProvider = null;
  }

  bool _sameProvider(AiProvider? left, AiProvider right) {
    if (left == null) return false;
    return coverageProviderKey(left) == coverageProviderKey(right);
  }

  void _disposeProvider(AiProvider provider) {
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
    if (state.status == CoverageJobStatus.completed) {
      final copy = coverageCompleteNotification(strings, state);
      await _desktopNotify(title: copy.title, body: copy.body);
      return;
    }
    if (state.status == CoverageJobStatus.paused) {
      final reason = state.pauseReason;
      if (reason == CoveragePauseReason.budget) {
        final copy = coverageBudgetPausedNotification(strings, state);
        await _desktopNotify(title: copy.title, body: copy.body);
      } else if (reason == CoveragePauseReason.failed) {
        final copy = coverageFailedNotification(strings);
        await _desktopNotify(title: copy.title, body: copy.body);
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
