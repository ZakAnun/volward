import 'dart:math';

import 'coverage_job_state.dart';
import 'coverage_models.dart';

/// Bumped when client-side batch mapping / pause-resume semantics change.
///
/// v1 (implicit): missing path in API response could hard-fail the batch.
/// v2: synthesize `review_needed` for missing paths; persist failed-batch context.
/// v3: tree-plan BFS queue cursors and local resolution progress in job state.
const kCoverageClientLogicVersion = 3;

bool coverageJobIsActive(CoverageJobState state) =>
    state.status == CoverageJobStatus.running ||
    state.status == CoverageJobStatus.paused;

/// Saved job was interrupted under older client logic; user should confirm Resume or Restart.
bool coverageJobNeedsClientLogicUpgrade(CoverageJobState state) =>
    coverageJobIsActive(state) &&
    (state.clientLogicVersion < kCoverageClientLogicVersion ||
        state.planVersion < kCoverageClientLogicVersion);

bool coveragePlanSummaryShowsV3PrecheckBreakdown(CoveragePlanSummary? summary) {
  if (summary == null || summary.planVersion < 3) {
    return false;
  }
  return summary.localSafeFiles != null &&
      summary.localKeepFiles != null &&
      summary.estimatedTreeCredits != null &&
      summary.estimatedTailCredits != null;
}

/// File count for coverage progress (v3 funnel totals when plan omits the field).
int coveragePlanTotalUnclassified(CoveragePlanSummary summary) {
  if (summary.totalUnclassified > 0) {
    return summary.totalUnclassified;
  }
  if (summary.planVersion < 3) return summary.totalUnclassified;
  final localSafe = summary.localSafeFiles ?? 0;
  final localKeep = summary.localKeepFiles ?? 0;
  final tail = summary.tailFiles ?? summary.tailFileCount ?? 0;
  final treePending = summary.treePendingFiles ?? 0;
  return localSafe + localKeep + tail + treePending;
}

int? coveragePrecheckEstimatedCredits(CoveragePlanSummary? summary) {
  if (summary == null) return null;
  if (coveragePlanSummaryShowsV3PrecheckBreakdown(summary)) {
    return coveragePlanMinApiCalls(summary);
  }
  return summary.estimatedPages;
}

int coveragePlanMinApiCalls(CoveragePlanSummary summary) {
  if (summary.planVersion >= 3 &&
      summary.estimatedTreeCredits != null &&
      summary.estimatedTailCredits != null) {
    return summary.estimatedTreeCredits! + summary.estimatedTailCredits!;
  }
  return coveragePrecheckEstimatedCredits(summary) ?? summary.estimatedPages;
}

bool coveragePlanRequiresApi(CoveragePlanSummary summary) =>
    coveragePlanMinApiCalls(summary) > 0;

int coverageJobMinApiCalls(CoverageJobState state) {
  if (state.planVersion >= 3 &&
      state.estimatedTreeCredits != null &&
      state.estimatedTailCredits != null) {
    return state.estimatedTreeCredits! + state.estimatedTailCredits!;
  }
  return state.estimatedCreditsRemaining ?? 0;
}

int coverageJobEstimatedRemainingApiCalls(CoverageJobState state) {
  if (state.planVersion >= 3 &&
      state.estimatedTreeCredits != null &&
      state.estimatedTailCredits != null) {
    return max(0, coverageJobMinApiCalls(state) - state.usedCredits);
  }
  if (state.planVersion >= 2 && state.estimatedCreditsRemaining != null) {
    return max(0, state.estimatedCreditsRemaining! - state.usedCredits);
  }
  final pending = max(0, state.totalUnclassified - state.analyzedFiles);
  final legacyEstimate = (pending / 40).ceil();
  return max(0, legacyEstimate - state.usedCredits);
}

bool coverageJobUsesCreditBilling(CoverageJobState state) =>
    state.budgetCredits > 0;

int coverageJobEstimatedRemainingCredits(CoverageJobState state) =>
    coverageJobEstimatedRemainingApiCalls(state);
