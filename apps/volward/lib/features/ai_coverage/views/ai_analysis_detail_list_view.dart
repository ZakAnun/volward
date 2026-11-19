import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../ai/ai_provider.dart';
import '../../../ai/ai_result_groups.dart';
import '../../../ai/coverage_job_state.dart';
import '../../../ai/coverage_pause_messages.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../theme/apple_tokens.dart';
import '../../../theme/volward_tokens.dart';
import '../../../widgets/ai_result_entry_tile.dart';
import '../../../widgets/apple_widgets.dart';
import '../ai_analysis_workspace_keys.dart';
import 'ai_analysis_workspace_view_actions.dart';
import 'ai_analysis_workspace_view_state.dart';

const _aiWorkspaceExpandedGroupInitialItemCap = 120;

/// Renders the detailed results list, toolbar, search/sort sheet and delete
/// action bar from immutable workspace state and typed actions.
final class AiAnalysisDetailListView extends StatelessWidget {
  const AiAnalysisDetailListView({
    super.key,
    required this.state,
    required this.actions,
    required this.scrollController,
    required this.searchController,
    required this.showCompactActivity,
    this.coverageBanner,
    this.compactActivityCard,
  });

  final AiAnalysisWorkspaceViewState state;
  final AiAnalysisWorkspaceViewActions actions;
  final ScrollController scrollController;
  final TextEditingController searchController;
  final bool showCompactActivity;
  final Widget? coverageBanner;
  final Widget? compactActivityCard;

  @override
  Widget build(BuildContext context) {
    final results = state.results;
    final layout = _DetailListLayout.build(
      groups: results.visibleGroups,
      expandedGroupPaths: results.expandedGroupPaths,
      expandedGroupItemLimits: results.expandedGroupItemLimits,
      showsFilteredItems: results.showsFilteredItems,
    );
    final rowCount = layout.rowCount;
    final deleting = state.delete.busy;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final horizontalPadding = wide ? AppleSpacing.lg : AppleSpacing.md;
        return Column(
          children: [
            if (results.resultsLayoutPending && !showCompactActivity)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: CustomScrollView(
                controller: scrollController,
                scrollCacheExtent: const ScrollCacheExtent.pixels(640),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppleSpacing.md,
                      horizontalPadding,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        key: AiAnalysisWorkspaceKeys.summaryKey,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!deleting &&
                              state.overview.resultsView ==
                                  WorkspaceResultsView.detailList) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: AppleButton(
                                key: AiAnalysisWorkspaceKeys
                                    .backToConclusionsKey,
                                label: context.l10n.aiConclusionsBack,
                                icon: Icons.arrow_back,
                                variant: AppleButtonVariant.pearl,
                                onPressed: actions.backToConclusions,
                              ),
                            ),
                            if (results.directoryFilter case final directory?
                                when directory.isNotEmpty) ...[
                              const SizedBox(height: AppleSpacing.xs),
                              Text(
                                context.l10n.aiReviewQueueFilteredDir(
                                  directory,
                                ),
                                style: context.vwCaption,
                              ),
                            ],
                            const SizedBox(height: AppleSpacing.sm),
                          ],
                          if (coverageBanner != null) ...[
                            KeyedSubtree(
                              key: const Key('ai-analysis-coverage-progress'),
                              child: coverageBanner!,
                            ),
                            const SizedBox(height: AppleSpacing.sm),
                          ],
                          if (showCompactActivity) ...[
                            compactActivityCard ?? const SizedBox.shrink(),
                            const SizedBox(height: AppleSpacing.sm),
                          ],
                          Text(
                            context.l10n.aiResultsDecisionSummary(
                              _formatBytes(results.safeBytes),
                              results.reviewCount,
                            ),
                            key: AiAnalysisWorkspaceKeys.decisionSummaryKey,
                            style: context.vwBodyStrong,
                          ),
                          if (results.showsLocalPreviewHint) ...[
                            const SizedBox(height: AppleSpacing.xxs),
                            Text(
                              context.l10n.aiResultsLocalPreviewHint,
                              style: context.vwCaption,
                            ),
                          ],
                          if (results.groups.isNotEmpty) ...[
                            const SizedBox(height: AppleSpacing.sm),
                            _buildToolbar(context, wide: wide),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (rowCount == 0)
                    SliverFillRemaining(
                      child: _buildEmptyState(
                        context,
                        filtered:
                            results.groups.isNotEmpty &&
                            results.showsFilteredItems,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      sliver: SliverList(
                        key: AiAnalysisWorkspaceKeys.resultsListKey,
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final row = layout.rowAt(index);
                            if (row == null) return const SizedBox.shrink();
                            return _buildStreamRow(context, row);
                          },
                          findChildIndexCallback: (key) =>
                              _findRowIndex(layout, key),
                          childCount: rowCount,
                          addRepaintBoundaries: true,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _buildActionBar(context, horizontalPadding: horizontalPadding),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(BuildContext context, {required bool wide}) {
    final searchToggle = IconButton(
      key: AiAnalysisWorkspaceKeys.searchToggleKey,
      tooltip: context.l10n.aiResultsSearchSortTitle,
      icon: const Icon(Icons.search_rounded, size: 18),
      onPressed: () => _openSearchSortSheet(context),
    );
    final keepHint =
        state.coverage.useFullCoverage &&
            state.results.filter == WorkspaceResultFilter.all
        ? Padding(
            padding: const EdgeInsets.only(top: AppleSpacing.xxs),
            child: Text(
              context.l10n.aiResultsKeepExpandHint,
              key: AiAnalysisWorkspaceKeys.resultsKeepExpandHintKey,
              style: context.vwCaption,
            ),
          )
        : const SizedBox.shrink();
    if (wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppleSpacing.xs,
            runSpacing: AppleSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [searchToggle, _buildSegmentBar(context, false)],
          ),
          keepHint,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSegmentBar(context, true),
        Align(alignment: Alignment.centerLeft, child: searchToggle),
        keepHint,
      ],
    );
  }

  Widget _buildSegmentBar(BuildContext context, bool compact) {
    final l10n = context.l10n;
    final segments = <(WorkspaceResultFilter, String)>[
      (WorkspaceResultFilter.review, l10n.aiResultsFilterReview),
      (WorkspaceResultFilter.safeToRemove, l10n.aiResultsFilterSafeToRemove),
      (WorkspaceResultFilter.selected, l10n.aiResultsFilterSelected),
      (WorkspaceResultFilter.all, l10n.aiResultsFilterAll),
    ];
    final chips = [
      for (final segment in segments)
        AppleFilterChip(
          key: ValueKey<String>('ai-results-segment:${segment.$1.name}'),
          label: segment.$2,
          selected: state.results.filter == segment.$1,
          onTap: () => actions.setResultFilter(segment.$1),
        ),
    ];
    final bar = Wrap(
      spacing: AppleSpacing.xxs,
      runSpacing: AppleSpacing.xxs,
      children: chips,
    );
    if (compact) {
      return KeyedSubtree(
        key: AiAnalysisWorkspaceKeys.resultsFilterKey,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: AppleSpacing.xxs),
                chips[i],
              ],
            ],
          ),
        ),
      );
    }
    return KeyedSubtree(
      key: AiAnalysisWorkspaceKeys.resultsFilterKey,
      child: bar,
    );
  }

  Future<void> _openSearchSortSheet(BuildContext context) async {
    final tokens = context.volward;
    final l10n = context.l10n;
    final titleStyle = context.vwBodyStrong;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: tokens.canvas,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: AppleSpacing.md,
            right: AppleSpacing.md,
            top: AppleSpacing.sm,
            bottom:
                MediaQuery.viewInsetsOf(sheetContext).bottom + AppleSpacing.lg,
          ),
          child: StatefulBuilder(
            builder: (_, setSheetState) {
              return Column(
                key: AiAnalysisWorkspaceKeys.searchSortSheetKey,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.aiResultsSearchSortTitle, style: titleStyle),
                  const SizedBox(height: AppleSpacing.sm),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.surfacePearl,
                      borderRadius: BorderRadius.circular(AppleRadius.sm),
                      border: Border.all(color: tokens.hairline),
                    ),
                    child: TextField(
                      controller: searchController,
                      autofocus: true,
                      onChanged: (value) {
                        actions.setResultsQuery(value);
                        setSheetState(() {});
                      },
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: l10n.aiResultsSearchHint,
                        border: InputBorder.none,
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: tokens.inkMuted48,
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppleSpacing.sm,
                          vertical: AppleSpacing.sm,
                        ),
                        suffix: state.results.query.isEmpty
                            ? null
                            : GestureDetector(
                                onTap: () {
                                  actions.setResultsQuery('');
                                  searchController.clear();
                                  setSheetState(() {});
                                },
                                child: Tooltip(
                                  message: l10n.aiResultsClearSearch,
                                  child: Icon(
                                    Icons.clear_rounded,
                                    size: 18,
                                    color: tokens.inkMuted80,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppleSpacing.sm),
                  Wrap(
                    spacing: AppleSpacing.xxs,
                    runSpacing: AppleSpacing.xxs,
                    children: [
                      for (final mode in WorkspaceResultSort.values)
                        FilterChip(
                          label: Text(_sortLabel(l10n, mode)),
                          selected: state.results.sort == mode,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onSelected: (_) {
                            actions.setResultSort(mode);
                            setSheetState(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: AppleSpacing.md),
                  AppleButton(
                    label: l10n.aiResultsSearchSortDone,
                    expanded: true,
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, {required bool filtered}) {
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

  Widget _buildActionBar(
    BuildContext context, {
    required double horizontalPadding,
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
                  l10n.aiResultsPendingReviewExcluded(
                    state.results.reviewCount,
                  ),
                  key: AiAnalysisWorkspaceKeys.pendingReviewKey,
                  style: context.vwFinePrint,
                ),
                if (state.results.errorMessage != null &&
                    state.delete.partialDeleteFailedCount == null) ...[
                  const SizedBox(height: AppleSpacing.xxs),
                  Text(
                    state.results.errorMessage!,
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
                        onPressed: deleting ? null : actions.deleteSelected,
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
            final actionsBox = ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
              child: deleteButton,
            );
            return Row(
              children: [
                Expanded(child: body),
                const SizedBox(width: AppleSpacing.md),
                actionsBox,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStreamRow(BuildContext context, _DetailListRow row) {
    final results = state.results;
    return RepaintBoundary(
      child: switch (row) {
        _DetailListGroupRow(:final visibleGroup) => AiWorkspaceResultGroupRow(
          key: row.key,
          group: visibleGroup.group,
          expanded: results.expandedGroupPaths.contains(
            visibleGroup.group.path,
          ),
          selectionValue: _safeGroupSelectionValue(
            visibleGroup.items,
            results.selectedPaths,
          ),
          onSelectionChanged:
              visibleGroup.items
                  .where((item) => item.verdict == 'safe_to_remove')
                  .isEmpty
              ? null
              : (value) => actions.toggleSafeGroup(
                  visibleGroup.items
                      .where((item) => item.verdict == 'safe_to_remove')
                      .map((item) => item.path)
                      .toList(growable: false),
                  value == true,
                ),
          onTap: () => actions.toggleGroupExpanded(visibleGroup.group.path),
          summaryLabel: _groupSummaryLabel(context, state, visibleGroup),
          metadataLabels: _groupMetadataLabels(context, state, visibleGroup),
        ),
        _DetailListShowMoreRow(:final groupPath, :final shown, :final total) =>
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: row.key,
              onPressed: () => actions.showMoreItemsInGroup(groupPath, total),
              child: Text(
                context.l10n.aiResultsShowMoreInGroup(
                  (total - shown).clamp(1, total),
                ),
              ),
            ),
          ),
        _DetailListItemRow(:final item) => AiWorkspaceResultRow(
          key: row.key,
          item: item,
          sizeLabel: _formatBytes(results.sizeByPath[item.path] ?? 0),
          selected: results.selectedPaths.contains(item.path),
          reviewDecision:
              results.reviewDecisions[item.path] ??
              WorkspaceReviewDecision.pending,
          onChanged: item.verdict == 'safe_to_remove'
              ? (value) => actions.setSelection(item.path, value == true)
              : null,
          onTap: switch (item.verdict) {
            'safe_to_remove' => () => actions.toggleSelection(item.path),
            'review_needed' => () => actions.toggleReviewExpanded(item.path),
            _ => null,
          },
          expanded: results.expandedReviewPaths.contains(item.path),
          onDecisionChanged: item.verdict == 'review_needed'
              ? (decision) => actions.setReviewDecision(item.path, decision)
              : null,
          cleanupMeta: _cleanupMetaLabel(context, item),
          cleanupSource: _cleanupSourceLabel(context, item),
          retentionHint: _retentionHintLabel(context, item),
          reviewStatusLabel: _reviewStatusLabel(
            context,
            results.reviewDecisions[item.path] ??
                WorkspaceReviewDecision.pending,
          ),
        ),
      },
    );
  }
}

String _formatBytes(num? bytes) {
  if (bytes == null) return '-';
  final value = bytes.toInt();
  if (value < 1024) return '$value B';
  if (value < 1048576) return '${(value / 1024).toStringAsFixed(1)} KB';
  if (value < 1073741824) {
    return '${(value / 1048576).toStringAsFixed(1)} MB';
  }
  return '${(value / 1073741824).toStringAsFixed(2)} GB';
}

String _sortLabel(AppLocalizations l10n, WorkspaceResultSort mode) {
  return switch (mode) {
    WorkspaceResultSort.priority => l10n.aiResultsSortPriority,
    WorkspaceResultSort.size => l10n.aiResultsSortSize,
  };
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
  if (job.status == CoverageJobStatus.completed && job.totalUnclassified == 0) {
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

String? _cleanupMetaLabel(BuildContext context, AiVerdict item) {
  final parts = <String>[
    if (_cleanupSourceLabel(context, item) case final source?) source,
    if (_retentionHintLabel(context, item) case final retention?) retention,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String? _cleanupSourceLabel(BuildContext context, AiVerdict item) {
  final source = item.cleanupSource;
  if (source == null || source.isEmpty) return null;
  return switch (source) {
    'ai_tool_cache' => context.l10n.aiCleanupSourceAiToolCache,
    'ai_generated_output' => context.l10n.aiCleanupSourceAiGeneratedOutput,
    'system_temp' => context.l10n.aiCleanupSourceSystemTemp,
    _ => source,
  };
}

String? _retentionHintLabel(BuildContext context, AiVerdict item) {
  final parts = <String>[
    if (item.retentionDays != null)
      context.l10n.aiCleanupRetentionDays(item.retentionDays!),
    if (item.cleanupHint case final hint? when hint.isNotEmpty) hint,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String _reviewStatusLabel(
  BuildContext context,
  WorkspaceReviewDecision decision,
) {
  return switch (decision) {
    WorkspaceReviewDecision.pending => context.l10n.aiResultsNeedsYourDecision,
    WorkspaceReviewDecision.include => context.l10n.aiResultsAddedToCleanup,
    WorkspaceReviewDecision.keep => context.l10n.aiResultsKeptOutOfCleanup,
  };
}

bool? _safeGroupSelectionValue(
  Iterable<AiVerdict> items,
  Set<String> selectedPaths,
) {
  final safeItems = items
      .where((item) => item.verdict == 'safe_to_remove')
      .toList(growable: false);
  if (safeItems.isEmpty) return false;
  final selectedSafeCount = safeItems
      .where((item) => selectedPaths.contains(item.path))
      .length;
  if (selectedSafeCount == 0) return false;
  if (selectedSafeCount == safeItems.length) return true;
  return null;
}

String _groupSummaryLabel(
  BuildContext context,
  AiAnalysisWorkspaceViewState state,
  AiWorkspaceVisibleResultGroup group,
) {
  final full = group.group;
  final listed = group.items.length;
  final total = full.safeCount + full.reviewCount + full.keepCount;
  var count = listed < total ? total : listed;
  if (listed >= total && state.coverage.useFullCoverage) {
    final actionable = group.actionableCount > 0
        ? group.actionableCount
        : full.safeCount + full.reviewCount;
    count = actionable > 0 ? actionable : listed;
  }
  return context.l10n.aiResultsGroupItems(
    count,
    _formatBytes(group.totalBytes),
  );
}

List<String> _groupMetadataLabels(
  BuildContext context,
  AiAnalysisWorkspaceViewState state,
  AiWorkspaceVisibleResultGroup group,
) {
  final full = group.group;
  final itemSource = group.items.isEmpty && state.coverage.useFullCoverage
      ? full.items
      : group.items;
  final visibleSafeCount = itemSource
      .where((item) => item.verdict == 'safe_to_remove')
      .length;
  final pendingReview = itemSource.where((item) {
    return item.verdict == 'review_needed' &&
        (state.results.reviewDecisions[item.path] ??
                WorkspaceReviewDecision.pending) ==
            WorkspaceReviewDecision.pending;
  }).length;
  final keepCount = itemSource.where((item) => item.verdict == 'keep').length;
  final visibleSelectedCount = group.items
      .where((item) => state.results.selectedPaths.contains(item.path))
      .length;
  return [
    context.l10n.aiResultsGroupSafe(visibleSafeCount),
    context.l10n.aiResultsGroupReview(pendingReview),
    context.l10n.aiResultsGroupKeep(keepCount),
    if (visibleSelectedCount > 0)
      context.l10n.aiResultsSelectedInGroup(visibleSelectedCount),
  ];
}

int? _findRowIndex(_DetailListLayout layout, Key key) {
  for (var index = 0; index < layout.rowCount; index++) {
    final row = layout.rowAt(index);
    if (row != null && row.key == key) return index;
  }
  return null;
}

final class _DetailListLayout {
  _DetailListLayout({
    required this.groups,
    required this.prefixEnds,
    required this.expandedGroupPaths,
    required this.showsFilteredItems,
    required this.expandedGroupItemLimits,
  });

  final List<AiWorkspaceVisibleResultGroup> groups;
  final List<int> prefixEnds;
  final Set<String> expandedGroupPaths;
  final bool showsFilteredItems;
  final Map<String, int> expandedGroupItemLimits;

  int get rowCount => prefixEnds.isEmpty ? 0 : prefixEnds.last;

  static _DetailListLayout build({
    required List<AiWorkspaceVisibleResultGroup> groups,
    required Set<String> expandedGroupPaths,
    required bool showsFilteredItems,
    required Map<String, int> expandedGroupItemLimits,
  }) {
    final prefixEnds = <int>[0];
    for (final group in groups) {
      var span = 1;
      final showItems =
          expandedGroupPaths.contains(group.group.path) || showsFilteredItems;
      if (showItems) {
        final limit = _itemLimitFor(
          expandedGroupItemLimits,
          group.group.path,
          group.items.length,
        );
        span += limit;
        if (!showsFilteredItems && group.items.length > limit && limit > 0) {
          span += 1;
        }
      }
      prefixEnds.add(prefixEnds.last + span);
    }
    return _DetailListLayout(
      groups: groups,
      prefixEnds: prefixEnds,
      expandedGroupPaths: expandedGroupPaths,
      showsFilteredItems: showsFilteredItems,
      expandedGroupItemLimits: expandedGroupItemLimits,
    );
  }

  _DetailListRow? rowAt(int index) {
    if (index < 0 || index >= rowCount || groups.isEmpty) return null;
    var lo = 0;
    var hi = groups.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (prefixEnds[mid] <= index) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final group = groups[lo];
    final local = index - prefixEnds[lo];
    if (local == 0) return _DetailListRow.group(group);
    final showItems =
        expandedGroupPaths.contains(group.group.path) || showsFilteredItems;
    if (!showItems) return null;
    final limit = _itemLimitFor(
      expandedGroupItemLimits,
      group.group.path,
      group.items.length,
    );
    final itemIndex = local - 1;
    if (itemIndex < limit) {
      return _DetailListRow.item(group.group, group.items[itemIndex]);
    }
    if (itemIndex == limit &&
        !showsFilteredItems &&
        group.items.length > limit &&
        limit > 0) {
      return _DetailListRow.showMore(
        groupPath: group.group.path,
        shown: limit,
        total: group.items.length,
      );
    }
    return null;
  }
}

int _itemLimitFor(
  Map<String, int> expandedGroupItemLimits,
  String groupPath,
  int itemCount,
) {
  final limit =
      expandedGroupItemLimits[groupPath] ??
      _aiWorkspaceExpandedGroupInitialItemCap;
  return limit.clamp(0, itemCount);
}

sealed class _DetailListRow {
  const _DetailListRow();

  factory _DetailListRow.group(AiWorkspaceVisibleResultGroup group) =
      _DetailListGroupRow;

  factory _DetailListRow.item(AiResultGroup group, AiVerdict item) =
      _DetailListItemRow;

  factory _DetailListRow.showMore({
    required String groupPath,
    required int shown,
    required int total,
  }) = _DetailListShowMoreRow;

  Key get key;
}

final class _DetailListGroupRow extends _DetailListRow {
  const _DetailListGroupRow(this.visibleGroup);

  final AiWorkspaceVisibleResultGroup visibleGroup;

  @override
  Key get key => ValueKey<String>('ai-result-group:${visibleGroup.group.path}');
}

final class _DetailListItemRow extends _DetailListRow {
  const _DetailListItemRow(this.group, this.item);

  final AiResultGroup group;
  final AiVerdict item;

  @override
  Key get key => ValueKey<String>('ai-result-item:${item.path}');
}

final class _DetailListShowMoreRow extends _DetailListRow {
  const _DetailListShowMoreRow({
    required this.groupPath,
    required this.shown,
    required this.total,
  });

  final String groupPath;
  final int shown;
  final int total;

  @override
  Key get key => ValueKey<String>('ai-result-show-more:$groupPath');
}

final class AiWorkspaceResultGroupRow extends StatelessWidget {
  const AiWorkspaceResultGroupRow({
    super.key,
    required this.group,
    required this.expanded,
    required this.selectionValue,
    required this.onSelectionChanged,
    required this.onTap,
    required this.summaryLabel,
    required this.metadataLabels,
  });

  final AiResultGroup group;
  final bool expanded;
  final bool? selectionValue;
  final ValueChanged<bool?>? onSelectionChanged;
  final VoidCallback onTap;
  final String summaryLabel;
  final List<String> metadataLabels;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    final checkbox = Checkbox(
      key: Key('ai-group-toggle:${group.path}'),
      tristate: true,
      value: selectionValue,
      onChanged: onSelectionChanged,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: expanded ? tokens.surfacePearl : tokens.canvas,
        border: Border(bottom: BorderSide(color: tokens.dividerSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppleSpacing.sm,
              AppleSpacing.sm,
              AppleSpacing.xs,
              AppleSpacing.sm,
            ),
            child: SizedBox(
              width: 40,
              height: 40,
              child: FittedBox(fit: BoxFit.scaleDown, child: checkbox),
            ),
          ),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    0,
                    AppleSpacing.sm,
                    AppleSpacing.sm,
                    AppleSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedRotation(
                            turns: expanded ? 0.25 : 0,
                            duration: const Duration(milliseconds: 160),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: tokens.inkMuted80,
                            ),
                          ),
                          const SizedBox(width: AppleSpacing.xs),
                          Icon(
                            Icons.folder_outlined,
                            size: 18,
                            color: tokens.folderIcon,
                          ),
                          const SizedBox(width: AppleSpacing.xs),
                          Expanded(
                            child: _PathLabel(
                              group.path,
                              style: context.vwCaptionStrong,
                              maxLines: 2,
                            ),
                          ),
                          const SizedBox(width: AppleSpacing.sm),
                          Flexible(
                            child: Text(
                              summaryLabel,
                              textAlign: TextAlign.right,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.vwFinePrintInk,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppleSpacing.xxs),
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 18 + AppleSpacing.xs,
                        ),
                        child: Wrap(
                          spacing: AppleSpacing.sm,
                          runSpacing: AppleSpacing.xxs,
                          children: [
                            for (
                              var index = 0;
                              index < metadataLabels.length;
                              index++
                            )
                              Text(
                                metadataLabels[index],
                                style: context.vwFinePrint.copyWith(
                                  color: switch (index) {
                                    0 => tokens.primary,
                                    1 => tokens.warning,
                                    _ => null,
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class AiWorkspaceResultRow extends StatelessWidget {
  const AiWorkspaceResultRow({
    super.key,
    required this.item,
    required this.sizeLabel,
    required this.selected,
    required this.reviewDecision,
    required this.onChanged,
    required this.onTap,
    required this.expanded,
    required this.onDecisionChanged,
    required this.cleanupMeta,
    required this.cleanupSource,
    required this.retentionHint,
    required this.reviewStatusLabel,
  });

  final AiVerdict item;
  final String sizeLabel;
  final bool selected;
  final WorkspaceReviewDecision reviewDecision;
  final ValueChanged<bool?>? onChanged;
  final VoidCallback? onTap;
  final bool expanded;
  final ValueChanged<WorkspaceReviewDecision>? onDecisionChanged;
  final String? cleanupMeta;
  final String? cleanupSource;
  final String? retentionHint;
  final String reviewStatusLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    final isSafe = item.verdict == 'safe_to_remove';
    final isReview = item.verdict == 'review_needed';
    final leading = switch (item.verdict) {
      'safe_to_remove' => Checkbox(
        key: Key('ai-item-toggle:${item.path}'),
        value: selected,
        onChanged: onChanged,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      'review_needed' => Icon(
        Icons.pending_actions_outlined,
        size: 18,
        color: tokens.warning,
      ),
      'unanalyzed' => Icon(
        Icons.hourglass_empty_outlined,
        size: 18,
        color: tokens.inkMuted48,
      ),
      _ => Icon(Icons.lock_outline, size: 18, color: tokens.inkMuted48),
    };
    final entryTile = AiResultEntryTile(
      item: item,
      sizeLabel: sizeLabel,
      variant: AiResultEntryTileVariant.listRow,
      cleanupMeta: cleanupMeta,
      reviewStatusLabel: isReview ? reviewStatusLabel : null,
      showInlineSize: false,
    );
    final sizeText = Text(
      sizeLabel,
      textAlign: TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.vwCaptionStrong,
    );
    final reviewDisclosure = isReview
        ? AnimatedRotation(
            turns: expanded ? 0.25 : 0,
            duration: const Duration(milliseconds: 160),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: tokens.warning,
            ),
          )
        : null;
    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppleSpacing.sm,
        vertical: AppleSpacing.xs,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 40, child: leading),
                    const SizedBox(width: AppleSpacing.xs),
                    Expanded(child: entryTile),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 40 + AppleSpacing.xs,
                    top: AppleSpacing.xxs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: sizeText),
                      if (reviewDisclosure != null) reviewDisclosure,
                    ],
                  ),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 40, child: leading),
              const SizedBox(width: AppleSpacing.xs),
              Expanded(child: entryTile),
              const SizedBox(width: AppleSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(
                  width: reviewDisclosure == null ? 88 : 110,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      sizeText,
                      if (reviewDisclosure != null) reviewDisclosure,
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    final rowBody = onTap == null
        ? body
        : Semantics(
            expanded: isReview ? expanded : null,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: body,
              ),
            ),
          );
    final showsDetails = expanded && isReview && onDecisionChanged != null;
    final row = DecoratedBox(
      decoration: BoxDecoration(
        color: isSafe && selected ? tokens.canvasParchment : tokens.canvas,
        border: Border(bottom: BorderSide(color: tokens.dividerSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: AppleSpacing.lg),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                rowBody,
                if (showsDetails)
                  Padding(
                    key: Key('ai-review-detail:${item.path}'),
                    padding: const EdgeInsets.fromLTRB(
                      AppleSpacing.sm + 40 + AppleSpacing.xs,
                      0,
                      AppleSpacing.sm,
                      AppleSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ResultDetailLine(
                          label: context.l10n.aiResultsDetailSize,
                          value: sizeLabel,
                        ),
                        _ResultDetailLine(
                          label: context.l10n.aiResultsDetailConfidence,
                          value: item.confidence,
                        ),
                        if (item.reason.isNotEmpty)
                          _ResultDetailLine(
                            label: context.l10n.aiResultsDetailReason,
                            value: item.reason,
                          ),
                        if (cleanupSource != null && cleanupSource!.isNotEmpty)
                          _ResultDetailLine(
                            label: context.l10n.aiResultsDetailCleanupSource,
                            value: cleanupSource!,
                          ),
                        if (retentionHint != null && retentionHint!.isNotEmpty)
                          _ResultDetailLine(
                            label: context.l10n.aiResultsDetailRetentionHint,
                            value: retentionHint!,
                          ),
                        const SizedBox(height: AppleSpacing.xs),
                        _ReviewDecisionButtons(
                          path: item.path,
                          decision: reviewDecision,
                          onChanged: onDecisionChanged!,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return row;
  }
}

class _ReviewDecisionButtons extends StatelessWidget {
  const _ReviewDecisionButtons({
    required this.path,
    required this.decision,
    required this.onChanged,
  });

  final String path;
  final WorkspaceReviewDecision decision;
  final ValueChanged<WorkspaceReviewDecision> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppleSpacing.xs,
      runSpacing: AppleSpacing.xs,
      children: [
        AppleButton(
          key: Key('ai-review-include:$path'),
          label: context.l10n.aiResultsAddToCleanup,
          icon: Icons.add_task_outlined,
          onPressed: decision == WorkspaceReviewDecision.include
              ? null
              : () => onChanged(WorkspaceReviewDecision.include),
        ),
        AppleButton(
          key: Key('ai-review-keep:$path'),
          label: context.l10n.aiResultsKeepItem,
          icon: Icons.lock_outline,
          variant: AppleButtonVariant.pearl,
          onPressed: decision == WorkspaceReviewDecision.keep
              ? null
              : () => onChanged(WorkspaceReviewDecision.keep),
        ),
      ],
    );
  }
}

class _ResultDetailLine extends StatelessWidget {
  const _ResultDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppleSpacing.xxs),
      child: Text('$label: $value', softWrap: true, style: context.vwFinePrint),
    );
  }
}

class _PathLabel extends StatelessWidget {
  const _PathLabel(this.path, {this.style, this.maxLines = 2});

  final String path;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      value: path,
      child: Text(
        path,
        maxLines: maxLines,
        softWrap: true,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}
