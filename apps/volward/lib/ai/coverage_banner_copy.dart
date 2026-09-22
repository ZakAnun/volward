import '../l10n/generated/app_localizations.dart';
import 'coverage_client_logic.dart';
import 'coverage_job_state.dart';
import 'coverage_models.dart';

class CoverageBannerCopy {
  const CoverageBannerCopy({
    required this.progressLine,
    this.funnelLine,
    this.apiCallsLine,
    this.pausedNoticeLine,
    this.sourceStatsLine,
    required this.showCreditRemaining,
    required this.remainingApiCalls,
  });

  final String progressLine;
  final String? funnelLine;
  final String? apiCallsLine;
  final String? pausedNoticeLine;
  final String? sourceStatsLine;
  final bool showCreditRemaining;
  final int remainingApiCalls;
}

bool coveragePlanHasFunnelBreakdown(CoveragePlanSummary? plan) {
  if (plan == null || plan.planVersion < 3) return false;
  return plan.localSafeFiles != null &&
      plan.localKeepFiles != null &&
      plan.treePendingFiles != null &&
      (plan.tailFiles != null || plan.tailFileCount != null);
}

CoverageBannerCopy buildCoverageBannerCopy({
  required CoverageJobState state,
  CoveragePlanSummary? plan,
  required AppLocalizations l10n,
  bool showPausedBeforeProgressNotice = false,
  CoverageSourceStatsInput? sourceStats,
}) {
  final progressLine = l10n.aiCoverageProgress(
    state.analyzedFiles,
    state.totalUnclassified,
  );

  String? funnelLine;
  if (coveragePlanHasFunnelBreakdown(plan)) {
    final tail = plan!.tailFiles ?? plan.tailFileCount ?? 0;
    funnelLine = l10n.aiCoverageFunnelBreakdown(
      plan.localSafeFiles!,
      plan.localKeepFiles!,
      plan.treePendingFiles!,
      tail,
    );
  }

  final minApiCalls = coverageJobMinApiCalls(state);
  final remainingApiCalls = coverageJobEstimatedRemainingApiCalls(state);
  final showApiEstimate =
      state.status == CoverageJobStatus.running ||
      state.status == CoverageJobStatus.paused;
  final String? apiCallsLine = showApiEstimate && minApiCalls > 0
      ? l10n.aiCoverageApiCallsEstimate(
          state.usedCredits,
          minApiCalls,
          remainingApiCalls,
        )
      : null;

  final showCreditRemaining =
      apiCallsLine == null &&
      state.status == CoverageJobStatus.paused &&
      coverageJobUsesCreditBilling(state) &&
      remainingApiCalls > 0;

  String? pausedNoticeLine;
  if (showPausedBeforeProgressNotice &&
      state.status == CoverageJobStatus.paused &&
      state.analyzedFiles == 0) {
    pausedNoticeLine = l10n.aiCoveragePausedBeforeProgress;
  }

  String? sourceStatsLine;
  if (sourceStats != null && !sourceStats.isEmpty) {
    sourceStatsLine = l10n.aiCoverageSourceStats(
      sourceStats.fileVerdicts,
      sourceStats.groupVerdicts,
      sourceStats.localPreClassified,
    );
  }

  return CoverageBannerCopy(
    progressLine: progressLine,
    funnelLine: funnelLine,
    apiCallsLine: apiCallsLine,
    pausedNoticeLine: pausedNoticeLine,
    sourceStatsLine: sourceStatsLine,
    showCreditRemaining: showCreditRemaining,
    remainingApiCalls: remainingApiCalls,
  );
}

/// Lightweight view of [computeCoverageSourceStats] for banner copy.
class CoverageSourceStatsInput {
  const CoverageSourceStatsInput({
    required this.fileVerdicts,
    required this.groupVerdicts,
    required this.localPreClassified,
  });

  final int fileVerdicts;
  final int groupVerdicts;
  final int localPreClassified;

  bool get isEmpty =>
      fileVerdicts == 0 && groupVerdicts == 0 && localPreClassified == 0;
}
