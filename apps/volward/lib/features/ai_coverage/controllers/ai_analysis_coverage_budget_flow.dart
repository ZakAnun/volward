import 'dart:async';

import '../../../ai/ai_analysis_gateway.dart';
import '../../../ai/ai_settings_store.dart';
import '../../../ai/coverage_client_logic.dart';
import '../../../ai/coverage_job_state.dart';
import '../ports/workspace_ports.dart';
import '../views/ai_analysis_workspace_messages.dart';
import 'ai_analysis_bootstrap_controller.dart';
import 'ai_analysis_coverage_controller.dart';

/// Narrow bridge the page controller implements so the coverage budget and
/// control flows can live in a context-free module. The page stays the single
/// writer of phase and result state, but the orchestration code moves out.
abstract interface class AiCoverageBudgetFlowHost {
  AiAnalysisWorkspaceMessages get messages;
  WorkspaceSettingsPort get settings;
  AiAnalysisGateway get gateway;
  AiAnalysisBootstrapController get bootstrapController;
  AiAnalysisCoverageController get coverageController;

  int get coverageOperationGeneration;
  bool isCoverageCurrent(int generation);
  bool get coverageDisposed;
  CoverageJobState? get coverageJobState;
  AiMode get coverageMode;
  int? get estimatedCoverageCredits;
  int? get coverageBudgetCredits;
  set coverageBudgetCredits(int? value);
  bool get coverageCapBelowEstimate;
  set coverageCapBelowEstimate(bool value);

  void markCoverageRunEngaged();
  Future<void> startFullCoverageAnalysis();
}

bool coverageJobBillingModeMismatch(
  AiCoverageBudgetFlowHost host,
  CoverageJobState job,
) {
  return !coverageJobBillingMatchesMode(host.coverageMode, job);
}

String? coverageJobBillingModeMismatchBannerMessage(
  AiCoverageBudgetFlowHost host,
  CoverageJobState job,
) {
  if (!coverageJobBillingModeMismatch(host, job)) return null;
  final l10n = host.messages.l10n;
  final targetMode = switch (coverageJobBillingKind(job)) {
    CoverageJobBillingKind.tokens => l10n.aiSettingsByokLabel,
    CoverageJobBillingKind.credits => l10n.aiSettingsPlatformLabel,
    CoverageJobBillingKind.unset => l10n.aiSettingsOffLabel,
  };
  return l10n.aiCoverageJobBillingModeMismatchBanner(targetMode);
}

Future<void> coverageShowBillingModeMismatchDialog(
  AiCoverageBudgetFlowHost host,
  CoverageJobState job,
) async {
  final restart = await host.messages.confirmBillingModeMismatch(job);
  if (restart && !host.coverageDisposed) {
    unawaited(coverageRestart(host));
  }
}

Future<void> coverageResume(AiCoverageBudgetFlowHost host) async {
  final generation = host.coverageOperationGeneration;
  final state = host.coverageJobState;
  if (state != null && coverageJobNeedsClientLogicUpgrade(state)) {
    final legacyOk = await host.messages.confirmLegacyResume();
    if (legacyOk != true ||
        host.coverageDisposed ||
        !host.isCoverageCurrent(generation)) {
      return;
    }
  }
  if (state?.pauseReason == CoveragePauseReason.failed) {
    final confirmed = await host.messages.confirmFailedResume(state!);
    if (confirmed != true ||
        host.coverageDisposed ||
        !host.isCoverageCurrent(generation)) {
      return;
    }
  }
  final provider = await host.gateway.resolveProvider();
  if (!host.isCoverageCurrent(generation)) return;
  if (provider == null) {
    if (!host.coverageDisposed) {
      host.bootstrapController.setProviderAvailable(false);
    }
    return;
  }
  host.markCoverageRunEngaged();
  await host.coverageController.prepareService(provider);
  if (!host.isCoverageCurrent(generation)) return;
  final resumed = await host.coverageController.resume();
  if (!resumed &&
      !host.coverageDisposed &&
      host.isCoverageCurrent(generation)) {
    host.messages.toastCoverageBusyOtherSnapshot();
  }
}

Future<void> coverageCancel(AiCoverageBudgetFlowHost host) async {
  await host.coverageController.cancel();
}

Future<void> coverageRestart(AiCoverageBudgetFlowHost host) async {
  final generation = host.coverageOperationGeneration;
  final confirmed = await host.messages.confirmRestartFull();
  if (confirmed != true || !host.isCoverageCurrent(generation)) return;
  await host.coverageController.cancel();
  if (!host.isCoverageCurrent(generation)) return;
  host.coverageController.invalidatePlanSummaryCache();
  await host.coverageController.restart();
  await host.startFullCoverageAnalysis();
}

Future<void> coverageRaiseConfiguredCap(AiCoverageBudgetFlowHost host) async {
  final estimated = host.estimatedCoverageCredits;
  if (estimated == null) return;
  final currentLimit =
      host.coverageBudgetCredits ??
      AiSettingsStore.defaultCoverageBudgetCredits;
  final suggested = (estimated * 1.2).ceil();
  if (suggested <= currentLimit) return;
  final parsed = await host.messages.promptCoverageBudget(
    isTokenBudget: false,
    suggested: suggested,
  );
  if (parsed == null || host.coverageDisposed) return;
  if (parsed <= currentLimit) {
    if (!host.coverageDisposed) {
      host.messages.toastCoverageBudgetInvalid();
    }
    return;
  }
  await host.settings.setCoverageBudgetCredits(parsed);
  if (host.coverageDisposed) return;
  host.coverageBudgetCredits = parsed;
  host.coverageCapBelowEstimate = false;
}

Future<void> coverageRaiseBudget(
  AiCoverageBudgetFlowHost host, {
  int? suggestedCredits,
}) async {
  final generation = host.coverageOperationGeneration;
  final state = host.coverageJobState;
  if (state == null) return;
  if (coverageJobBillingModeMismatch(host, state)) {
    await coverageShowBillingModeMismatchDialog(host, state);
    return;
  }
  final isTokenBudget = state.budgetTokens > 0;
  final currentLimit = isTokenBudget ? state.budgetTokens : state.budgetCredits;
  final settings = await host.settings.coverageBudgetForMode(
    isTokenBudget ? AiMode.byok : AiMode.platform,
  );
  if (host.coverageDisposed || !host.isCoverageCurrent(generation)) return;
  final typedCreditsValid =
      suggestedCredits != null &&
      !isTokenBudget &&
      suggestedCredits > currentLimit;
  int? parsed;
  if (typedCreditsValid) {
    parsed = suggestedCredits;
  } else {
    final suggested = isTokenBudget
        ? coverageSuggestedTokenBudgetRaise(
            jobBudgetTokens: currentLimit,
            settingsBudgetTokens: settings.tokens,
          )
        : coverageSuggestedCreditBudgetRaise(
            jobBudgetCredits: currentLimit,
            settingsBudgetCredits: settings.credits,
          );
    parsed = await host.messages.promptCoverageBudget(
      isTokenBudget: isTokenBudget,
      suggested: suggested,
    );
    if (parsed == null || !host.isCoverageCurrent(generation)) return;
  }
  if (parsed <= currentLimit) {
    if (!host.coverageDisposed) {
      host.messages.toastCoverageBudgetInvalid();
    }
    return;
  }
  if (isTokenBudget) {
    await host.settings.setCoverageBudgetTokens(parsed);
  } else {
    await host.settings.setCoverageBudgetCredits(parsed);
  }
  if (!host.isCoverageCurrent(generation)) return;
  final provider = await host.gateway.resolveProvider();
  if (!host.isCoverageCurrent(generation)) return;
  if (provider == null) {
    if (!host.coverageDisposed) {
      host.bootstrapController.setProviderAvailable(false);
    }
    return;
  }
  if (!host.coverageDisposed) host.markCoverageRunEngaged();
  await host.coverageController.prepareService(provider);
  if (!host.isCoverageCurrent(generation)) return;
  final bool raised;
  if (isTokenBudget) {
    raised = await host.coverageController.raiseBudgetAndResume(
      budgetTokens: parsed,
      budgetCredits: 0,
    );
  } else {
    await host.coverageController.raiseBudget(parsed);
    raised = host.coverageController.lastRaiseBudgetSucceeded ?? false;
  }
  if (!raised && !host.coverageDisposed && host.isCoverageCurrent(generation)) {
    host.messages.toastCoverageBusyOtherSnapshot();
  }
}
