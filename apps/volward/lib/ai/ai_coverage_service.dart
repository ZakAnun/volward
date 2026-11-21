import 'dart:async';

import 'package:flutter/foundation.dart';

import '../snapshot_cache.dart';
import 'ai_coverage_job_controller.dart';
import 'ai_provider.dart';
import 'byok_ai_provider.dart';
import 'cancel_token.dart';
import 'coverage_analyze_batch.dart';
import 'coverage_analyze_tree_batch.dart';
import 'coverage_engine.dart';
import 'coverage_job_isolate_host.dart';
import 'coverage_job_state.dart';
import 'coverage_snapshot_reader.dart';
import 'coverage_verdict_store.dart';
import 'platform_ai_provider.dart';
import 'native_coverage_engine.dart';

/// Process-scoped wiring for full-coverage AI analysis.
class AiCoverageService {
  @visibleForTesting
  static CoverageJobIsolateHost Function(String, Map<String, dynamic>)?
  debugHostFactory;

  @visibleForTesting
  AiCoverageService({
    required this.engine,
    required CoverageJobController this._controller,
    this.platformProvider,
    this.isolateCatalogPath,
    this.isolateCatalogSnapshotId,
  }) : _isolateHost = null,
       _releaseEngine = null,
       _checkAdmission = null;

  AiCoverageService._({
    required this.engine,
    this.platformProvider,
    this._controller,
    this._isolateHost,
    this.isolateCatalogPath,
    this.isolateCatalogSnapshotId,
    this._releaseEngine,
    this._checkAdmission,
  });

  final void Function()? _releaseEngine;
  final void Function()? _checkAdmission;
  bool _disposed = false;
  int _dispatches = 0;
  Completer<void>? _dispatchesIdle;
  Future<void> _commandTail = Future.value();
  Future<void>? _shutdown;
  final _hostControls = <Future<void>>{};

  Future<T> _command<T>(Future<T> Function() action) async {
    final previous = _commandTail;
    final done = Completer<void>();
    _commandTail = done.future;
    await previous;
    try {
      _ensureOpen();
      return await action();
    } finally {
      done.complete();
    }
  }

  Future<T> _trackHostControl<T>(Future<T> Function() action) {
    final result = action();
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _hostControls.add(settled);
    unawaited(settled.whenComplete(() => _hostControls.remove(settled)));
    return result;
  }

  // Serialize dispatch, while the tracked caller still awaits the control reply.
  Future<T> _dispatchControl<T>(Future<T> Function() action) async {
    final result = await _command<({Future<T> pending})>(
      () async => (pending: _trackHostControl(action)),
    );
    return result.pending;
  }

  Future<CoverageJobState> _runForSnapshot(
    String snapshotId,
    Future<CoverageJobState> Function() action, {
    bool deferCompletion = false,
  }) async {
    while (true) {
      final result =
          await _command<
            ({Future<CoverageJobState>? pending, Future<void>? wait})?
          >(() async {
            if (_isolateHost != null &&
                !deferCompletion &&
                _hostControls.isNotEmpty) {
              return (pending: null, wait: Future.wait(_hostControls.toList()));
            }
            final current = state;
            // Host status is only an early-wait hint; the worker rechecks its
            // execution signal before admission. Main-isolate admission uses that
            // signal directly, so no controller call can hide a queued start.
            final running =
                _controller?.isRunning ??
                (current?.status == CoverageJobStatus.running);
            if (running && current?.snapshotId != snapshotId) {
              return null;
            }
            if (_isolateHost != null &&
                (deferCompletion ||
                    (current != null && current.snapshotId != snapshotId))) {
              // The worker makes the authoritative execution check. Its correlated
              // reply may wait for an old run even when the last status is paused;
              // leave this queue available for controls while that reply is pending.
              return (
                pending: deferCompletion ? _trackHostControl(action) : action(),
                wait: null,
              );
            }
            return (pending: Future.value(await action()), wait: null);
          });
      if (result?.pending != null) return result!.pending!;
      if (result?.wait != null) {
        await result!.wait;
        continue;
      }
      _ensureOpen();
      await (_isolateHost?.waitUntilIdle() ?? _controller!.waitUntilIdle());
    }
  }

  void _ensureOpen() {
    if (_disposed) throw StateError('Coverage service is disposed');
  }

  Future<T> _trackDispatch<T>(Future<T> Function() action) =>
      _track(action, checkAdmission: true);

  Future<T> _trackControl<T>(Future<T> Function() action) => _track(action);

  Future<T> _track<T>(
    Future<T> Function() action, {
    bool checkAdmission = false,
  }) async {
    _ensureOpen();
    if (checkAdmission) _checkAdmission?.call();
    _dispatches++;
    try {
      return await action();
    } finally {
      _dispatches--;
      if (_dispatches == 0) {
        _dispatchesIdle?.complete();
        _dispatchesIdle = null;
      }
    }
  }

  Future<void> _drainDispatches() async {
    while (_dispatches != 0) {
      _dispatchesIdle ??= Completer<void>();
      await _dispatchesIdle!.future;
    }
  }

  final CoverageJobController? _controller;
  final CoverageJobIsolateHost? _isolateHost;
  final CoverageEngine engine;
  final PlatformAiProvider? platformProvider;

  /// Catalog file loaded by the background worker, if any.
  final String? isolateCatalogPath;

  /// Snapshot id the worker catalog is intended to represent.
  final String? isolateCatalogSnapshotId;

  static bool _preferBackgroundJobIsolate() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  static Future<AiCoverageService?> tryCreate({
    required CoverageSnapshotReader session,
    required AiProvider provider,
    CoverageResumePlanLoader? resumePlanLoader,
    String? catalogSnapshotId,
    bool runJobOnMainIsolate = false,
  }) async {
    final rootEngine = session.coverageEngine;
    if (rootEngine == null) return null;
    final scoped = rootEngine is NativeCoverageEngine
        ? rootEngine.scopedForService()
        : null;
    final nativeEngine = scoped?.$1 ?? rootEngine;
    final releaseEngine = scoped?.$2;
    void checkAdmission() {
      if (rootEngine is NativeCoverageEngine) rootEngine.retain()?.call();
    }

    try {
      final cacheDir = SnapshotCache.cacheDir();
      final cancelToken = CancelToken();
      final platformProvider = provider is PlatformAiProvider ? provider : null;
      final preferTree = session.hasAiTreeCoverageApi;

      if (!runJobOnMainIsolate && _preferBackgroundJobIsolate()) {
        final currentSnapshotId = session.currentCoverageSnapshotId;
        final targetSnapshotId = catalogSnapshotId ?? currentSnapshotId;
        final catalogPath = targetSnapshotId == null
            ? null
            : await session.catalogIndexPathForAiCoverage(targetSnapshotId);
        if (catalogPath != null && catalogPath.isNotEmpty) {
          final workerConfig = <String, dynamic>{
            'hasIndexApi': session.hasIndexApi,
            'preferTree': preferTree,
            'providerKind': provider is PlatformAiProvider
                ? 'platform'
                : 'byok',
            if (provider is ByokAiProvider) 'byokApiKey': provider.apiKey,
            if (provider is PlatformAiProvider) ...{
              'platformToken': provider.token,
              'platformBaseUrl': provider.baseUrl,
            },
          };
          debugPrint(
            'AiCoverageService: full coverage job on background isolate '
            '(catalog=$catalogPath)',
          );
          final host =
              debugHostFactory?.call(catalogPath, workerConfig) ??
              CoverageJobIsolateHost(
                catalogPath: catalogPath,
                workerConfig: workerConfig,
              );
          return AiCoverageService._(
            engine: rootEngine,
            platformProvider: platformProvider,
            isolateHost: host,
            isolateCatalogPath: catalogPath,
            isolateCatalogSnapshotId: targetSnapshotId,
            releaseEngine: releaseEngine,
            checkAdmission: checkAdmission,
          );
        }
        debugPrint(
          'AiCoverageService: no catalog for snapshot=$targetSnapshotId; '
          'running full coverage job on the UI isolate',
        );
      }

      AnalyzeTreeBatch? treeBatch;
      if (provider is TreeAiProvider) {
        treeBatch = createCoverageAnalyzeTreeBatch(
          provider: provider as TreeAiProvider,
          cancelToken: cancelToken,
        );
      }
      return AiCoverageService._(
        engine: rootEngine,
        platformProvider: platformProvider,
        releaseEngine: releaseEngine,
        checkAdmission: checkAdmission,
        controller: CoverageJobController(
          engine: nativeEngine,
          verdictStore: CoverageVerdictStore(cacheDir),
          stateStore: CoverageJobStateStore(cacheDir),
          analyzeBatch: createCoverageAnalyzeBatch(
            provider: provider,
            cancelToken: cancelToken,
          ),
          analyzeTreeBatch: treeBatch,
          preferTreeCoveragePlan: preferTree,
          cancelToken: cancelToken,
          platformCreditsRemaining: platformProvider == null
              ? null
              : () => platformProvider.lastCreditsRemaining,
          resumePlanLoader: resumePlanLoader == null
              ? null
              : (snapshotId, job) => nativeEngine is NativeCoverageEngine
                    ? nativeEngine.withMaterializedReadScope(
                        () => resumePlanLoader(snapshotId, job),
                      )
                    : resumePlanLoader(snapshotId, job),
        ),
      );
    } catch (_) {
      releaseEngine?.call();
      rethrow;
    }
  }

  Future<void> _refreshPlatformWallet() async {
    final provider = platformProvider;
    if (provider == null) return;
    await provider.queryQuota();
  }

  Future<CoverageJobState> start(
    String snapshotId, {
    required int budgetTokens,
    required int budgetCredits,
  }) => _trackDispatch(() async {
    await _refreshPlatformWallet();
    _ensureOpen();
    final host = _isolateHost;
    if (host != null) {
      return _runForSnapshot(
        snapshotId,
        () => host.start(
          snapshotId,
          budgetTokens: budgetTokens,
          budgetCredits: budgetCredits,
          detachRun: true,
        ),
      );
    }
    return _runForSnapshot(
      snapshotId,
      () => _controller!.start(
        snapshotId,
        budgetTokens: budgetTokens,
        budgetCredits: budgetCredits,
        detachRun: true,
      ),
    );
  });

  Future<CoverageJobState> pause() => _trackControl(() {
    final host = _isolateHost;
    if (host != null) return _dispatchControl(host.pause);
    return _controller!.pause();
  });

  Future<CoverageJobState> cancel(String snapshotId) => _trackControl(() {
    final host = _isolateHost;
    if (host != null) {
      return _runForSnapshot(
        snapshotId,
        () => host.cancel(snapshotId),
        deferCompletion: true,
      );
    }
    return _runForSnapshot(snapshotId, () => _controller!.cancel(snapshotId));
  });

  Future<CoverageJobState> resume(String snapshotId) =>
      _trackDispatch(() async {
        await _refreshPlatformWallet();
        _ensureOpen();
        final host = _isolateHost;
        if (host != null) {
          return _runForSnapshot(
            snapshotId,
            () => host.resume(snapshotId, detachRun: true),
          );
        }
        return _runForSnapshot(
          snapshotId,
          () => _controller!.resume(snapshotId, detachRun: true),
        );
      });

  Future<CoverageJobState> raiseBudgetAndResume({
    required String snapshotId,
    required int budgetTokens,
    required int budgetCredits,
  }) => _trackDispatch(() async {
    await _refreshPlatformWallet();
    _ensureOpen();
    final host = _isolateHost;
    if (host != null) {
      return _runForSnapshot(
        snapshotId,
        () => host.raiseBudgetAndResume(
          snapshotId: snapshotId,
          budgetTokens: budgetTokens,
          budgetCredits: budgetCredits,
          detachRun: true,
        ),
      );
    }
    return _runForSnapshot(
      snapshotId,
      () => _controller!.raiseBudgetAndResume(
        snapshotId: snapshotId,
        budgetTokens: budgetTokens,
        budgetCredits: budgetCredits,
        detachRun: true,
      ),
    );
  });

  Future<void> markAppQuit() => _trackControl(() {
    final host = _isolateHost;
    if (host != null) return _dispatchControl(host.markAppQuit);
    return _controller!.markAppQuit();
  });

  Future<void> waitUntilIdle() {
    if (_disposed) return _shutdown ?? Future.value();
    return _trackControl(() {
      final host = _isolateHost;
      if (host != null) return host.waitUntilIdle();
      return _controller!.waitUntilIdle();
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final controller = _controller;
    final host = _isolateHost;
    final release = _releaseEngine;
    Object? failure;
    StackTrace? failureStack;
    void record(Object error, StackTrace stack) {
      failure ??= error;
      failureStack ??= stack;
    }

    try {
      controller?.dispose();
    } catch (error, stack) {
      record(error, stack);
    }
    _shutdown = () async {
      Future<bool> attempt(FutureOr<void> Function() action) async {
        try {
          await action();
          return true;
        } catch (error, stack) {
          record(error, stack);
          return false;
        }
      }

      if (host != null) {
        // Close admission before waking queued dispatches. On failure, dispose
        // immediately to settle host requests before joining service dispatches.
        final stopped = await attempt(host.beginShutdown);
        if (!stopped) await attempt(host.dispose);
      }
      if (controller != null) {
        await attempt(() async {
          await _commandTail;
          await controller.markAppQuit();
        });
      }
      await attempt(_drainDispatches);
      if (controller != null) await attempt(controller.waitUntilIdle);
      if (host != null) await attempt(host.dispose);
      if (release != null) await attempt(release);
      if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
    }();
    // dispose is synchronous; attach an observer until callers await shutdown.
    unawaited(
      _shutdown!.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  CoverageJobState? get state => _isolateHost?.state ?? _controller?.state;

  Stream<CoverageJobState> get states =>
      _isolateHost?.states ?? _controller!.states;

  bool isolateCatalogMatches(String snapshotId) {
    if (_isolateHost == null) return true;
    if (isolateCatalogSnapshotId == snapshotId) return true;
    return false;
  }
}
