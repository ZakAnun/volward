import 'dart:async';

import '../../../ai/ai_analysis_gateway.dart';
import '../../../ai/ai_coverage_coordinator.dart';
import '../../../ai/ai_provider.dart';
import '../../../ai/ai_settings_store.dart';
import '../../../ai/coverage_job_state.dart';
import '../../../ai/coverage_verdict_store.dart';
import '../../../snapshot_cache.dart';
import '../models/ai_analysis_workspace_display_state.dart';
import '../ports/workspace_ports.dart';
import '../views/ai_analysis_workspace_messages.dart';
import 'ai_analysis_bootstrap_controller.dart';
import 'ai_analysis_coverage_controller.dart';
import 'ai_analysis_coverage_job_flow.dart';

/// Narrow bridge the page controller implements so the Coverage precheck,
/// start, privacy and auto-restore orchestration can live in this
/// context-free module.
abstract interface class AiCoverageStartFlowHost
    implements AiCoverageJobFlowHost {
  AiAnalysisGateway get gateway;
  WorkspaceSettingsPort get settings;
  AiAnalysisWorkspaceMessages get messages;
  AiAnalysisBootstrapController get bootstrap;
  AiAnalysisCoverageController get coverage;

  int? get platformCredits;
  int? get estimatedCoverageCredits;
  int? get coverageBudgetCredits;
  set coverageBudgetCredits(int? value);
  bool get runCapBelowBufferedEstimate;
  bool get hasExistingResult;
  bool get deleting;
  CoverageJobState? get debugCoverageJobState;

  void markCoverageRunEngaged();
  void enterOverviewHub();
  void setResultsViewOverview();
  Future<void> ensureUnknownCandidatesLoaded();
  Future<void> raiseConfiguredCoverageCap();
  Future<bool> loadPreviousResult({required int generation});
  Future<void> loadNarrativeSettings();
  Future<void> refreshVerdictsFromStoreWithOptions({
    required bool incremental,
    required bool allowNativeLocalBackfill,
    required bool preferReadAll,
  });
}

Future<bool> coverageEnsurePrivacyAccepted(
  AiCoverageStartFlowHost host,
  int generation,
) async {
  final accepted = await host.gateway.isPrivacyAccepted();
  if (!host.isCurrent(generation)) return false;
  if (accepted) return true;
  host.mutate(() => host.phase = AiWorkspaceDisplayState.privacy);
  if (host.disposed) return false;
  final confirmed = await host.messages.confirmPrivacy();
  if (!host.isCurrent(generation)) return false;
  if (confirmed != true) {
    host.mutate(() {
      host.phase = AiWorkspaceDisplayState.results;
      host.setResultsViewOverview();
    });
    return false;
  }
  await host.gateway.setPrivacyAccepted(true);
  return host.isCurrent(generation);
}

Future<void> coverageHydratePrecheck(
  AiCoverageStartFlowHost host, {
  required int generation,
  required AiMode mode,
  required int? platformCredits,
}) async {
  if (!host.coverageJobs.isAvailable) return;
  host.coverage.prepareHydration(
    mode: mode,
    platformCredits: platformCredits,
    planUnavailableMessage: host.messages.l10n.aiCoverageUnavailable,
  );
  await host.coverage.hydratePrecheck();
  if (!host.isCurrent(generation) || host.disposed) return;
  host.mutate(() {});
}

Future<void> coverageSyncActiveJobAfterPrecheck(
  AiCoverageStartFlowHost host,
  int generation,
) async {
  if (!host.coverageJobs.isAvailable) return;
  await host.coverage.syncActiveJobAfterPrecheck(generation);
  if (!host.isCurrent(generation) || host.disposed) return;
  host.mutate(() {});
  host.schedulePlanSummaryForBannerIfNeeded();
}

Future<CoverageJobState?> coverageLoadJobStateForRestore(
  AiCoverageStartFlowHost host,
) async {
  final cached = host.coverageController.jobState ?? host.debugCoverageJobState;
  if (cached != null && cached.snapshotId == host.snapshotId) return cached;
  return host.coverageController.loadJobState();
}

Future<bool> coverageTryAutoRestoreResults(
  AiCoverageStartFlowHost host,
  int generation,
) async {
  final state = await coverageLoadJobStateForRestore(host);
  if (!host.isCurrent(generation) || host.disposed) return false;
  final hasStoredVerdicts = await host.coverageController.verdictStoreHasRows();
  final jobSuggestsRestore =
      state != null && host.coverageController.hasRestorableProgress(state);
  if (!hasStoredVerdicts && !jobSuggestsRestore) return false;

  if (state != null && state.snapshotId == host.snapshotId) {
    host.mutate(() {
      host.coverageController.jobState = state;
      host.uiPrefersAnalyzingPhase = false;
      host.coverageController.userEngagedFullRun = false;
    });
  }
  final store = CoverageVerdictStore(SnapshotCache.cacheDir());
  final preferReadAll =
      hasStoredVerdicts && await store.fitsInlineReadBudget(host.snapshotId);
  await host.refreshVerdictsFromStoreWithOptions(
    incremental: false,
    allowNativeLocalBackfill: false,
    preferReadAll: preferReadAll,
  );
  if (!host.isCurrent(generation) || host.disposed || host.verdicts.isEmpty) {
    return false;
  }
  host.mutate(() {
    host.enterResultsPhase(showOverview: true);
    host.analyzing = false;
    host.error = null;
    host.bootstrap.markExistingResult(true);
  });
  unawaited(host.maybeRunConclusionNarrative(fresh: false));
  return true;
}

Future<void> coverageMaybeAutoRestorePreviousSession(
  AiCoverageStartFlowHost host,
  int generation,
) async {
  if (!host.isCurrent(generation) ||
      host.disposed ||
      host.phase != AiWorkspaceDisplayState.results ||
      host.analyzing ||
      host.deleting) {
    return;
  }
  if (host.verdicts.isNotEmpty) return;
  if (host.useFullCoverage && host.coverageJobs.isAvailable) {
    if (await coverageTryAutoRestoreResults(host, generation)) return;
  }
  if (host.hasExistingResult) {
    await host.loadPreviousResult(generation: generation);
  }
}

void coverageSchedulePlanSummaryForBanner(AiCoverageStartFlowHost host) {
  if (!host.useFullCoverage || host.coverageController.planSummary != null) {
    return;
  }
  if (host.coverageController.planLoadInFlight ||
      host.coverageController.planBannerLoadAttempted) {
    return;
  }
  final state = host.coverageController.jobState ?? host.debugCoverageJobState;
  if (!host.coverageController.jobStateShowsBanner(
    state,
    debug: host.debugCoverageJobState != null,
  )) {
    return;
  }
  final jobs = host.coverageJobs;
  final owner = host.coverageOwner;
  final snapshotId = host.snapshotId;
  host.coverageController.planLoadInFlight = true;
  unawaited(() async {
    try {
      await host.coverageController.ensurePlanSummaryLoaded(
        useFullCoverage: host.useFullCoverage,
      );
    } finally {
      if (!host.disposed &&
          identical(jobs, host.coverageJobs) &&
          identical(owner, host.coverageOwner) &&
          snapshotId == host.snapshotId) {
        host.mutate(() {
          host.coverageController.planLoadInFlight = false;
          host.coverageController.planBannerLoadAttempted = true;
        });
      }
    }
  }());
}

Future<void> coverageOpenLocalOnlyResults(AiCoverageStartFlowHost host) async {
  host.mutate(() {
    host.coverageController.userEngagedFullRun = true;
    host.enterResultsPhase(showOverview: true);
    host.analyzing = false;
    host.error = null;
  });
  await host.refreshVerdictsFromStore(incremental: false);
  if (!host.disposed) host.mutate(() {});
}

Future<void> coverageFinishStartFull(
  AiCoverageStartFlowHost host, {
  required int generation,
  required AiMode mode,
  required AiProvider provider,
}) async {
  final result = await host.coverage.startFullCoverage(
    mode: mode,
    provider: provider,
  );
  if (host.disposed || !host.isCurrent(generation)) return;
  if (result is StartCoverageBlocked) {
    if (result.reason == StartCoverageBlockedReason.capBelowEstimate) {
      host.mutate(() {
        host.analyzing = false;
        host.uiPrefersAnalyzingPhase = false;
        host.enterOverviewHub();
        host.error = null;
        host.coverageController.coverageCapBelowEstimate = true;
      });
      return;
    }
    if (result.reason ==
        StartCoverageBlockedReason.insufficientAccountBalance) {
      final needed = host.estimatedCoverageCredits ?? 0;
      final available = host.platformCredits ?? 0;
      host.mutate(() {
        host.analyzing = false;
        host.uiPrefersAnalyzingPhase = false;
        host.enterOverviewHub();
        host.error = host.messages.l10n.aiCoverageInsufficientForEstimate(
          needed,
          available,
        );
      });
      return;
    }
  }
  if (result is StartFullCoverageUnavailable) {
    host.mutate(() {
      host.analyzing = false;
      host.uiPrefersAnalyzingPhase = false;
      host.enterOverviewHub();
      host.error = host.messages.l10n.aiCoverageUnavailable;
    });
    return;
  }
  if (result is StartFullCoverageLocalOnly) {
    await coverageOpenLocalOnlyResults(host);
  }
}

Future<void> coverageStartFullAnalysis(AiCoverageStartFlowHost host) async {
  final generation = host.operationGeneration;
  await host.ensureUnknownCandidatesLoaded();
  if (host.disposed) return;
  if (host.runCapBelowBufferedEstimate) {
    await host.raiseConfiguredCoverageCap();
    if (host.disposed || !host.isCurrent(generation)) return;
    final budget = await host.settings.coverageBudgetForMode(
      host.bootstrap.mode,
    );
    host.mutate(() {
      host.coverageBudgetCredits = budget.credits;
      host.coverageController.coverageCapBelowEstimate =
          host.runCapBelowBufferedEstimate;
    });
    if (host.runCapBelowBufferedEstimate) return;
  }
  if (!await coverageEnsurePrivacyAccepted(host, generation)) return;
  if (!host.isCurrent(generation)) return;
  final provider = await host.gateway.resolveProvider();
  if (!host.isCurrent(generation)) return;
  if (provider == null) {
    host.bootstrap.setProviderAvailable(false);
    return;
  }
  final mode = await host.gateway.getMode();
  if (!host.isCurrent(generation)) return;
  host.mutate(() {
    host.markCoverageRunEngaged();
    host.coverageController.coverageCapBelowEstimate = false;
    host.coverageController.verdictByteOffset = 0;
    host.coverageController.verdictRows = const [];
    host.resetResultsPresentation();
    host.resultsController.reset();
    host.invalidateResultGroups();
  });
  if (!host.isCurrent(generation) || host.disposed) return;
  unawaited(
    coverageFinishStartFull(
      host,
      generation: generation,
      mode: mode,
      provider: provider,
    ),
  );
}
