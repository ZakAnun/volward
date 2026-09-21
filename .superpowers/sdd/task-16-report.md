# Task 16 Report: Resume guard + coordinator wiring

**Base:** `b964328`  
**Commit message:** `feat(flutter): coverage v3 coordinator and resume guard`

## Summary

Wired coverage v3 semantics through the coordinator and UI helpers so stale flat-plan jobs are not auto-resumed, pre-check uses tree plan credits when the tree FFI is available, and the job banner estimates remaining credits from tree + tail fields on v3 jobs.

## Changes

### `coverage_client_logic.dart`

- Extended `coverageJobNeedsClientLogicUpgrade` to block active jobs when `planVersion < kCoverageClientLogicVersion` (covers v1/v2 plans at client logic v3 even if `clientLogicVersion` was already bumped).
- Added `coveragePlanSummaryShowsV3PrecheckBreakdown`, `coveragePrecheckEstimatedCredits`, and `coverageJobEstimatedRemainingCredits` for shared pre-check and banner math.

### `ai_coverage_coordinator.dart`

- `planSummary`: uses `engine.buildTreePlan` when `VolwardSession.hasAiTreeCoverageApi`, else flat `buildPlan`.
- `startFullCoverage` (platform mode): budget cap / resolve uses `coveragePrecheckEstimatedCredits` instead of flat `estimatedPages` only.

### `coverage_job_banner.dart`

- `_estimateRemainingCredits` delegates to `coverageJobEstimatedRemainingCredits` (v3: tree + tail credits on state).

## Tests

- `ai_coverage_coordinator_hydrate_test.dart`: v2 plan + current client logic does not auto-resume; happy-path auto-resume uses `planVersion: 3`.
- `coverage_client_logic_test.dart`: plan-version guard, v3 pre-check credit sum.
- `coverage_job_banner_test.dart`: paused v3 banner shows tree+tail total (17).

## Verification

```bash
cd apps/volward && fvm flutter test \
  test/ai_coverage/coverage_client_logic_test.dart \
  test/ai_coverage/coverage_job_banner_test.dart \
  test/ai_coverage/ai_coverage_coordinator_hydrate_test.dart \
  test/ai_coverage/ai_coverage_coordinator_test.dart
```

All 22 tests passed.

## Notes

- `ai_analysis_workspace.dart` still defines duplicate pre-check helpers from Task 15; coordinator/banner now use the shared copies in `coverage_client_logic.dart`. Consolidating workspace imports is optional follow-up.
