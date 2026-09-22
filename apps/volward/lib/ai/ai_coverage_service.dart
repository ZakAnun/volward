import 'dart:async';

import 'package:flutter/foundation.dart';

import '../snapshot_cache.dart';
import '../volward_session.dart';
import 'ai_coverage_job_controller.dart';
import 'ai_provider.dart';
import 'byok_ai_provider.dart';
import 'coverage_job_isolate_host.dart';
import 'platform_ai_provider.dart';
import 'cancel_token.dart';
import 'coverage_analyze_batch.dart';
import 'coverage_analyze_tree_batch.dart';
import 'coverage_engine.dart';
import 'coverage_job_state.dart';
import 'coverage_verdict_store.dart';

/// Process-scoped wiring for full-coverage AI analysis.
class AiCoverageService {
  @visibleForTesting
  AiCoverageService({
    required this.engine,
    required CoverageJobController this._controller,
    this.platformProvider,
    this.isolateCatalogPath,
    this.isolateCatalogSnapshotId,
  }) : _isolateHost = null;

  AiCoverageService._({
    required this.engine,
    this.platformProvider,
    this._controller,
    this._isolateHost,
    this.isolateCatalogPath,
    this.isolateCatalogSnapshotId,
  });

  final CoverageJobController? _controller;
  final CoverageJobIsolateHost? _isolateHost;
  final CoverageEngine engine;
  final PlatformAiProvider? platformProvider;

  /// Catalog file loaded by the background worker, if any.
  final String? isolateCatalogPath;

  /// Snapshot id the worker catalog is intended to represent.
  final String? isolateCatalogSnapshotId;

  static bool _preferBackgroundJobIsolate(VolwardSession session) {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  static Future<AiCoverageService?> tryCreate({
    required VolwardSession session,
    required AiProvider provider,
    CoverageResumePlanLoader? resumePlanLoader,
    String? catalogSnapshotId,
    bool runJobOnMainIsolate = false,
  }) async {
    final nativeEngine = session.coverageEngine;
    if (nativeEngine == null) return null;
    final cacheDir = SnapshotCache.cacheDir();
    final cancelToken = CancelToken();
    final platformProvider = provider is PlatformAiProvider ? provider : null;
    final preferTree = session.hasAiTreeCoverageApi;

    if (!runJobOnMainIsolate && _preferBackgroundJobIsolate(session)) {
      final snap = session.lastSnapshot;
      final targetSnapshotId = catalogSnapshotId ?? snap?.snapshotId;
      final catalogPath = targetSnapshotId == null
          ? null
          : await session.catalogIndexPathForAiCoverage(targetSnapshotId);
      if (catalogPath != null && catalogPath.isNotEmpty) {
        final workerConfig = <String, dynamic>{
          'hasIndexApi': session.hasIndexApi,
          'preferTree': preferTree,
          'providerKind': provider is PlatformAiProvider ? 'platform' : 'byok',
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
        final host = CoverageJobIsolateHost(
          catalogPath: catalogPath,
          workerConfig: workerConfig,
        );
        return AiCoverageService._(
          engine: nativeEngine,
          platformProvider: platformProvider,
          isolateHost: host,
          isolateCatalogPath: catalogPath,
          isolateCatalogSnapshotId: targetSnapshotId,
        );
      }
    }

    AnalyzeTreeBatch? treeBatch;
    if (provider is TreeAiProvider) {
      treeBatch = createCoverageAnalyzeTreeBatch(
        provider: provider as TreeAiProvider,
        cancelToken: cancelToken,
      );
    }
    return AiCoverageService._(
      engine: nativeEngine,
      platformProvider: platformProvider,
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
        resumePlanLoader: resumePlanLoader,
      ),
    );
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
  }) async {
    await _refreshPlatformWallet();
    final host = _isolateHost;
    if (host != null) {
      return host.start(
        snapshotId,
        budgetTokens: budgetTokens,
        budgetCredits: budgetCredits,
        detachRun: true,
      );
    }
    return _controller!.start(
      snapshotId,
      budgetTokens: budgetTokens,
      budgetCredits: budgetCredits,
      detachRun: true,
    );
  }

  Future<CoverageJobState> pause() {
    final host = _isolateHost;
    if (host != null) return host.pause();
    return _controller!.pause();
  }

  Future<CoverageJobState> cancel(String snapshotId) {
    final host = _isolateHost;
    if (host != null) return host.cancel(snapshotId);
    return _controller!.cancel(snapshotId);
  }

  Future<CoverageJobState> resume(String snapshotId) async {
    await _refreshPlatformWallet();
    final host = _isolateHost;
    if (host != null) return host.resume(snapshotId, detachRun: true);
    return _controller!.resume(snapshotId, detachRun: true);
  }

  Future<CoverageJobState> raiseBudgetAndResume({
    required String snapshotId,
    required int budgetTokens,
    required int budgetCredits,
  }) async {
    await _refreshPlatformWallet();
    final host = _isolateHost;
    if (host != null) {
      return host.raiseBudgetAndResume(
        snapshotId: snapshotId,
        budgetTokens: budgetTokens,
        budgetCredits: budgetCredits,
        detachRun: true,
      );
    }
    return _controller!.raiseBudgetAndResume(
      snapshotId: snapshotId,
      budgetTokens: budgetTokens,
      budgetCredits: budgetCredits,
      detachRun: true,
    );
  }

  Future<void> markAppQuit() {
    final host = _isolateHost;
    if (host != null) return host.markAppQuit();
    return _controller!.markAppQuit();
  }

  Future<void> waitUntilIdle() {
    final host = _isolateHost;
    if (host != null) return host.waitUntilIdle();
    return _controller!.waitUntilIdle();
  }

  void dispose() {
    unawaited(_isolateHost?.dispose());
    _controller?.dispose();
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
