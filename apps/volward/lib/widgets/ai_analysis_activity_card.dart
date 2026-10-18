import 'package:flutter/material.dart';

import '../ai/ai_analysis_activity_model.dart';
import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';

enum AiAnalysisActivityCardVariant { expanded, compact }

/// Unified in-progress analysis surface (design spec §3).
class AiAnalysisActivityCard extends StatelessWidget {
  const AiAnalysisActivityCard({
    super.key,
    required this.variant,
    required this.model,
    this.substageLabel,
  });

  final AiAnalysisActivityCardVariant variant;
  final AiAnalysisActivityModel model;

  /// Chip captions; defaults to [AiActivitySubstage.name] when null.
  final String Function(AiActivitySubstage stage)? substageLabel;

  String _labelFor(AiActivitySubstage stage) =>
      substageLabel?.call(stage) ?? stage.name;

  @override
  Widget build(BuildContext context) {
    return switch (variant) {
      AiAnalysisActivityCardVariant.expanded => _ExpandedActivityCard(
        model: model,
        substageLabel: _labelFor,
      ),
      AiAnalysisActivityCardVariant.compact => _CompactActivityCard(
        model: model,
        substageLabel: _labelFor,
      ),
    };
  }

  /// Root key of the compact strip (results surface while a job streams in).
  static const compactKey = Key('ai-analysis-activity-compact');
}

/// Single-row summary: active stage pill, caption, optional percent, and a
/// thin progress bar. Height stays within ~56-72dp.
class _CompactActivityCard extends StatelessWidget {
  const _CompactActivityCard({
    required this.model,
    required this.substageLabel,
  });

  static const double _maxHeight = 72;
  static const double _barHeight = 3;

  final AiAnalysisActivityModel model;
  final String Function(AiActivitySubstage stage) substageLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    final progress = model.progress;
    final percent = progress != null
        ? '${(progress.clamp(0.0, 1.0) * 100).round()}%'
        : null;
    final caption = model.progressLabel ?? model.subtitle;
    final stageLabel = substageLabel(model.activeSubstage);

    return Semantics(
      label: percent != null
          ? '${model.title}, $percent'
          : '${model.title}, in progress, no percentage yet',
      liveRegion: true,
      child: DecoratedBox(
        key: AiAnalysisActivityCard.compactKey,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppleSpacing.sm),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: 56,
            maxHeight: _maxHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppleSpacing.md,
              vertical: AppleSpacing.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppleSpacing.sm,
                        vertical: AppleSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.primary,
                        borderRadius: BorderRadius.circular(AppleRadius.pill),
                      ),
                      child: Text(
                        stageLabel,
                        maxLines: 1,
                        style: AppleTypography.finePrint.copyWith(
                          color: tokens.onPrimary,
                          fontWeight: FontWeight.w600,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppleSpacing.sm),
                    Expanded(
                      child: Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.vwCaption,
                      ),
                    ),
                    if (percent != null) ...[
                      const SizedBox(width: AppleSpacing.sm),
                      Text(percent, style: context.vwCaptionStrong),
                    ],
                  ],
                ),
                const SizedBox(height: AppleSpacing.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(_barHeight),
                  child: LinearProgressIndicator(
                    value: progress?.clamp(0.0, 1.0),
                    minHeight: _barHeight,
                    backgroundColor: tokens.inkMuted48.withValues(alpha: 0.35),
                    color: tokens.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandedActivityCard extends StatelessWidget {
  const _ExpandedActivityCard({
    required this.model,
    required this.substageLabel,
  });

  final AiAnalysisActivityModel model;
  final String Function(AiActivitySubstage stage) substageLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    final visible = model.visibleSubstages;
    final activeIndex = visible.indexOf(model.activeSubstage);
    final stageOrdinal = activeIndex >= 0 ? activeIndex + 1 : 1;
    final stageCount = visible.isEmpty ? 1 : visible.length;

    final progress = model.progress;
    final semanticsProgress = progress != null
        ? '${(progress.clamp(0.0, 1.0) * 100).round()}%'
        : 'In progress, no percentage yet';

    final semanticsLabel =
        '${model.title}, stage $stageOrdinal of $stageCount, $semanticsProgress';

    return Semantics(
      label: semanticsLabel,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppleSpacing.sm),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 200),
          child: Padding(
            padding: const EdgeInsets.all(AppleSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _SubstageChipRow(
                  visibleSubstages: visible,
                  activeSubstage: model.activeSubstage,
                  completedSubstages: model.completedSubstages,
                  substageLabel: substageLabel,
                ),
                const SizedBox(height: AppleSpacing.md),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                const SizedBox(height: AppleSpacing.md),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: Column(
                    key: ValueKey(
                      '${model.activeSubstage.name}|${model.title}|${model.subtitle}',
                    ),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(model.title, style: context.vwBodyStrong),
                      const SizedBox(height: AppleSpacing.xxs),
                      Text(model.subtitle, style: context.vwCaption),
                    ],
                  ),
                ),
                const SizedBox(height: AppleSpacing.md),
                _ActivityProgressBar(progress: progress, tokens: tokens),
                if (model.progressLabel != null || progress != null) ...[
                  const SizedBox(height: AppleSpacing.xs),
                  Row(
                    children: [
                      if (model.progressLabel case final label?)
                        Expanded(child: Text(label, style: context.vwCaption)),
                      if (progress != null)
                        Text(
                          '${(progress.clamp(0.0, 1.0) * 100).round()}%',
                          style: context.vwCaptionStrong,
                        ),
                    ],
                  ),
                ],
                if (model.metrics.isNotEmpty) ...[
                  const SizedBox(height: AppleSpacing.sm),
                  Wrap(
                    spacing: AppleSpacing.xs,
                    runSpacing: AppleSpacing.xs,
                    children: [
                      for (final metric in model.metrics)
                        _MetricPill(metric: metric),
                    ],
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

class _SubstageChipRow extends StatelessWidget {
  const _SubstageChipRow({
    required this.visibleSubstages,
    required this.activeSubstage,
    required this.completedSubstages,
    required this.substageLabel,
  });

  final List<AiActivitySubstage> visibleSubstages;
  final AiActivitySubstage activeSubstage;
  final Set<AiActivitySubstage> completedSubstages;
  final String Function(AiActivitySubstage stage) substageLabel;

  @override
  Widget build(BuildContext context) {
    if (visibleSubstages.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < visibleSubstages.length; i++) ...[
            if (i > 0) const SizedBox(width: AppleSpacing.xs),
            _SubstageChip(
              label: substageLabel(visibleSubstages[i]),
              state: _chipState(visibleSubstages[i]),
            ),
          ],
        ],
      ),
    );
  }

  _SubstageChipState _chipState(AiActivitySubstage stage) {
    if (stage == activeSubstage) {
      return _SubstageChipState.active;
    }
    if (completedSubstages.contains(stage)) {
      return _SubstageChipState.completed;
    }
    return _SubstageChipState.pending;
  }
}

enum _SubstageChipState { pending, active, completed }

class _SubstageChip extends StatelessWidget {
  const _SubstageChip({required this.label, required this.state});

  final String label;
  final _SubstageChipState state;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final showPulse = state == _SubstageChipState.active && !reduceMotion;

    final Color bg;
    final Color border;
    final Color fg;
    switch (state) {
      case _SubstageChipState.active:
        bg = tokens.primary;
        border = tokens.primary;
        fg = tokens.onPrimary;
      case _SubstageChipState.completed:
        bg = Colors.transparent;
        border = tokens.primary;
        fg = tokens.primary;
      case _SubstageChipState.pending:
        bg = Colors.transparent;
        border = tokens.inkMuted48;
        fg = tokens.inkMuted80;
    }

    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppleSpacing.sm,
              vertical: AppleSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppleRadius.pill),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state == _SubstageChipState.completed) ...[
                  Icon(Icons.check_rounded, size: 14, color: fg),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: AppleTypography.finePrint.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          if (showPulse)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(1),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: tokens.primary.withValues(alpha: 0.25),
                  color: tokens.onPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityProgressBar extends StatelessWidget {
  const _ActivityProgressBar({required this.progress, required this.tokens});

  final double? progress;
  final VolwardTokens tokens;

  @override
  Widget build(BuildContext context) {
    const minHeight = 5.0;
    if (progress != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(minHeight),
        child: LinearProgressIndicator(
          value: progress!.clamp(0.0, 1.0),
          minHeight: minHeight,
          backgroundColor: tokens.inkMuted48.withValues(alpha: 0.35),
          color: tokens.primary,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(minHeight),
      child: LinearProgressIndicator(
        minHeight: minHeight,
        backgroundColor: tokens.inkMuted48.withValues(alpha: 0.35),
        color: tokens.primary,
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.metric});

  final AiActivityMetric metric;

  @override
  Widget build(BuildContext context) {
    final text = metric.value.isEmpty
        ? metric.label
        : '${metric.label} ${metric.value}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppleRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppleSpacing.sm,
          vertical: AppleSpacing.xxs,
        ),
        child: Text(text, style: context.vwFinePrint),
      ),
    );
  }
}
