import 'coverage_job_state.dart';

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
    state.clientLogicVersion < kCoverageClientLogicVersion;
