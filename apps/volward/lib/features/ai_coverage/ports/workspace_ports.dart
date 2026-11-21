import '../../../ai/ai_coverage_coordinator.dart';
import '../../../ai/ai_coverage_service.dart';
import '../../../ai/ai_provider.dart';
import '../../../ai/ai_settings_store.dart';
import '../../../ai/coverage_job_state.dart';
import '../../../ai/coverage_models.dart';

abstract interface class WorkspaceAnalyticsPort {
  Future<void> track(String name, [Map<String, Object?>? props]);
}

abstract interface class WorkspaceSettingsPort {
  Future<({int tokens, int credits})> coverageBudgetForMode(AiMode mode);

  Future<void> setCoverageBudgetTokens(int tokens);

  Future<void> setCoverageBudgetCredits(int credits);

  Future<bool> conclusionNarrativeEnabled();

  Future<bool> conclusionNarrativeAuto();

  Future<int> resolveRunBudgetCredits({
    required int estimatedCredits,
    required int accountBalance,
  });

  Future<ByokTokenUsageTotals> addByokTokenUsage({
    required int inputTokens,
    required int outputTokens,
    required int totalTokens,
    required bool estimated,
    required bool partial,
  });
}

abstract interface class WorkspaceAuthPort {
  Future<bool> hasAuthenticatedUser();
}

abstract interface class WorkspaceCandidateCachePort {
  void clearSnapshot(String snapshotId);
}

abstract interface class WorkspaceCoverageJobsPort implements AiCoverageJobs {}

final class AiWorkspacePorts {
  const AiWorkspacePorts({
    required this.analytics,
    required this.settings,
    required this.auth,
    required this.coverageJobs,
    required this.candidateCache,
  });

  factory AiWorkspacePorts.fromCoverageJobs({AiCoverageJobs? coverageJobs}) {
    return AiWorkspacePorts(
      analytics: const _NoopAnalyticsPort(),
      settings: const _NoopSettingsPort(),
      auth: const _NoopAuthPort(),
      coverageJobs: coverageJobs == null
          ? const _UnavailableCoverageJobsPort()
          : _DelegatingCoverageJobsPort(coverageJobs),
      candidateCache: const _NoopCandidateCachePort(),
    );
  }

  final WorkspaceAnalyticsPort analytics;
  final WorkspaceSettingsPort settings;
  final WorkspaceAuthPort auth;
  final WorkspaceCoverageJobsPort coverageJobs;
  final WorkspaceCandidateCachePort candidateCache;

  AiWorkspacePorts copyWith({WorkspaceCoverageJobsPort? coverageJobs}) {
    return AiWorkspacePorts(
      analytics: analytics,
      settings: settings,
      auth: auth,
      coverageJobs: coverageJobs ?? this.coverageJobs,
      candidateCache: candidateCache,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AiWorkspacePorts &&
        other.analytics == analytics &&
        other.settings == settings &&
        other.auth == auth &&
        other.coverageJobs == coverageJobs &&
        other.candidateCache == candidateCache;
  }

  @override
  int get hashCode =>
      Object.hash(analytics, settings, auth, coverageJobs, candidateCache);
}

final class _DelegatingCoverageJobsPort implements WorkspaceCoverageJobsPort {
  const _DelegatingCoverageJobsPort(this._delegate);

  final AiCoverageJobs _delegate;

  @override
  bool operator ==(Object other) =>
      other is _DelegatingCoverageJobsPort && other._delegate == _delegate;

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

final class _UnavailableCoverageJobsPort implements WorkspaceCoverageJobsPort {
  const _UnavailableCoverageJobsPort();

  Never _unavailable() =>
      throw StateError('AI workspace coverage jobs missing');

  @override
  bool get isAvailable => false;

  @override
  void addJobStateListener(void Function(CoverageJobState) listener) {}

  @override
  void removeJobStateListener(void Function(CoverageJobState) listener) {}

  @override
  Future<CoverageJobState?> loadJobState(String snapshotId) async => null;

  @override
  Future<CoveragePlanSummary?> planSummary(String snapshotId) async => null;

  @override
  void invalidatePlanSummaryCache() {}

  @override
  Future<AiCoverageService?> prepareService(AiProvider provider) async => null;

  @override
  Future<StartFullCoverageResult> startFullCoverage({
    required String snapshotId,
    required AiMode mode,
    required AiProvider provider,
    int? budgetCredits,
    CoveragePlanSummary? preloadedPlanSummary,
  }) async => _unavailable();

  @override
  Future<void> pauseCoverage() async => _unavailable();

  @override
  Future<void> cancelCoverage(String snapshotId) async => _unavailable();

  @override
  Future<bool> tryResumeCoverage(String snapshotId) async => false;

  @override
  Future<bool> tryRaiseBudgetAndResume({
    required String snapshotId,
    required int budgetTokens,
    required int budgetCredits,
  }) async => false;
}

final class _NoopAnalyticsPort implements WorkspaceAnalyticsPort {
  const _NoopAnalyticsPort();

  @override
  Future<void> track(String name, [Map<String, Object?>? props]) async {}
}

final class _NoopSettingsPort implements WorkspaceSettingsPort {
  const _NoopSettingsPort();

  @override
  Future<ByokTokenUsageTotals> addByokTokenUsage({
    required int inputTokens,
    required int outputTokens,
    required int totalTokens,
    required bool estimated,
    required bool partial,
  }) async => ByokTokenUsageTotals.empty;

  @override
  Future<bool> conclusionNarrativeAuto() async => true;

  @override
  Future<bool> conclusionNarrativeEnabled() async => false;

  @override
  Future<({int tokens, int credits})> coverageBudgetForMode(
    AiMode mode,
  ) async => (tokens: 0, credits: 0);

  @override
  Future<int> resolveRunBudgetCredits({
    required int estimatedCredits,
    required int accountBalance,
  }) async => estimatedCredits;

  @override
  Future<void> setCoverageBudgetCredits(int credits) async {}

  @override
  Future<void> setCoverageBudgetTokens(int tokens) async {}
}

final class _NoopAuthPort implements WorkspaceAuthPort {
  const _NoopAuthPort();

  @override
  Future<bool> hasAuthenticatedUser() async => false;
}

final class _NoopCandidateCachePort implements WorkspaceCandidateCachePort {
  const _NoopCandidateCachePort();

  @override
  void clearSnapshot(String snapshotId) {}
}
