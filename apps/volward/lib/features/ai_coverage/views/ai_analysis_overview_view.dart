import 'package:flutter/material.dart';

import '../../../ai/ai_conclusion_synthesis.dart';
import '../../../ai/ai_result_overview.dart';
import '../../../ai/ai_result_groups.dart';
import '../../../ai/coverage_ui_helpers.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/generated/app_localizations.dart';
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
    this.showClassificationProvenance = true,
    required this.emptyState,
    required this.onOpenDetailList,
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
  final bool showClassificationProvenance;
  final Widget emptyState;
  final void Function(WorkspaceResultFilter filter, {String? directoryPath})
  onOpenDetailList;
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
        if (hasVerdicts && showClassificationProvenance) ...[
          _ClassificationProvenanceSection(
            provenance: state.results.classificationProvenance,
          ),
          const SizedBox(height: AppleSpacing.xxs),
        ],
        const SizedBox(height: AppleSpacing.sm),
        Opacity(
          opacity: staleUpdating ? 0.55 : 1,
          child: _AiCleanupDashboardSummary(
            overview: overview,
            shareRoot: shareRoot,
            placeholder: !hasVerdicts,
            analyzing: analyzing,
            safeCount: safeCount,
            coverageRun: state.results.coverageRunPresentation,
            onOpenDetailList: onOpenDetailList,
            onOpenReviewQueue: onOpenReviewQueue,
          ),
        ),
        if (state.results.loadedEmptySuggestions && !hasVerdicts) ...[
          const SizedBox(height: AppleSpacing.sm),
          emptyState,
        ],
        if (hasVerdicts) ...[
          const SizedBox(height: AppleSpacing.sm),
          Text(l10n.aiConclusionsLead, style: context.vwBody),
          if (!analyzing)
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
            filter: _resultFilterForDirectoryType(
              state.results.directoryTypeFilter,
            ),
            onOpenDetailList: onOpenDetailList,
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

  static WorkspaceResultFilter _resultFilterForDirectoryType(
    WorkspaceDirectoryTypeFilter filter,
  ) {
    return switch (filter) {
      WorkspaceDirectoryTypeFilter.safe => WorkspaceResultFilter.safeToRemove,
      WorkspaceDirectoryTypeFilter.review => WorkspaceResultFilter.review,
      WorkspaceDirectoryTypeFilter.keep => WorkspaceResultFilter.keep,
    };
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

class _ClassificationProvenanceSection extends StatelessWidget {
  const _ClassificationProvenanceSection({required this.provenance});

  final ClassificationProvenanceSummary provenance;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final presentation = buildClassificationProgressPresentation(provenance);
    final localPlanned = provenance.localPlannedCount;
    final localFraction = localPlanned == null || localPlanned <= 0
        ? null
        : (provenance.localRuleCount / localPlanned).clamp(0, 1).toDouble();
    final localComplete =
        provenance.localPhaseComplete ||
        (localFraction != null && localFraction >= 1);
    final localRunning = provenance.localPhase == CoverageLocalPhase.running;
    final aiStatusLine = localComplete
        ? _aiStatusLine(l10n, provenance)
        : l10n.aiClassificationAiWaitingForLocal;
    return Column(
      key: AiAnalysisWorkspaceKeys.classificationProvenanceKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppleSpacing.sm,
          runSpacing: AppleSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ClassificationMetric(
              key: AiAnalysisWorkspaceKeys.classificationBootstrapKey,
              icon: Icons.shield_outlined,
              value: '${provenance.bootstrapLocalCount}',
              label: l10n.aiClassificationBootstrapLocal(
                provenance.bootstrapLocalCount,
              ),
            ),
            _ClassificationMetric(
              key: AiAnalysisWorkspaceKeys.classificationLocalRulesKey,
              icon: localRunning ? Icons.autorenew : Icons.rule_folder_outlined,
              value: '${provenance.localRuleCount}',
              label: l10n.aiClassificationCoverageLocal(
                provenance.localRuleCount,
              ),
              color: localRunning ? AppleColors.primary : null,
            ),
            if (localRunning)
              Semantics(
                label: l10n.aiClassificationLocalRulesProgress(
                  ((localFraction ?? 0) * 100).round(),
                ),
                child: const SizedBox(
                  key: AiAnalysisWorkspaceKeys.classificationLocalLoadingKey,
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            _ClassificationMetric(
              key: AiAnalysisWorkspaceKeys.classificationAiMetricKey,
              icon: Icons.auto_awesome_outlined,
              value: _aiMetricValue(provenance),
              label: aiStatusLine,
              color: _statusColor(provenance.phase),
            ),
            Tooltip(
              message: aiStatusLine,
              child: Semantics(
                label: aiStatusLine,
                child: Icon(
                  _statusIcon(
                    localComplete
                        ? provenance.phase
                        : ClassificationAiPhase.notStarted,
                  ),
                  key: AiAnalysisWorkspaceKeys.classificationAiStatusKey,
                  color: _statusColor(
                    localComplete
                        ? provenance.phase
                        : ClassificationAiPhase.notStarted,
                  ),
                  size: 18,
                ),
              ),
            ),
          ],
        ),
        if (localFraction != null) ...[
          const SizedBox(height: AppleSpacing.xxs),
          Row(
            key: AiAnalysisWorkspaceKeys.classificationLocalProgressKey,
            children: [
              Text(
                l10n.aiClassificationLocalRulesProgress(
                  (localFraction * 100).round(),
                ),
                style: context.vwCaption,
              ),
              const SizedBox(width: AppleSpacing.xs),
              Expanded(
                child: LinearProgressIndicator(
                  value: localFraction,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(AppleRadius.pill),
                  color: localComplete
                      ? Colors.green.shade700
                      : AppleColors.primary,
                  backgroundColor: AppleColors.dividerSoft,
                ),
              ),
            ],
          ),
        ] else if (!localComplete) ...[
          const SizedBox(height: AppleSpacing.xxs),
          Text(
            l10n.aiClassificationLocalRulesPreparing,
            key: AiAnalysisWorkspaceKeys.classificationLocalPreparingKey,
            style: context.vwCaption,
          ),
        ],
        if (presentation.showsAiProgress && localComplete) ...[
          const SizedBox(height: AppleSpacing.xxs),
          Row(
            key: AiAnalysisWorkspaceKeys.classificationAiProgressKey,
            children: [
              Text(
                '${presentation.progressPercent}%',
                style: context.vwCaption,
              ),
              const SizedBox(width: AppleSpacing.xs),
              Expanded(
                child: Semantics(
                  label: _aiStatusLine(l10n, provenance),
                  value: '${presentation.progressPercent}%',
                  child: LinearProgressIndicator(
                    value: presentation.progressFraction,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(AppleRadius.pill),
                    color: _statusColor(provenance.phase),
                    backgroundColor: AppleColors.dividerSoft,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _aiMetricValue(ClassificationProvenanceSummary provenance) {
    final planned = provenance.aiPlannedCount;
    return planned == null || planned <= 0
        ? '${provenance.aiResolvedCount}'
        : '${provenance.aiResolvedCount} / $planned';
  }

  IconData _statusIcon(ClassificationAiPhase phase) => switch (phase) {
    ClassificationAiPhase.notStarted => Icons.pending_outlined,
    ClassificationAiPhase.running => Icons.autorenew,
    ClassificationAiPhase.completed => Icons.check_circle_outline,
    ClassificationAiPhase.paused => Icons.pause_circle_outline,
    ClassificationAiPhase.failed => Icons.error_outline,
    ClassificationAiPhase.notRequired => Icons.offline_bolt_outlined,
  };

  Color _statusColor(ClassificationAiPhase phase) => switch (phase) {
    ClassificationAiPhase.running => AppleColors.primary,
    ClassificationAiPhase.completed ||
    ClassificationAiPhase.notRequired => Colors.green.shade700,
    ClassificationAiPhase.paused => Colors.orange.shade800,
    ClassificationAiPhase.failed => Colors.red.shade700,
    ClassificationAiPhase.notStarted => AppleColors.inkMuted48,
  };

  String _aiStatusLine(
    AppLocalizations l10n,
    ClassificationProvenanceSummary provenance,
  ) {
    return switch (provenance.phase) {
      ClassificationAiPhase.notStarted => l10n.aiClassificationAiNotStarted,
      ClassificationAiPhase.running when provenance.aiPlannedCount != null =>
        l10n.aiClassificationAiRunningKnown(
          provenance.aiResolvedCount,
          provenance.aiPlannedCount!,
        ),
      ClassificationAiPhase.running => l10n.aiClassificationAiRunningUnknown(
        provenance.aiResolvedCount,
      ),
      ClassificationAiPhase.completed when provenance.aiPlannedCount != null =>
        l10n.aiClassificationAiCompletedKnown(
          provenance.aiResolvedCount,
          provenance.aiPlannedCount!,
        ),
      ClassificationAiPhase.completed =>
        l10n.aiClassificationAiCompletedUnknown(provenance.aiResolvedCount),
      ClassificationAiPhase.paused => l10n.aiClassificationAiPaused,
      ClassificationAiPhase.failed => l10n.aiClassificationAiFailed,
      ClassificationAiPhase.notRequired => l10n.aiClassificationAiNotRequired,
    };
  }
}

class _ClassificationMetric extends StatelessWidget {
  const _ClassificationMetric({
    required super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final metricColor = color ?? AppleColors.inkMuted48;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: metricColor, size: 18),
            const SizedBox(width: AppleSpacing.xxs),
            Text(value, style: context.vwCaptionStrong),
          ],
        ),
      ),
    );
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

class _AiCleanupDashboardSummary extends StatelessWidget {
  const _AiCleanupDashboardSummary({
    required this.overview,
    required this.shareRoot,
    required this.placeholder,
    required this.analyzing,
    required this.safeCount,
    required this.coverageRun,
    required this.onOpenDetailList,
    required this.onOpenReviewQueue,
  });

  final AiAnalysisConclusionOverview overview;
  final String shareRoot;
  final bool placeholder;
  final bool analyzing;
  final int safeCount;
  final CoverageRunPresentation coverageRun;
  final void Function(WorkspaceResultFilter filter, {String? directoryPath})
  onOpenDetailList;
  final VoidCallback onOpenReviewQueue;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    final fraction = overview.shareOfRootPct == null
        ? null
        : (overview.shareOfRootPct! / 100).clamp(0, 1).toDouble();
    return KeyedSubtree(
      key: AiAnalysisWorkspaceKeys.cleanupDashboardKey,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfacePearl,
          borderRadius: BorderRadius.circular(AppleRadius.md),
          border: Border.all(color: tokens.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppleSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (!placeholder && fraction != null) ...[
                    SizedBox(
                      key: AiAnalysisWorkspaceKeys.cleanupReclaimRingKey,
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: fraction,
                        strokeWidth: 7,
                        backgroundColor: tokens.hairline,
                      ),
                    ),
                    const SizedBox(width: AppleSpacing.sm),
                  ],
                  Expanded(
                    child: _ResultsHero(
                      overview: overview,
                      shareRoot: shareRoot,
                      placeholder: placeholder,
                      analyzing: analyzing,
                    ),
                  ),
                ],
              ),
              if (coverageRun.localPhase == CoverageLocalPhase.running) ...[
                const SizedBox(height: AppleSpacing.xs),
                _LocalCoverageProgress(
                  resolved: coverageRun.localResolvedFiles,
                  planned: coverageRun.localPlannedFiles,
                  fraction: coverageRun.localProgressFraction,
                ),
              ],
              const SizedBox(height: AppleSpacing.sm),
              _ResultsMetricCards(
                overview: overview,
                placeholder: placeholder,
                safeCount: safeCount,
                onOpenDetailList: onOpenDetailList,
                onOpenReviewQueue: onOpenReviewQueue,
              ),
              if (!placeholder) ...[
                const SizedBox(height: AppleSpacing.sm),
                Text(
                  context.l10n.aiConclusionsScanLine(
                    overview.targetLabel,
                    overview.analyzedItemCount,
                    AiAnalysisOverviewView._formatBytes(
                      overview.analyzedTotalBytes,
                    ),
                  ),
                  style: context.vwCaption,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalCoverageProgress extends StatelessWidget {
  const _LocalCoverageProgress({
    required this.resolved,
    required this.planned,
    required this.fraction,
  });

  final int resolved;
  final int? planned;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final detail = planned == null
        ? l10n.aiAnalysisStageLocalPreparing
        : l10n.aiAnalysisStageLocalProgress(resolved, planned!);
    return Semantics(
      label: detail,
      child: Column(
        key: AiAnalysisWorkspaceKeys.cleanupLocalProgressKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppleSpacing.xs),
              Expanded(child: Text(detail, style: context.vwCaption)),
            ],
          ),
          if (fraction case final value?) ...[
            const SizedBox(height: AppleSpacing.xxs),
            LinearProgressIndicator(
              value: value,
              minHeight: 4,
              borderRadius: BorderRadius.circular(AppleRadius.pill),
              color: AppleColors.primary,
              backgroundColor: AppleColors.dividerSoft,
            ),
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
    required this.onOpenDetailList,
    required this.onOpenReviewQueue,
  });

  final AiAnalysisConclusionOverview overview;
  final bool placeholder;
  final int safeCount;
  final void Function(WorkspaceResultFilter filter, {String? directoryPath})
  onOpenDetailList;
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
        subtitle: placeholder
            ? dash
            : _safeMetricSubtitle(l10n, overview, safeCount),
        onTap: placeholder
            ? null
            : () => onOpenDetailList(WorkspaceResultFilter.safeToRemove),
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
        subtitle: placeholder ? dash : _keepSourceLabel(l10n, overview),
        onTap: placeholder
            ? null
            : () => onOpenDetailList(WorkspaceResultFilter.keep),
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

  static String _safeMetricSubtitle(
    AppLocalizations l10n,
    AiAnalysisConclusionOverview overview,
    int safeCount,
  ) {
    final count = l10n.aiResultsMetricCountLine(safeCount);
    final source = _safeSourceLabel(l10n, overview);
    return source == null ? count : '$count · $source';
  }

  static String? _safeSourceLabel(
    AppLocalizations l10n,
    AiAnalysisConclusionOverview overview,
  ) {
    final hasLocal = overview.localSafeCount > 0;
    final hasAi = overview.aiSafeCount > 0;
    if (hasLocal && hasAi) return l10n.aiResultsMetricSafeCombinedSubtitle;
    if (hasLocal) return l10n.aiResultsMetricSafeLocalSubtitle;
    if (hasAi) return l10n.aiResultsMetricSafeAiSubtitle;
    return null;
  }

  static String _keepSourceLabel(
    AppLocalizations l10n,
    AiAnalysisConclusionOverview overview,
  ) {
    final hasLocal = overview.localKeepCount > 0;
    final hasAi = overview.aiKeepCount > 0;
    if (hasLocal && hasAi) return l10n.aiResultsMetricKeepCombinedSubtitle;
    if (hasLocal) return l10n.aiResultsMetricKeepLocalSubtitle;
    if (hasAi) return l10n.aiResultsMetricKeepAiSubtitle;
    return l10n.aiResultsMetricKeepUnknownSubtitle;
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
    required this.filter,
    required this.onOpenDetailList,
  });

  final List<AiDirectoryConclusion> directories;
  final WorkspaceResultFilter filter;
  final void Function(WorkspaceResultFilter filter, {String? directoryPath})
  onOpenDetailList;

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
          onTap: () =>
              onOpenDetailList(filter, directoryPath: directories[index].path),
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
    final l10n = context.l10n;
    if (!narrative.enabled) {
      return Padding(
        padding: const EdgeInsets.only(top: AppleSpacing.xs),
        child: Text(
          l10n.aiConclusionNarrativeDisabled,
          key: AiAnalysisWorkspaceKeys.conclusionNarrativeUnavailableKey,
          style: context.vwCaption,
        ),
      );
    }
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
    return Padding(
      padding: const EdgeInsets.only(top: AppleSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.aiConclusionNarrativeUnavailable,
            key: AiAnalysisWorkspaceKeys.conclusionNarrativeUnavailableKey,
            style: context.vwCaption,
          ),
          const SizedBox(height: AppleSpacing.xs),
          AppleButton(
            key: AiAnalysisWorkspaceKeys.conclusionNarrativeGenerateKey,
            label: l10n.aiConclusionNarrativeGenerate,
            icon: Icons.auto_awesome_outlined,
            variant: AppleButtonVariant.pearl,
            onPressed: canGenerate ? onGenerate : null,
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
}
