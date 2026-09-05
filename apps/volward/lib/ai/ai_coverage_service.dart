import '../snapshot_cache.dart';
import '../volward_session.dart';
import 'ai_coverage_job_controller.dart';
import 'ai_provider.dart';
import 'coverage_analyze_batch.dart';
import 'coverage_engine.dart';
import 'coverage_job_state.dart';
import 'coverage_verdict_store.dart';

/// Process-scoped wiring for full-coverage AI analysis.
class AiCoverageService {
  AiCoverageService({required this.controller, required this.engine});

  final CoverageJobController controller;
  final CoverageEngine engine;

  static AiCoverageService? tryCreate({
    required VolwardSession session,
    required AiProvider provider,
  }) {
    final nativeEngine = session.coverageEngine;
    if (nativeEngine == null) return null;
    final cacheDir = SnapshotCache.cacheDir();
    return AiCoverageService(
      engine: nativeEngine,
      controller: CoverageJobController(
        engine: nativeEngine,
        verdictStore: CoverageVerdictStore(cacheDir),
        stateStore: CoverageJobStateStore(cacheDir),
        analyzeBatch: createCoverageAnalyzeBatch(provider: provider),
      ),
    );
  }

  Future<CoverageJobState> start(
    String snapshotId, {
    required int budgetTokens,
    required int budgetCredits,
  }) => controller.start(
    snapshotId,
    budgetTokens: budgetTokens,
    budgetCredits: budgetCredits,
  );

  Future<CoverageJobState> pause() => controller.pause();

  Future<CoverageJobState> resume() => controller.resume();

  CoverageJobState? get state => controller.state;

  Stream<CoverageJobState> get states => controller.states;
}
