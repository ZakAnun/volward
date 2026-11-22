import 'package:flutter/material.dart';

import '../../../ai/ai_analysis_activity_model.dart';
import '../../../ai/ai_settings_store.dart';
import '../../../ai/coverage_job_state.dart';
import '../../../ai/coverage_pause_messages.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../theme/apple_tokens.dart';
import '../../../theme/volward_tokens.dart';
import '../../../widgets/ai_analysis_scope_panel.dart';
import '../../../widgets/apple_widgets.dart';
import '../ai_analysis_workspace_keys.dart';
import '../models/ai_analysis_workspace_display_state.dart';
import '../widgets/analysis_results_view.dart';
import 'ai_analysis_activity_view.dart';
import 'ai_analysis_coverage_banner_view.dart';
import 'ai_analysis_detail_list_view.dart';
import 'ai_analysis_overview_view.dart';
import 'ai_analysis_review_item_view.dart';
import 'ai_analysis_results_view.dart';
import 'ai_analysis_scope_panel_view.dart';
import 'ai_analysis_workspace_view_actions.dart';
import 'ai_analysis_workspace_view_state.dart';

/// Renders the AI workspace body from immutable state and typed actions.
///
/// This view owns all `BuildContext` use and the remaining shell chrome. It
/// composes the already-extracted section views and never touches the page
/// controller.
class AiAnalysisWorkspaceBodyView extends StatelessWidget {
  const AiAnalysisWorkspaceBodyView({
    super.key,
    required this.state,
    required this.actions,
    required this.onOpenSettings,
    required this.scrollController,
    required this.searchController,
  });

  final AiAnalysisWorkspaceViewState state;
  final AiAnalysisWorkspaceViewActions actions;
  final VoidCallback onOpenSettings;
  final ScrollController scrollController;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    return switch (state.overview.displayState) {
      AiWorkspaceDisplayState.loading => _buildActivityListView(),
      AiWorkspaceDisplayState.error => _buildError(context),
      AiWorkspaceDisplayState.analyzing ||
      AiWorkspaceDisplayState.results ||
      AiWorkspaceDisplayState.deleting => _wrapScrollHoldForRebuild(
        _buildResultsSurface(),
      ),
      AiWorkspaceDisplayState.precheck ||
      AiWorkspaceDisplayState.privacy => _buildResultsSurface(),
    };
  }

  Widget _wrapScrollHoldForRebuild(Widget child) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          actions.notifyResultsScrollStart();
        } else if (notification is ScrollEndNotification) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            actions.notifyResultsScrollEnd(
              pixels: notification.metrics.pixels,
              maxScrollExtent: notification.metrics.maxScrollExtent,
            );
          });
        }
        return false;
      },
      child: child,
    );
  }

  Widget _buildActivityListView() {
    return ListView(
      padding: const EdgeInsets.all(AppleSpacing.lg),
      children: [
        if (_coverageBanner case final banner?) ...[
          banner,
          const SizedBox(height: AppleSpacing.lg),
        ],
        AiAnalysisActivityView(activity: state.activity),
      ],
    );
  }

  Widget? get _coverageBanner {
    final banner = state.coverageBanner;
    if (banner == null) return null;
    return AiAnalysisCoverageBannerView(
      state: banner,
      onPause: () => actions.pauseCoverage(),
      onResume: () => actions.resumeCoverage(),
      onCancel: () => actions.cancelCoverage(),
      onRaiseBudget: () => actions.raiseCoverageBudget(0),
      onRestart: () => actions.restartCoverage(),
    );
  }

  Widget _buildResultsActivityPlaceholder() {
    return ListView(
      padding: const EdgeInsets.all(AppleSpacing.lg),
      children: [
        AiAnalysisActivityView(
          activity: state.activity,
          macroPhase: AiActivityMacroPhase.resultsBusy,
        ),
      ],
    );
  }

  Widget _buildActivityCompactCard() {
    return AiAnalysisActivityView(
      compact: true,
      activity: state.activity,
      macroPhase: AiActivityMacroPhase.resultsBusy,
    );
  }

  String _resultsScopeSummaryLine(AppLocalizations l10n) {
    final precheck = state.precheck;
    if (precheck.candidatesBootstrapPending) {
      return l10n.aiCandidatesBootstrapLoading;
    }
    var localDeletable = 0;
    for (final entry in precheck.preClassified) {
      if (entry['deletable'] == true) localDeletable++;
    }
    final line = l10n.aiResultsScopeSummaryLine(
      precheck.displayUnknownCount,
      localDeletable,
    );
    if (state.coverage.useFullCoverage) {
      return '$line · ${l10n.aiConclusionsModeFull}';
    }
    return line;
  }

  bool _embeddedScopeExpanded() {
    final manual = state.overview.scopeExpandedManual;
    if (manual != null) return manual;
    final precheck = state.precheck;
    final needsSettings =
        !precheck.hasProvider ||
        (precheck.mode == AiMode.platform && precheck.platformCredits == 0);
    return needsSettings || precheck.error != null;
  }

  Widget _buildScopePanelExpandedBody({bool includeCoverageBanner = true}) {
    return AiAnalysisScopePanelView(
      precheck: state.precheck,
      coverage: state.coverage,
      actions: actions,
      onOpenSettings: onOpenSettings,
      banner: includeCoverageBanner ? state.coverageBanner : null,
      onPause: () => actions.pauseCoverage(),
      onResume: () => actions.resumeCoverage(),
      onCancel: () => actions.cancelCoverage(),
      onRaiseBudget: () => actions.raiseCoverageBudget(0),
      onRestart: () => actions.restartCoverage(),
    );
  }

  Widget _buildResultsSurface() {
    final deleting = state.delete.busy;
    final resultsView = state.overview.resultsView;
    if (deleting && resultsView != WorkspaceResultsView.overview) {
      return AnalysisResultsView(
        body: KeyedSubtree(
          key: AiAnalysisWorkspaceKeys.detailListKey,
          child: _buildDetailList(),
        ),
      );
    }
    return AnalysisResultsView(
      body: switch (resultsView) {
        WorkspaceResultsView.overview => _buildResultsOverview(),
        WorkspaceResultsView.reviewQueue => _buildReviewQueue(),
        WorkspaceResultsView.detailList => KeyedSubtree(
          key: AiAnalysisWorkspaceKeys.detailListKey,
          child: _buildDetailList(),
        ),
      },
    );
  }

  Widget _buildResultsOverview() {
    final overview = state.results.overview;
    final hasVerdicts = state.results.verdicts.isNotEmpty;
    final showCompactActivity = state.activity.showCompact;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final horizontalPadding = wide ? AppleSpacing.lg : AppleSpacing.md;
        final l10n = context.l10n;
        return Column(
          key: AiAnalysisWorkspaceKeys.conclusionsOverviewKey,
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppleSpacing.md,
                      horizontalPadding,
                      AppleSpacing.lg,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AiAnalysisScopeSummaryRow(
                            key: AiAnalysisWorkspaceKeys.resultsScopePanelKey,
                            summaryLine: _resultsScopeSummaryLine(l10n),
                            expanded: _embeddedScopeExpanded(),
                            onToggle: actions.toggleScopeExpanded,
                          ),
                          if (_embeddedScopeExpanded()) ...[
                            const SizedBox(height: AppleSpacing.sm),
                            _buildScopePanelExpandedBody(
                              includeCoverageBanner: false,
                            ),
                          ],
                          if (showCompactActivity) ...[
                            const SizedBox(height: AppleSpacing.sm),
                            _buildActivityCompactCard(),
                          ],
                          if (_coverageBanner case final banner?) ...[
                            const SizedBox(height: AppleSpacing.sm),
                            banner,
                          ],
                          AiAnalysisOverviewView(
                            state: state,
                            hasVerdicts: hasVerdicts,
                            safeCount: _conclusionSafeItemCount(),
                            analyzing: state.overview.analyzing,
                            canGenerateNarrative: state.precheck.hasProvider,
                            showNarrativeCreditHint:
                                state.precheck.mode == AiMode.platform,
                            emptyState: _buildResultsEmptyState(
                              context,
                              filtered: false,
                            ),
                            onOpenDetailList: (filter, {directoryPath}) =>
                                actions.openDetailList(
                                  initialFilter: filter,
                                  directoryPath: directoryPath,
                                ),
                            onOpenReviewQueue: actions.openReviewQueue,
                            onDirectoryTypeFilterChanged:
                                actions.setDirectoryTypeFilter,
                            onGenerateNarrative: actions.generateNarrative,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!state.overview.analyzing)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  AppleSpacing.sm,
                  horizontalPadding,
                  AppleSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!hasVerdicts) ...[
                      if (state.results.hasExistingResult) ...[
                        AppleButton(
                          key: AiAnalysisWorkspaceKeys.loadPreviousKey,
                          label: l10n.aiWorkspaceLoadPrevious,
                          variant: AppleButtonVariant.secondary,
                          expanded: true,
                          onPressed: actions.loadPreviousResult,
                        ),
                        const SizedBox(height: AppleSpacing.xs),
                      ],
                      if (!state.results.coveragePlanIsLocalOnly)
                        AppleButton(
                          key: AiAnalysisWorkspaceKeys.startAnalysisKey,
                          label: l10n.aiStartAnalysis,
                          icon: Icons.auto_awesome_outlined,
                          expanded: true,
                          onPressed: state.results.canStartWorkspaceAnalysis
                              ? () => actions.startAnalysis(
                                  fullCoverage: state.coverage.useFullCoverage,
                                )
                              : null,
                        ),
                    ] else ...[
                      AppleButton(
                        key: AiAnalysisWorkspaceKeys.analyzeAgainKey,
                        label: l10n.aiWorkspaceAnalyzeAgain,
                        icon: Icons.auto_awesome_outlined,
                        variant: AppleButtonVariant.pearl,
                        expanded: true,
                        onPressed: state.results.canStartWorkspaceAnalysis
                            ? () => actions.startAnalysis(
                                fullCoverage: state.coverage.useFullCoverage,
                              )
                            : null,
                      ),
                      if ((overview?.reviewCount ?? 0) > 0) ...[
                        const SizedBox(height: AppleSpacing.xs),
                        AppleButton(
                          key: AiAnalysisWorkspaceKeys.reviewQueuePrimaryKey,
                          label: l10n.aiResultsReviewQueuePrimary(
                            overview!.reviewCount,
                          ),
                          onPressed: actions.openReviewQueue,
                        ),
                      ],
                      const SizedBox(height: AppleSpacing.xs),
                      AppleButton(
                        key: AiAnalysisWorkspaceKeys.showAllResultsKey,
                        label: l10n.aiResultsViewFullList,
                        variant: AppleButtonVariant.pearl,
                        onPressed: actions.openDetailList,
                      ),
                    ],
                  ],
                ),
              ),
            if (!state.overview.analyzing && hasVerdicts)
              _buildResultsActionBar(
                context,
                horizontalPadding: horizontalPadding,
                pendingReviewCount: overview?.reviewCount ?? 0,
              ),
          ],
        );
      },
    );
  }

  int _conclusionSafeItemCount() {
    final results = state.results;
    if (results.overview == null) return 0;
    if (state.coverage.useFullCoverage &&
        results.overview!.analyzedItemCount > results.verdicts.length) {
      return results.groups.fold<int>(
        0,
        (total, group) => total + group.safeCount,
      );
    }
    return results.groups
        .expand((group) => group.items)
        .where((item) => item.verdict == 'safe_to_remove')
        .length;
  }

  Widget _buildReviewQueue() {
    return AiAnalysisResultsView(
      state: state,
      reviewItemBuilder: (item) =>
          AiAnalysisReviewItemView(state: state, actions: actions, item: item),
      onBackToResults: actions.backToConclusions,
      onNextDelete: actions.goBack,
    );
  }

  Widget _buildDetailList() {
    if (state.results.resultsLayoutPending && state.results.verdicts.isEmpty) {
      return _buildResultsActivityPlaceholder();
    }
    final showCompactActivity = state.activity.showCompact;
    return AiAnalysisDetailListView(
      state: state,
      actions: actions,
      scrollController: scrollController,
      searchController: searchController,
      showCompactActivity: showCompactActivity,
      coverageBanner: _coverageBanner,
      compactActivityCard: showCompactActivity
          ? _buildActivityCompactCard()
          : null,
    );
  }

  Widget _buildResultsEmptyState(
    BuildContext context, {
    required bool filtered,
  }) {
    final l10n = context.l10n;
    final jobHint = _coverageResultsEmptyJobHint(l10n, state.coverage.jobState);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppleSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filtered
                  ? Icons.search_off_rounded
                  : Icons.check_circle_outline_rounded,
              size: 28,
              color: context.volward.inkMuted48,
            ),
            const SizedBox(height: AppleSpacing.sm),
            Text(
              filtered ? l10n.aiResultsNoMatches : l10n.aiResultsEmpty,
              style: context.vwCaptionStrong,
            ),
            if (state.results.errorMessage case final error?
                when error.trim().isNotEmpty) ...[
              const SizedBox(height: AppleSpacing.xs),
              Text(
                error,
                style: context.vwCaption.copyWith(
                  color: context.volward.danger,
                ),
                textAlign: TextAlign.center,
              ),
            ] else if (jobHint != null) ...[
              const SizedBox(height: AppleSpacing.xs),
              Text(
                jobHint,
                style: context.vwCaption,
                textAlign: TextAlign.center,
              ),
            ],
            if (filtered) ...[
              const SizedBox(height: AppleSpacing.xs),
              AppleButton(
                label: l10n.aiResultsResetFilters,
                icon: Icons.filter_alt_off_outlined,
                variant: AppleButtonVariant.pearl,
                onPressed: actions.resetResultsFilters,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultsActionBar(
    BuildContext context, {
    required double horizontalPadding,
    required int pendingReviewCount,
  }) {
    final l10n = context.l10n;
    final tokens = context.volward;
    final deleting = state.delete.busy;
    final selectedCount = state.results.selectedPaths.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(top: BorderSide(color: tokens.dividerSoft)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          AppleSpacing.sm,
          horizontalPadding,
          AppleSpacing.sm,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final deleteButton = AppleButton(
              key: AiAnalysisWorkspaceKeys.deleteKey,
              label: deleting
                  ? l10n.deleteActionWorking
                  : l10n.aiDeleteSelected(selectedCount),
              icon: deleting ? null : Icons.delete_outline,
              expanded: true,
              onPressed: selectedCount == 0 || deleting
                  ? null
                  : actions.deleteSelected,
            );
            final body = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.aiResultsSelectedForCleanup(
                    selectedCount,
                    _formatBytes(state.results.selectedBytes),
                  ),
                  key: AiAnalysisWorkspaceKeys.selectedSummaryKey,
                  style: context.vwCaptionStrong,
                ),
                const SizedBox(height: AppleSpacing.xxs),
                Text(
                  l10n.aiResultsPendingReviewExcluded(pendingReviewCount),
                  key: AiAnalysisWorkspaceKeys.pendingReviewKey,
                  style: context.vwFinePrint,
                ),
                if (state.results.errorMessage case final error?
                    when error.trim().isNotEmpty) ...[
                  const SizedBox(height: AppleSpacing.xxs),
                  Text(
                    error,
                    style: AppleTypography.caption.copyWith(
                      color: tokens.danger,
                    ),
                  ),
                ],
                if (state.delete.partialDeleteFailedCount != null &&
                    state.delete.partialDeleteFreedBytes != null) ...[
                  const SizedBox(height: AppleSpacing.xxs),
                  Text(
                    l10n.aiWorkspacePartialDelete(
                      state.delete.partialDeleteFailedCount!,
                      _formatBytes(state.delete.partialDeleteFreedBytes!),
                    ),
                    style: AppleTypography.caption.copyWith(
                      color: tokens.danger,
                    ),
                  ),
                ],
                if (state.delete.partialDeleteFailedCount != null) ...[
                  const SizedBox(height: AppleSpacing.xs),
                  Wrap(
                    spacing: AppleSpacing.xs,
                    runSpacing: AppleSpacing.xs,
                    children: [
                      AppleButton(
                        label: l10n.aiActionRetry,
                        icon: Icons.refresh_outlined,
                        variant: AppleButtonVariant.pearl,
                        onPressed: deleting ? null : actions.retryFailedDeletes,
                      ),
                      AppleButton(
                        label: l10n.aiWorkspaceReturn,
                        variant: AppleButtonVariant.pearl,
                        onPressed: deleting ? null : actions.exitWorkspace,
                      ),
                    ],
                  ),
                ],
              ],
            );
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  body,
                  const SizedBox(height: AppleSpacing.sm),
                  deleteButton,
                ],
              );
            }
            final actionButtons = ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
              child: deleteButton,
            );
            return Row(
              children: [
                Expanded(child: body),
                const SizedBox(width: AppleSpacing.md),
                actionButtons,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final l10n = context.l10n;
    final error = state.precheck.error ?? state.results.errorMessage;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppleSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error ?? l10n.aiErrorUnknown,
              textAlign: TextAlign.center,
              style: AppleTypography.body.copyWith(
                color: context.volward.danger,
              ),
            ),
            const SizedBox(height: AppleSpacing.md),
            AppleButton(
              label: l10n.aiActionRetry,
              icon: Icons.refresh_outlined,
              onPressed: actions.retry,
            ),
          ],
        ),
      ),
    );
  }

  String? _coverageResultsEmptyJobHint(
    AppLocalizations l10n,
    CoverageJobState? job,
  ) {
    if (job == null) return null;
    if (job.status == CoverageJobStatus.paused &&
        job.pauseReason == CoveragePauseReason.failed) {
      return coverageFailedReasonCategory(
        l10n,
        job.pauseDetail,
        pauseMessage: job.pauseMessage,
      );
    }
    if (job.status == CoverageJobStatus.running) {
      return l10n.aiCoverageProgress(job.analyzedFiles, job.totalUnclassified);
    }
    if (job.status == CoverageJobStatus.completed &&
        job.totalUnclassified == 0) {
      return '当前扫描快照里没有「未分类」文件，Full Coverage 没有可写入的结果。';
    }
    if (job.status == CoverageJobStatus.completed &&
        job.analyzedFiles == 0 &&
        job.totalUnclassified > 0) {
      return '分析已结束，但 verdict 文件为空。请 Restart full coverage；若仍失败，请确认已用最新 native 库重启应用。';
    }
    if (job.status == CoverageJobStatus.completed &&
        job.analyzedFiles < job.totalUnclassified) {
      return l10n.aiCoverageProgress(job.analyzedFiles, job.totalUnclassified);
    }
    return null;
  }

  static String _formatBytes(num? bytes) {
    if (bytes == null) return '-';
    final value = bytes.toInt();
    if (value < 1024) return '$value B';
    if (value < 1048576) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1073741824) {
      return '${(value / 1073741824).toStringAsFixed(1)} MB';
    }
    return '${(value / 1073741824).toStringAsFixed(2)} GB';
  }
}
