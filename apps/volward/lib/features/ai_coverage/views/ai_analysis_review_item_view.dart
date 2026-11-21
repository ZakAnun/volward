import 'package:flutter/material.dart';

import '../../../ai/ai_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../theme/apple_tokens.dart';
import '../../../theme/volward_tokens.dart';
import '../../../widgets/ai_result_entry_tile.dart';
import '../../../widgets/apple_widgets.dart';
import 'ai_analysis_workspace_view_actions.dart';
import 'ai_analysis_workspace_view_state.dart';

/// Renders one review-queue item from immutable workspace state and typed
/// actions. The checkbox is disabled in review mode; review decisions and
/// disclosure are handled through the actions interface.
class AiAnalysisReviewItemView extends StatelessWidget {
  const AiAnalysisReviewItemView({
    super.key,
    required this.state,
    required this.actions,
    required this.item,
  });

  final AiAnalysisWorkspaceViewState state;
  final AiAnalysisWorkspaceViewActions actions;
  final AiVerdict item;

  @override
  Widget build(BuildContext context) {
    final results = state.results;
    final selected = results.selectedPaths.contains(item.path);
    final decision =
        results.reviewDecisions[item.path] ?? WorkspaceReviewDecision.pending;
    final expanded = results.expandedReviewPaths.contains(item.path);
    final sizeLabel = AiAnalysisReviewItemView.formatBytes(
      results.sizeByPath[item.path] ?? 0,
    );
    final l10n = context.l10n;

    return _ResultRow(
      key: ValueKey<String>('ai-review-queue:${item.path}'),
      item: item,
      sizeLabel: sizeLabel,
      selected: selected,
      reviewDecision: decision,
      onChanged: null,
      onTap: () => actions.toggleReviewExpanded(item.path),
      expanded: expanded,
      onDecisionChanged: (decision) =>
          actions.setReviewDecision(item.path, decision),
      cleanupMeta: _cleanupMetaLabel(context, item),
      cleanupSource: _cleanupSourceLabel(context, item),
      retentionHint: _retentionHintLabel(context, item),
      reviewStatusLabel: _reviewStatusLabel(l10n, decision),
    );
  }

  static String formatBytes(num? bytes) {
    if (bytes == null) return '-';
    final value = bytes.toInt();
    if (value < 1024) return '$value B';
    if (value < 1048576) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1073741824) {
      return '${(value / 1048576).toStringAsFixed(1)} MB';
    }
    return '${(value / 1073741824).toStringAsFixed(2)} GB';
  }

  static String _reviewStatusLabel(
    AppLocalizations l10n,
    WorkspaceReviewDecision decision,
  ) {
    return switch (decision) {
      WorkspaceReviewDecision.pending => l10n.aiResultsNeedsYourDecision,
      WorkspaceReviewDecision.include => l10n.aiResultsAddedToCleanup,
      WorkspaceReviewDecision.keep => l10n.aiResultsKeptOutOfCleanup,
    };
  }

  static String? _cleanupMetaLabel(BuildContext context, AiVerdict item) {
    final parts = <String>[
      if (_cleanupSourceLabel(context, item) case final source?) source,
      if (_retentionHintLabel(context, item) case final retention?) retention,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String? _cleanupSourceLabel(BuildContext context, AiVerdict item) {
    final source = item.cleanupSource;
    if (source == null || source.isEmpty) return null;
    final l10n = context.l10n;
    return switch (source) {
      'ai_tool_cache' => l10n.aiCleanupSourceAiToolCache,
      'ai_generated_output' => l10n.aiCleanupSourceAiGeneratedOutput,
      'system_temp' => l10n.aiCleanupSourceSystemTemp,
      _ => source,
    };
  }

  static String? _retentionHintLabel(BuildContext context, AiVerdict item) {
    final parts = <String>[
      if (item.retentionDays != null)
        context.l10n.aiCleanupRetentionDays(item.retentionDays!),
      if (item.cleanupHint case final hint? when hint.isNotEmpty) hint,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
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
