import '../../ai/ai_candidates_materialized_cache.dart';
import '../../ai/ai_coverage_coordinator.dart';
import '../../ai/ai_coverage_service.dart';
import '../../ai/ai_provider.dart';
import '../../ai/ai_settings_store.dart';
import '../../ai/coverage_job_state.dart';
import '../../ai/coverage_models.dart';
import '../../ai/platform_auth_store.dart';
import '../../analytics/analytics.dart';
import '../../features/ai_coverage/ports/workspace_ports.dart';

AiWorkspacePorts createProductionAiWorkspacePorts({
  AiCoverageJobs? coverageJobs,
}) {
  return AiWorkspacePorts(
    analytics: const _AnalyticsAdapter(),
    settings: const _SettingsAdapter(),
    auth: const _AuthAdapter(),
    coverageJobs: _CoordinatorAdapter(
      coverageJobs ?? AiCoverageCoordinator.instance,
    ),
    candidateCache: const _CandidateCacheAdapter(),
  );
}

final class _AnalyticsAdapter implements WorkspaceAnalyticsPort {
  const _AnalyticsAdapter();

  @override
  Future<void> track(String name, [Map<String, Object?>? props]) =>
      Analytics.instance.track(name, props);
}

final class _SettingsAdapter implements WorkspaceSettingsPort {
  const _SettingsAdapter();

  AiSettingsStore get _store => AiSettingsStore.instance;

  @override
  Future<ByokTokenUsageTotals> addByokTokenUsage({
    required int inputTokens,
    required int outputTokens,
    required int totalTokens,
    required bool estimated,
    required bool partial,
  }) {
    return _store.addByokTokenUsage(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      totalTokens: totalTokens,
      estimated: estimated,
      partial: partial,
    );
  }

  @override
  Future<bool> conclusionNarrativeAuto() => _store.conclusionNarrativeAuto();

  @override
  Future<bool> conclusionNarrativeEnabled() =>
      _store.conclusionNarrativeEnabled();

  @override
  Future<({int tokens, int credits})> coverageBudgetForMode(AiMode mode) =>
      _store.coverageBudgetForMode(mode);

  @override
  Future<int> resolveRunBudgetCredits({
    required int estimatedCredits,
    required int accountBalance,
  }) {
    return _store.resolveRunBudgetCredits(
      estimatedCredits: estimatedCredits,
      accountBalance: accountBalance,
    );
  }

  @override
  Future<void> setCoverageBudgetCredits(int credits) =>
      _store.setCoverageBudgetCredits(credits);

  @override
  Future<void> setCoverageBudgetTokens(int tokens) =>
      _store.setCoverageBudgetTokens(tokens);
}

final class _AuthAdapter implements WorkspaceAuthPort {
  const _AuthAdapter();

  @override
  Future<bool> hasAuthenticatedUser() async =>
      await PlatformAuthStore.instance.currentUser() != null;
}

final class _CandidateCacheAdapter implements WorkspaceCandidateCachePort {
  const _CandidateCacheAdapter();

  @override
  void clearSnapshot(String snapshotId) {
    AiCandidatesMaterializedCache.instance.clearSnapshot(snapshotId);
  }
}

final class _CoordinatorAdapter implements WorkspaceCoverageJobsPort {
  const _CoordinatorAdapter(this._delegate);

  final AiCoverageJobs _delegate;

  @override
  bool operator ==(Object other) =>
      other is _CoordinatorAdapter && other._delegate == _delegate;

  @override
  int get hashCode => _delegate.hashCode;

  @override
  bool get isAvailable => _delegate.isAvailable;

  @override
  void addJobStateListener(void Function(CoverageJobState) listener) =>
      _delegate.addJobStateListener(listener);

  @override
  void removeJobStateListener(void Function(CoverageJobState) listener) =>
      _delegate.removeJobStateListener(listener);

  @override
  Future<CoverageJobState?> loadJobState(String snapshotId) =>
      _delegate.loadJobState(snapshotId);

  @override
  Future<CoveragePlanSummary?> planSummary(String snapshotId) =>
      _delegate.planSummary(snapshotId);

  @override
  void invalidatePlanSummaryCache() => _delegate.invalidatePlanSummaryCache();

  @override
  Future<AiCoverageService?> prepareService(AiProvider provider) =>
      _delegate.prepareService(provider);

  @override
  Future<StartFullCoverageResult> startFullCoverage({
    required String snapshotId,
    required AiMode mode,
    required AiProvider provider,
    int? budgetCredits,
    CoveragePlanSummary? preloadedPlanSummary,
  }) {
    return _delegate.startFullCoverage(
      snapshotId: snapshotId,
      mode: mode,
      provider: provider,
      budgetCredits: budgetCredits,
      preloadedPlanSummary: preloadedPlanSummary,
    );
  }

  @override
  Future<void> pauseCoverage() => _delegate.pauseCoverage();

  @override
  Future<void> cancelCoverage(String snapshotId) =>
      _delegate.cancelCoverage(snapshotId);

  @override
  Future<bool> tryResumeCoverage(String snapshotId) =>
      _delegate.tryResumeCoverage(snapshotId);

  @override
  Future<bool> tryRaiseBudgetAndResume({
    required String snapshotId,
    required int budgetTokens,
    required int budgetCredits,
  }) {
    return _delegate.tryRaiseBudgetAndResume(
      snapshotId: snapshotId,
      budgetTokens: budgetTokens,
      budgetCredits: budgetCredits,
    );
  }
}
