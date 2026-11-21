import 'package:flutter/material.dart';

import '../../../ai/ai_conclusion_synthesis.dart';
import '../../../ai/ai_result_overview.dart';
import '../../../ai/ai_result_groups.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/apple_tokens.dart';
import '../../../theme/volward_tokens.dart';
import '../../../widgets/apple_widgets.dart';
import '../../ai_coverage/ai_analysis_workspace_keys.dart';
import 'ai_analysis_workspace_view_state.dart';

/// Renders the conclusions overview, directory summaries and optional
/// narrative from immutable workspace state.
///
/// The page shell composes scope, activity and coverage-banner slots above
/// this view and keeps the shared delete/action bar below it.
final class AiAnalysisOverviewView extends StatelessWidget {
  const AiAnalysisOverviewView({
    super.key,
    required this.state,
    required this.hasVerdicts,
    required this.safeCount,
    required this.analyzing,
    required this.canGenerateNarrative,
    required this.showNarrativeCreditHint,
    required this.emptyState,
    required this.onOpenDetailPage,
    required this.onOpenReviewQueue,
    required this.onDirectoryTypeFilterChanged,
    required this.onGenerateNarrative,
  });

  final AiAnalysisWorkspaceViewState state;
  final bool hasVerdicts;
  final int safeCount;
  final bool analyzing;
  final bool canGenerateNarrative;
  final bool showNarrativeCreditHint;
  final Widget emptyState;
  final void Function({String? directoryPath}) onOpenDetailPage;
  final VoidCallback onOpenReviewQueue;
  final ValueChanged<WorkspaceDirectoryTypeFilter> onDirectoryTypeFilterChanged;
  final VoidCallback onGenerateNarrative;

  @override
  Widget build(BuildContext context) {
    final overview = state.results.overview;
    final l10n = context.l10n;
    if (overview == null) return const SizedBox.shrink();

    final shareRoot = overview.shareOfRootPct != null
        ? l10n.aiConclusionsShareRootSuffix(
            overview.shareOfRootPct!.toStringAsFixed(1),
          )
        : '';
    final hiddenDirCount =
        state.results.directoryBucketCount - overview.directories.length;
    final staleUpdating = analyzing && hasVerdicts;
    final directories = _directoriesForType(
      overview,
      state.results.directoryTypeFilter,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasVerdicts) ...[
          Text(
            l10n.aiConclusionsScanLine(
              overview.targetLabel,
              overview.analyzedItemCount,
              _formatBytes(overview.analyzedTotalBytes),
            ),
            style: context.vwCaption,
          ),
          const SizedBox(height: AppleSpacing.xxs),
          Text(
            overview.fullCoverage
                ? l10n.aiConclusionsModeFull
                : l10n.aiConclusionsModeQuick,
            style: context.vwCaption,
          ),
          if (overview.truncated) ...[
            const SizedBox(height: AppleSpacing.xxs),
            Text(l10n.aiConclusionsTruncated, style: context.vwCaption),
          ],
        ],
        const SizedBox(height: AppleSpacing.sm),
        Opacity(
          opacity: staleUpdating ? 0.55 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResultsHero(
                overview: overview,
                shareRoot: shareRoot,
                placeholder: !hasVerdicts,
                analyzing: analyzing,
              ),
              const SizedBox(height: AppleSpacing.sm),
              _ResultsMetricCards(
                overview: overview,
                placeholder: !hasVerdicts,
                safeCount: safeCount,
                onOpenDetailPage: onOpenDetailPage,
                onOpenReviewQueue: onOpenReviewQueue,
              ),
              const SizedBox(height: AppleSpacing.sm),
              if (state.results.loadedEmptySuggestions && !hasVerdicts)
                emptyState,
            ],
          ),
        ),
        if (hasVerdicts) ...[
          const SizedBox(height: AppleSpacing.sm),
          Text(l10n.aiConclusionsLead, style: context.vwBody),
          _NarrativeSection(
            narrative: state.narrative,
            overview: overview,
            groups: state.results.groups,
            canGenerate: canGenerateNarrative,
            showCreditHint: showNarrativeCreditHint,
            onGenerate: onGenerateNarrative,
          ),
        ],
        if (overview.directories.isNotEmpty) ...[
          const SizedBox(height: AppleSpacing.md),
          Text(l10n.aiConclusionsByDirectory, style: context.vwBodyStrong),
          const SizedBox(height: AppleSpacing.sm),
          _DirectoryTypeFilterBar(
            selected: state.results.directoryTypeFilter,
            onChanged: onDirectoryTypeFilterChanged,
          ),
          const SizedBox(height: AppleSpacing.sm),
          _DirectoryGrid(
            directories: directories,
            onOpenDetailPage: onOpenDetailPage,
          ),
          if (hiddenDirCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppleSpacing.xs),
              child: Text(
                l10n.aiConclusionsMoreDirs(hiddenDirCount),
                style: context.vwCaption,
              ),
            ),
        ],
      ],
    );
  }

  static List<AiDirectoryConclusion> _directoriesForType(
    AiAnalysisConclusionOverview overview,
    WorkspaceDirectoryTypeFilter filter,
  ) {
    return overview.directories
        .where((directory) {
          return switch (filter) {
            WorkspaceDirectoryTypeFilter.safe => directory.safeBytes > 0,
            WorkspaceDirectoryTypeFilter.review => directory.reviewCount > 0,
            WorkspaceDirectoryTypeFilter.keep => directory.keepCount > 0,
          };
        })
        .toList(growable: false);
  }

  static String _formatBytes(num? bytes) {
    if (bytes == null) return '-';
    final value = bytes.toInt();
    if (value < 1024) return '$value B';
    if (value < 1048576) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1073741824) {
      return '${(value / 1048576).toStringAsFixed(1)} MB';
    }
    return '${(value / 1073741824).toStringAsFixed(2)} GB';
  }
}

class _ResultsHero extends StatelessWidget {
  const _ResultsHero({
    required this.overview,
    required this.shareRoot,
    required this.placeholder,
    required this.analyzing,
  });

  final AiAnalysisConclusionOverview overview;
  final String shareRoot;
  final bool placeholder;
  final bool analyzing;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final heroLine = placeholder
        ? (analyzing
              ? l10n.aiResultsHubStatusAnalyzing
              : l10n.aiResultsHubStatusAwaiting)
        : l10n.aiResultsHeroLine(
            AiAnalysisOverviewView._formatBytes(overview.safeBytes),
            overview.reviewCount,
          );
    return KeyedSubtree(
      key: AiAnalysisWorkspaceKeys.resultsHeroKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heroLine,
            key: AiAnalysisWorkspaceKeys.decisionSummaryKey,
            style: context.vwBodyStrong,
          ),
          if (!placeholder && shareRoot.isNotEmpty) ...[
            const SizedBox(height: AppleSpacing.xxs),
            Text(shareRoot, style: context.vwCaption),
          ],
        ],
      ),
    );
  }
}

class _ResultsMetricCards extends StatelessWidget {
  const _ResultsMetricCards({
    required this.overview,
    required this.placeholder,
    required this.safeCount,
    required this.onOpenDetailPage,
    required this.onOpenReviewQueue,
  });

  final AiAnalysisConclusionOverview overview;
  final bool placeholder;
  final int safeCount;
  final void Function({String? directoryPath}) onOpenDetailPage;
  final VoidCallback onOpenReviewQueue;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const dash = '—';
    final cards = [
      _MetricCard(
        cardKey: AiAnalysisWorkspaceKeys.resultsMetricSafeKey,
        title: l10n.aiResultsMetricSafeTitle,
        value: placeholder
            ? dash
            : AiAnalysisOverviewView._formatBytes(overview.safeBytes),
        subtitle: placeholder ? dash : l10n.aiResultsMetricCountLine(safeCount),
        onTap: placeholder ? null : () => onOpenDetailPage(),
      ),
      _MetricCard(
        cardKey: AiAnalysisWorkspaceKeys.resultsMetricReviewKey,
        title: l10n.aiResultsMetricReviewTitle,
        value: placeholder ? dash : '${overview.reviewCount}',
        subtitle: placeholder ? dash : l10n.aiResultsMetricReviewSubtitle,
        onTap: !placeholder && overview.reviewCount > 0
            ? onOpenReviewQueue
            : null,
      ),
      _MetricCard(
        cardKey: AiAnalysisWorkspaceKeys.resultsMetricKeepKey,
        title: l10n.aiResultsMetricKeepTitle,
        value: placeholder ? dash : '${overview.keepCount}',
        subtitle: placeholder ? dash : l10n.aiResultsMetricKeepSubtitle,
        onTap: placeholder ? null : () => onOpenDetailPage(),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 640) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: AppleSpacing.xs),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(height: AppleSpacing.xs),
              cards[i],
            ],
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.cardKey,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.onTap,
  });

  final Key cardKey;
  final String title;
  final String value;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    final child = Padding(
      padding: const EdgeInsets.all(AppleSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.vwCaption),
          const SizedBox(height: AppleSpacing.xxs),
          Text(value, style: context.vwBodyStrong),
          Text(subtitle, style: context.vwCaption),
        ],
      ),
    );
    return Material(
      key: cardKey,
      color: tokens.surfacePearl,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        side: BorderSide(color: tokens.hairline),
      ),
      child: onTap == null
          ? child
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppleRadius.sm),
              child: child,
            ),
    );
  }
}

class _DirectoryTypeFilterBar extends StatelessWidget {
  const _DirectoryTypeFilterBar({
    required this.selected,
    required this.onChanged,
  });

  final WorkspaceDirectoryTypeFilter selected;
  final ValueChanged<WorkspaceDirectoryTypeFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.volward;
    final segments = <(WorkspaceDirectoryTypeFilter, String)>[
      (WorkspaceDirectoryTypeFilter.safe, l10n.aiResultsFilterSafeToRemove),
      (WorkspaceDirectoryTypeFilter.review, l10n.aiResultsFilterReview),
      (WorkspaceDirectoryTypeFilter.keep, l10n.aiResultsMetricKeepTitle),
    ];
    return KeyedSubtree(
      key: AiAnalysisWorkspaceKeys.directoryTypeFilterKey,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfacePearl,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          border: Border.all(color: tokens.hairline),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          child: SizedBox(
            height: 32,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < segments.length; i++) ...[
                  if (i > 0) Container(width: 1, color: tokens.hairline),
                  Expanded(
                    child: _DirectoryTypeSegment(
                      key: AiAnalysisWorkspaceKeys.directoryTypeChipKey(
                        segments[i].$1.name,
                      ),
                      label: segments[i].$2,
                      selected: selected == segments[i].$1,
                      onTap: () => onChanged(segments[i].$1),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectoryTypeSegment extends StatelessWidget {
  const _DirectoryTypeSegment({
    required super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    return Material(
      color: selected
          ? tokens.primary.withValues(alpha: 0.12)
          : tokens.surfacePearl,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.vwFinePrint.copyWith(
              color: selected ? tokens.primary : tokens.inkMuted80,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectoryGrid extends StatelessWidget {
  const _DirectoryGrid({
    required this.directories,
    required this.onOpenDetailPage,
  });

  final List<AiDirectoryConclusion> directories;
  final void Function({String? directoryPath}) onOpenDetailPage;

  @override
  Widget build(BuildContext context) {
    if (directories.isEmpty) {
      return Text(context.l10n.aiResultsNoMatches, style: context.vwCaption);
    }
    return GridView.builder(
      key: AiAnalysisWorkspaceKeys.directoryGridKey,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: directories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppleSpacing.sm,
        mainAxisSpacing: AppleSpacing.sm,
        mainAxisExtent: 112,
      ),
      itemBuilder: (context, index) {
        return _DirectoryConclusionCard(
          directory: directories[index],
          onTap: () => onOpenDetailPage(directoryPath: directories[index].path),
        );
      },
    );
  }
}

class _DirectoryConclusionCard extends StatelessWidget {
  const _DirectoryConclusionCard({
    required this.directory,
    required this.onTap,
  });

  final AiDirectoryConclusion directory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.volward;
    return Material(
      key: AiAnalysisWorkspaceKeys.directoryCardKey(directory.path),
      color: tokens.surfacePearl,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        side: BorderSide(color: tokens.hairline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppleSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                directory.displayLabel,
                style: context.vwBodyStrong,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppleSpacing.xxs),
              Expanded(
                child: Text(
                  l10n.aiConclusionsDirectoryMetrics(
                    AiAnalysisOverviewView._formatBytes(directory.safeBytes),
                    directory.reviewCount,
                    directory.shareOfSafePct.toStringAsFixed(0),
                  ),
                  style: context.vwCaption,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NarrativeSection extends StatelessWidget {
  const _NarrativeSection({
    required this.narrative,
    required this.overview,
    required this.groups,
    required this.canGenerate,
    required this.showCreditHint,
    required this.onGenerate,
  });

  final AiWorkspaceNarrativeState narrative;
  final AiAnalysisConclusionOverview overview;
  final List<AiResultGroup> groups;
  final bool canGenerate;
  final bool showCreditHint;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    if (!narrative.enabled) return const SizedBox.shrink();
    final l10n = context.l10n;
    final hash = conclusionContentHash(
      overview,
      groups.expand((group) => group.items),
    );
    if (narrative.text != null && narrative.signature == hash) {
      return Padding(
        padding: const EdgeInsets.only(top: AppleSpacing.xs),
        child: Text(
          narrative.text!,
          key: AiAnalysisWorkspaceKeys.conclusionNarrativeKey,
          style: context.vwBody,
        ),
      );
    }
    if (narrative.loading) {
      return Padding(
        padding: const EdgeInsets.only(top: AppleSpacing.xs),
        child: Row(
          key: AiAnalysisWorkspaceKeys.conclusionNarrativeLoadingKey,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppleSpacing.xs),
            Text(l10n.aiConclusionNarrativeLoading, style: context.vwCaption),
          ],
        ),
      );
    }
    if (!narrative.auto) {
      return Padding(
        padding: const EdgeInsets.only(top: AppleSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AppleButton(
                key: AiAnalysisWorkspaceKeys.conclusionNarrativeGenerateKey,
                label: l10n.aiConclusionNarrativeGenerate,
                icon: Icons.auto_awesome_outlined,
                variant: AppleButtonVariant.pearl,
                onPressed: canGenerate ? onGenerate : null,
              ),
            ),
            if (showCreditHint) ...[
              const SizedBox(height: AppleSpacing.xxs),
              Text(
                l10n.aiConclusionNarrativePlatformCreditHint,
                style: context.vwCaption,
              ),
            ],
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
