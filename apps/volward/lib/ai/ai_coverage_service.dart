import '../snapshot_cache.dart';
import '../volward_session.dart';
import 'ai_coverage_job_controller.dart';
import 'ai_provider.dart';
import 'platform_ai_provider.dart';
import 'cancel_token.dart';
import 'coverage_analyze_batch.dart';
import 'coverage_analyze_tree_batch.dart';
import 'coverage_engine.dart';
import 'coverage_job_state.dart';
import 'coverage_verdict_store.dart';

/// Process-scoped wiring for full-coverage AI analysis.
class AiCoverageService {
  AiCoverageService({
    required this.controller,
    required this.engine,
    this.platformProvider,
  });

  final CoverageJobController controller;
  final CoverageEngine engine;
  final PlatformAiProvider? platformProvider;

  static AiCoverageService? tryCreate({
    required VolwardSession session,
    required AiProvider provider,
  }) {
    final nativeEngine = session.coverageEngine;
    if (nativeEngine == null) return null;
    final cacheDir = SnapshotCache.cacheDir();
    final cancelToken = CancelToken();
    final platformProvider = provider is PlatformAiProvider ? provider : null;
    final preferTree = session.hasAiTreeCoverageApi;
    AnalyzeTreeBatch? treeBatch;
    if (provider is TreeAiProvider) {
      treeBatch = createCoverageAnalyzeTreeBatch(
        provider: provider as TreeAiProvider,
        cancelToken: cancelToken,
      );
    }
    return AiCoverageService(
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
    return controller.start(
      snapshotId,
      budgetTokens: budgetTokens,
      budgetCredits: budgetCredits,
      detachRun: true,
    );
  }

  Future<CoverageJobState> pause() => controller.pause();

  Future<CoverageJobState> cancel(String snapshotId) =>
      controller.cancel(snapshotId);

  Future<CoverageJobState> resume(String snapshotId) async {
    await _refreshPlatformWallet();
    return controller.resume(snapshotId, detachRun: true);
  }

  Future<CoverageJobState> raiseBudgetAndResume({
    required String snapshotId,
    required int budgetTokens,
    required int budgetCredits,
  }) async {
    await _refreshPlatformWallet();
    return controller.raiseBudgetAndResume(
      snapshotId: snapshotId,
      budgetTokens: budgetTokens,
      budgetCredits: budgetCredits,
      detachRun: true,
    );
  }

  Future<void> markAppQuit() => controller.markAppQuit();

  Future<void> waitUntilIdle() => controller.waitUntilIdle();

  void dispose() => controller.dispose();

  CoverageJobState? get state => controller.state;

  Stream<CoverageJobState> get states => controller.states;
}
