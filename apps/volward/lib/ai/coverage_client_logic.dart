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

int? coveragePrecheckEstimatedCredits(CoveragePlanSummary? summary) {
  if (summary == null) return null;
  if (coveragePlanSummaryShowsV3PrecheckBreakdown(summary)) {
    return summary.estimatedTreeCredits! + summary.estimatedTailCredits!;
  }
  return summary.estimatedPages;
}

int coverageJobEstimatedRemainingCredits(CoverageJobState state) {
  if (state.planVersion >= 3 &&
      state.estimatedTreeCredits != null &&
      state.estimatedTailCredits != null) {
    return state.estimatedTreeCredits! + state.estimatedTailCredits!;
  }
  if (state.planVersion >= 2 && state.estimatedCreditsRemaining != null) {
    return state.estimatedCreditsRemaining!;
  }
  final pending = max(0, state.totalUnclassified - state.analyzedFiles);
  return (pending / 40).ceil();
}
