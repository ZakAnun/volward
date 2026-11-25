import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../ai/ai_analysis_gateway.dart';
import '../../../ai/ai_provider.dart';
import '../../../ai/ai_coverage_coordinator.dart';
import '../../../ai/coverage_client_logic.dart';
import '../../../ai/coverage_job_state.dart';
import '../../../ai/coverage_verdict_adapter.dart';
import '../../../ai/coverage_verdict_store.dart';
import '../../../widgets/ai_results_hub.dart';
import '../models/ai_analysis_workspace_display_state.dart';
import '../views/ai_analysis_workspace_presenter.dart';
import '../views/ai_analysis_workspace_view_state.dart';
import 'ai_analysis_bootstrap_controller.dart';
import 'ai_analysis_coverage_controller.dart';
import 'ai_analysis_coverage_flow.dart';
import 'ai_analysis_results_controller.dart';
import 'ai_analysis_workspace_result_helpers.dart';

/// Narrow bridge the page controller implements so the Coverage job-state and
/// verdict-row flows live in this context-free module. The page remains the
/// single writer of phase/result state, but the orchestration bodies no
/// longer live in the page controller file.
abstract interface class AiCoverageJobFlowHost {
  String get snapshotId;
  Object? get coverageOwner;
  AiCoverageJobs get coverageJobs;
  AiAnalysisCoverageController get coverageController;
  AiAnalysisResultsController get resultsController;
  AiAnalysisBootstrapController get bootstrapController;
  AiAnalysisWorkspacePresenter? get presenter;

  bool get disposed;
  int get operationGeneration;
  bool isCurrent(int generation);

  AiWorkspaceDisplayState get phase;
  set phase(AiWorkspaceDisplayState value);
  bool get analyzing;
  set analyzing(bool value);
  String? get error;
  set error(String? value);
  bool get useFullCoverage;
  bool get uiPrefersAnalyzingPhase;
  set uiPrefersAnalyzingPhase(bool value);
  bool get userEngagedFullRun;
  int? get stalePausedUpdatedAtMs;
  set stalePausedUpdatedAtMs(int? value);
  bool get pauseInFlight;
  set pauseInFlight(bool value);
  bool get deferCoverageJobUiForScroll;
  set deferCoverageJobUiForScroll(bool value);
  int get resultsLayoutGeneration;
  set resultsLayoutGeneration(int value);
  bool get resultsUserScrolling;
  set resultsUserScrolling(bool value);
  bool get resultsLayoutPending;
  set resultsLayoutPending(bool value);
  Timer? get jobStateCoalesceTimer;
  set jobStateCoalesceTimer(Timer? value);
  List<CoverageVerdict>? get pendingVerdictRowsAfterScroll;
  set pendingVerdictRowsAfterScroll(List<CoverageVerdict>? value);
  bool get pendingVerdictRowsPreserveUi;
  set pendingVerdictRowsPreserveUi(bool value);
  List<AiVerdict> get verdicts;
  Set<String> get selected;
  Map<String, WorkspaceReviewDecision> get reviewDecisions;
  Set<String> get expandedGroupPaths;
  Set<String> get expandedReviewPaths;
  String get resultsQuery;
  WorkspaceResultFilter get resultFilter;
  WorkspaceResultSort get resultSort;
  Map<String, int> get sizeByPath;

  bool get lightweightAnalyzingUi;
  ResultsHubMode get resultsHubMode;
  int get displayPreClassifiedCount;
  int get verdictPageCount;
  String? failedReasonForState(CoverageJobState state);
  Set<String> defaultExpandedGroupPaths();

  void mutate(VoidCallback update);
  void enterResultsPhase({required bool showOverview});
  void bumpVerdictPagesForTerminal(CoverageJobState state);
  void schedulePlanSummaryForBannerIfNeeded();
  void invalidateResultGroups();
  void invalidateVisibleGroups();
  void resetResultsPresentation();
  void syncSelectedToKnownPaths();
  void queueVerdictRowsUntilScrollIdle(
    List<CoverageVerdict> rows, {
    required bool preserveUiState,
  });
  Future<void> applyHeavyResultsPresentation({
    required List<AiVerdict> verdicts,
    required bool preserveUiState,
  });
  Future<void> refreshVerdictsFromStore({required bool incremental});
  Future<void> maybeRunConclusionNarrative({required bool fresh});
  AiWorkspaceCoverage get coverageAccess;
}

const _coverageVerdictRefreshMinInterval = Duration(milliseconds: 350);
const _heavyResultsLayoutThreshold = 200;

void coverageJobOnState(AiCoverageJobFlowHost host, CoverageJobState state) {
  if (state.snapshotId != host.snapshotId || host.disposed) return;
  host.coverageController.pendingJobState = state;
  final terminal = aiCoverageJobStateIsTerminal(state);
  if (terminal) {
    host.jobStateCoalesceTimer?.cancel();
    host.jobStateCoalesceTimer = null;
    unawaited(coverageJobApplyState(host, state));
    return;
  }
  host.jobStateCoalesceTimer?.cancel();
  host.jobStateCoalesceTimer = Timer(
    Duration(milliseconds: _coalesceDelayMs(host, state)),
    () {
      host.jobStateCoalesceTimer = null;
      if (host.deferCoverageJobUiForScroll) return;
      final pending = host.coverageController.pendingJobState;
      if (pending == null || host.disposed) return;
      unawaited(coverageJobApplyState(host, pending));
    },
  );
}

int _coalesceDelayMs(AiCoverageJobFlowHost host, CoverageJobState state) {
  if (aiCoverageJobStateIsTerminal(state)) return 0;
  if (host.lightweightAnalyzingUi) return 1000;
  if (host.phase == AiWorkspaceDisplayState.analyzing &&
      host.uiPrefersAnalyzingPhase &&
      state.status == CoverageJobStatus.running) {
    return 1000;
  }
  return 150;
}

Future<void> coverageJobApplyState(
  AiCoverageJobFlowHost host,
  CoverageJobState state,
) async {
  if (state.snapshotId != host.snapshotId) return;
  final jobs = host.coverageJobs;
  final owner = host.coverageOwner;
  if (host.deferCoverageJobUiForScroll) {
    host.coverageController.pendingJobState = state;
    if (aiCoverageJobStateIsTerminal(state)) {
      coverageJobPaintState(host, state);
    }
    return;
  }
  // Persisted jobs surface on precheck as the banner only until the user
  // explicitly starts or resumes full coverage this visit.
  if (host.resultsHubMode != ResultsHubMode.ready &&
      !host.analyzing &&
      !host.userEngagedFullRun &&
      host.verdicts.isEmpty) {
    if (host.disposed) return;
    final terminal = aiCoverageJobStateIsTerminal(state);
    host.mutate(() {
      host.coverageController.jobState = state;
      if (terminal) host.pauseInFlight = false;
    });
    host.schedulePlanSummaryForBannerIfNeeded();
    return;
  }
  if (coverageIgnoreStalePausedJobState(
    state: state,
    stalePausedUpdatedAtMs: host.stalePausedUpdatedAtMs,
  )) {
    // An explicit Pause tap after Resume produces a fresh paused emit that
    // may share the pre-resume timestamp; do not drop it or the optimistic
    // pausing UI would be stuck until the pause future rolls it back.
    if (!host.pauseInFlight) return;
    host.stalePausedUpdatedAtMs = null;
  }
  if (state.status == CoverageJobStatus.running) {
    host.stalePausedUpdatedAtMs = null;
  } else if (state.status == CoverageJobStatus.paused &&
      host.stalePausedUpdatedAtMs != null &&
      state.updatedAtMs != host.stalePausedUpdatedAtMs) {
    host.stalePausedUpdatedAtMs = null;
  }
  final incremental =
      host.coverageController.verdictByteOffset > 0 && host.verdicts.isNotEmpty;
  final terminal = aiCoverageJobStateIsTerminal(state);
  if (terminal) {
    host.uiPrefersAnalyzingPhase = false;
    if (!host.disposed) {
      coverageJobPaintState(host, state);
    }
  }
  final lightweightAnalyzing =
      host.useFullCoverage &&
      host.uiPrefersAnalyzingPhase &&
      host.phase == AiWorkspaceDisplayState.analyzing &&
      state.status == CoverageJobStatus.running;
  var shouldRefreshVerdicts =
      !lightweightAnalyzing &&
      (state.analyzedFiles > 0 || state.status == CoverageJobStatus.completed);
  if (shouldRefreshVerdicts) {
    final now = DateTime.now();
    final running = state.status == CoverageJobStatus.running;
    final rows = host.coverageController.verdictRows;
    final heavy =
        rows.length >= _heavyResultsLayoutThreshold ||
        state.analyzedFiles >= _heavyResultsLayoutThreshold;
    final minInterval = running && heavy
        ? const Duration(seconds: 4)
        : _coverageVerdictRefreshMinInterval;
    final lastRefresh = host.coverageController.lastVerdictRefreshAt;
    final dueByTime =
        lastRefresh == null || now.difference(lastRefresh) >= minInterval;
    final allowRefresh = terminal || (dueByTime && (!running || incremental));
    if (allowRefresh) {
      // Terminal transitions (completed/paused): paint job state first so
      // progress does not freeze while reading jsonl / heavy results layout.
      if (terminal) {
        host.bumpVerdictPagesForTerminal(state);
        final inc = incremental;
        final freshCompleted =
            state.status == CoverageJobStatus.completed &&
            host.userEngagedFullRun;
        unawaited(() async {
          await host.refreshVerdictsFromStore(incremental: inc);
          if (!host.disposed &&
              identical(jobs, host.coverageJobs) &&
              identical(owner, host.coverageOwner) &&
              state.snapshotId == host.snapshotId) {
            host.coverageController.lastVerdictRefreshAt = DateTime.now();
            unawaited(host.maybeRunConclusionNarrative(fresh: freshCompleted));
          }
        }());
      } else {
        await host.refreshVerdictsFromStore(incremental: incremental);
        if (host.disposed ||
            !identical(jobs, host.coverageJobs) ||
            !identical(owner, host.coverageOwner) ||
            state.snapshotId != host.snapshotId) {
          return;
        }
        host.coverageController.lastVerdictRefreshAt = now;
      }
    }
  }
  if (host.disposed) return;
  if (terminal) {
    host.schedulePlanSummaryForBannerIfNeeded();
    return;
  }
  final showResults =
      state.status == CoverageJobStatus.paused ||
      state.status == CoverageJobStatus.completed ||
      (!host.uiPrefersAnalyzingPhase &&
          ((state.status == CoverageJobStatus.running &&
                  state.analyzedFiles > 0) ||
              host.verdicts.isNotEmpty));
  host.mutate(() {
    host.coverageController.jobState = state;
    host.analyzing = state.status == CoverageJobStatus.running;
    if (showResults) {
      host.enterResultsPhase(
        showOverview:
            host.phase != AiWorkspaceDisplayState.results &&
            host.phase != AiWorkspaceDisplayState.deleting,
      );
    } else if (state.status == CoverageJobStatus.running) {
      host.phase = AiWorkspaceDisplayState.analyzing;
    }
    if (state.pauseReason == CoveragePauseReason.failed) {
      host.error = host.failedReasonForState(state);
    } else if (state.status != CoverageJobStatus.paused) {
      host.error = null;
    }
  });
  host.schedulePlanSummaryForBannerIfNeeded();
}

void coverageJobPaintState(AiCoverageJobFlowHost host, CoverageJobState state) {
  if (host.disposed) return;
  // Same state object already painted (e.g. terminal painted while scroll
  // was deferred, then flushed after scroll) — avoid a duplicate setState.
  if (identical(host.coverageController.jobState, state) &&
      !host.pauseInFlight) {
    return;
  }
  final showResults =
      state.status == CoverageJobStatus.paused ||
      state.status == CoverageJobStatus.completed ||
      (!host.uiPrefersAnalyzingPhase &&
          ((state.status == CoverageJobStatus.running &&
                  state.analyzedFiles > 0) ||
              host.verdicts.isNotEmpty));
  host.mutate(() {
    host.coverageController.jobState = state;
    host.pauseInFlight = false;
    host.analyzing = state.status == CoverageJobStatus.running;
    if (showResults) {
      host.enterResultsPhase(
        showOverview:
            host.phase != AiWorkspaceDisplayState.results &&
            host.phase != AiWorkspaceDisplayState.deleting,
      );
    } else if (state.status == CoverageJobStatus.running) {
      host.phase = AiWorkspaceDisplayState.analyzing;
    }
    if (state.pauseReason == CoveragePauseReason.failed) {
      host.error = host.failedReasonForState(state);
    } else if (state.status != CoverageJobStatus.paused) {
      host.error = null;
    }
  });
}

Future<void> coverageJobApplyVerdictRows(
  AiCoverageJobFlowHost host,
  List<CoverageVerdict> coverageVerdicts, {
  bool preserveUiState = false,
}) async {
  if (host.lightweightAnalyzingUi) return;
  host.resultsLayoutGeneration++;
  host.pendingVerdictRowsAfterScroll = null;
  final savedPresentation = preserveUiState
      ? (
          query: host.resultsQuery,
          filter: host.resultFilter,
          sort: host.resultSort,
        )
      : null;
  final verdicts = coverageVerdictsToAiVerdicts(coverageVerdicts)
      .map(
        (verdict) =>
            withCandidateMeta(verdict, host.bootstrapController.unknownByPath),
      )
      .toList();
  host.bootstrapController.addSizes({
    for (final verdict in coverageVerdicts)
      if (verdict.sizeBytes > 0) verdict.path: verdict.sizeBytes,
  });
  if (verdicts.length >= _heavyResultsLayoutThreshold) {
    if (!host.disposed) {
      host.mutate(() {
        host.coverageController.verdictRows = coverageVerdicts;
        if (preserveUiState && savedPresentation != null) {
          host.resultsController.setQuery(savedPresentation.query);
          host.resultsController.setFilter(savedPresentation.filter);
          host.resultsController.setSort(savedPresentation.sort);
          host.invalidateVisibleGroups();
        } else {
          host.resetResultsPresentation();
        }
      });
    }
    await host.applyHeavyResultsPresentation(
      verdicts: verdicts,
      preserveUiState: preserveUiState,
    );
    return;
  }
  final savedReview = preserveUiState
      ? Map<String, WorkspaceReviewDecision>.from(host.reviewDecisions)
      : null;
  final savedSelected = preserveUiState
      ? Set<String>.from(host.selected)
      : null;
  final savedExpandedGroups = preserveUiState
      ? Set<String>.from(host.expandedGroupPaths)
      : null;
  final savedExpandedReviews = preserveUiState
      ? Set<String>.from(host.expandedReviewPaths)
      : null;
  if (host.disposed) return;
  host.mutate(() {
    host.coverageController.verdictRows = coverageVerdicts;
    if (preserveUiState && savedPresentation != null) {
      host.resultsController.setQuery(savedPresentation.query);
      host.resultsController.setFilter(savedPresentation.filter);
      host.resultsController.setSort(savedPresentation.sort);
    } else {
      host.resetResultsPresentation();
    }
    host.invalidateResultGroups();
    final review = <String, WorkspaceReviewDecision>{};
    if (preserveUiState && savedReview != null) {
      review.addAll(savedReview);
      for (final verdict in verdicts) {
        if (verdict.verdict == 'review_needed' &&
            !review.containsKey(verdict.path)) {
          review[verdict.path] = WorkspaceReviewDecision.pending;
        }
      }
    } else {
      for (final verdict in verdicts) {
        if (verdict.verdict == 'review_needed') {
          review[verdict.path] = WorkspaceReviewDecision.pending;
        }
      }
    }
    final selectedPaths = preserveUiState && savedSelected != null
        ? savedSelected
        : selectedPathsForResults(
            verdicts: verdicts,
            preClassified: host.bootstrapController.preClassified,
            reviewDecisions: review,
          );
    final expandedGroups = preserveUiState && savedExpandedGroups != null
        ? savedExpandedGroups
        : host.defaultExpandedGroupPaths();
    final expandedReviews = preserveUiState && savedExpandedReviews != null
        ? savedExpandedReviews
        : const <String>{};
    host.resultsController.applyVerdicts(
      verdicts,
      selectedPaths: selectedPaths,
      reviewDecisions: review,
      expandedGroupPaths: expandedGroups,
      expandedReviewPaths: expandedReviews,
    );
    if (preserveUiState && savedSelected != null) {
      host.syncSelectedToKnownPaths();
    }
    host.bootstrapController.markExistingResult(verdicts.isNotEmpty);
    host.resultsLayoutPending = false;
  });
}

Future<void> coverageJobLoadNextPage(AiCoverageJobFlowHost host) async {
  final generation = host.operationGeneration;
  final previousRows = host.coverageController.verdictRows;
  await host.coverageController.loadMoreVerdicts();
  if (!host.isCurrent(generation) || host.disposed) return;
  final rows = host.coverageController.verdictRows;
  if (identical(rows, previousRows)) return;
  if (host.resultsUserScrolling) {
    host.queueVerdictRowsUntilScrollIdle(rows, preserveUiState: true);
    return;
  }
  host.mutate(() {});
  unawaited(coverageJobApplyVerdictRows(host, rows, preserveUiState: true));
}

void coverageJobMaybeLoadMore(
  AiCoverageJobFlowHost host, {
  double? pixels,
  double? maxScrollExtent,
}) {
  if (host.lightweightAnalyzingUi) return;
  if (!host.useFullCoverage || pixels == null || maxScrollExtent == null) {
    return;
  }
  if (maxScrollExtent <= 0) return;
  if (pixels < maxScrollExtent - 240) return;
  if (host.coverageController.verdictRows.length <
      host.verdictPageCount * AiAnalysisCoverageController.verdictPageSize) {
    return;
  }
  unawaited(coverageJobLoadNextPage(host));
}
