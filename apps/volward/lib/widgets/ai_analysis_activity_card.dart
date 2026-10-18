import 'package:flutter/material.dart';

import '../ai/ai_analysis_activity_model.dart';
import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';

enum AiAnalysisActivityCardVariant { expanded, compact }

/// Fixed outer height so active/pending/completed chips align in the row.
const _kSubstageChipOuterHeight = 34.0;
const _kSubstageTrackHeight = 2.0;
const _kSubstageIconSlotWidth = 18.0;

/// Compact circular loader for substage chips and inline captions.
class AiAnalysisActivityInlineSpinner extends StatelessWidget {
  const AiAnalysisActivityInlineSpinner({
    super.key,
    required this.color,
    this.size = 12,
    this.strokeWidth = 2,
    this.animating = true,
  });

  final Color color;
  final double size;
  final double strokeWidth;
  final bool animating;

  @override
  Widget build(BuildContext context) {
    if (!animating) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: 0.55),
            width: strokeWidth,
          ),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

/// Unified in-progress analysis surface (design spec §3).
class AiAnalysisActivityCard extends StatelessWidget {
  const AiAnalysisActivityCard({
    super.key,
    required this.variant,
    required this.model,
    this.substageLabel,
    this.freezeActiveMotion = false,
  });

  final AiAnalysisActivityCardVariant variant;
  final AiAnalysisActivityModel model;

  /// Chip captions; defaults to [AiActivitySubstage.name] when null.
  final String Function(AiActivitySubstage stage)? substageLabel;

  /// When true, the active substage chip keeps the same footprint without pulse.
  final bool freezeActiveMotion;

  String _labelFor(AiActivitySubstage stage) =>
      substageLabel?.call(stage) ?? stage.name;

  @override
  Widget build(BuildContext context) {
    return switch (variant) {
      AiAnalysisActivityCardVariant.expanded => _ExpandedActivityCard(
        model: model,
        substageLabel: _labelFor,
        freezeActiveMotion: freezeActiveMotion,
      ),
      AiAnalysisActivityCardVariant.compact => _CompactActivityCard(
        model: model,
        substageLabel: _labelFor,
        freezeActiveMotion: freezeActiveMotion,
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
    this.freezeActiveMotion = false,
  });

  static const double _maxHeight = 72;
  static const double _barHeight = 3;

  final AiAnalysisActivityModel model;
  final String Function(AiActivitySubstage stage) substageLabel;
  final bool freezeActiveMotion;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    final progress = model.progress;
    final barValue = freezeActiveMotion
        ? (progress ?? 0.0).clamp(0.0, 1.0)
        : progress?.clamp(0.0, 1.0);
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
                    value: barValue,
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
    this.freezeActiveMotion = false,
  });

  final AiAnalysisActivityModel model;
  final String Function(AiActivitySubstage stage) substageLabel;
  final bool freezeActiveMotion;

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

    final subtitlePart = model.subtitle.trim().isEmpty
        ? ''
        : '${model.subtitle}, ';
    final semanticsLabel =
        '${model.title}, $subtitlePart'
        'stage $stageOrdinal of $stageCount, $semanticsProgress';

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
                  freezeActiveMotion: freezeActiveMotion,
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
                _ActivityProgressBar(
                  progress: progress,
                  tokens: tokens,
                  freezeActiveMotion: freezeActiveMotion,
                ),
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
    this.freezeActiveMotion = false,
  });

  final List<AiActivitySubstage> visibleSubstages;
  final AiActivitySubstage activeSubstage;
  final Set<AiActivitySubstage> completedSubstages;
  final String Function(AiActivitySubstage stage) substageLabel;
  final bool freezeActiveMotion;

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
              freezeActiveMotion: freezeActiveMotion,
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

class _SubstageChipLeading extends StatelessWidget {
  const _SubstageChipLeading({
    required this.state,
    required this.foreground,
    required this.freezeActiveMotion,
    required this.reduceMotion,
  });

  final _SubstageChipState state;
  final Color foreground;
  final bool freezeActiveMotion;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      _SubstageChipState.completed => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 14, color: foreground),
          const SizedBox(width: 4),
        ],
      ),
      _SubstageChipState.active => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: AiAnalysisActivityInlineSpinner(
          color: foreground,
          size: 12,
          strokeWidth: 1.75,
          animating: !reduceMotion && !freezeActiveMotion,
        ),
      ),
      _SubstageChipState.pending => const SizedBox.shrink(),
    };
  }
}

class _SubstageChip extends StatelessWidget {
  const _SubstageChip({
    required this.label,
    required this.state,
    this.freezeActiveMotion = false,
  });

  final String label;
  final _SubstageChipState state;
  final bool freezeActiveMotion;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final showTrackPulse =
        state == _SubstageChipState.active &&
        !reduceMotion &&
        !freezeActiveMotion;

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
      child: SizedBox(
        height: _kSubstageChipOuterHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
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
                  SizedBox(
                    width: _kSubstageIconSlotWidth,
                    child: _SubstageChipLeading(
                      state: state,
                      foreground: fg,
                      freezeActiveMotion: freezeActiveMotion,
                      reduceMotion: reduceMotion,
                    ),
                  ),
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
            const SizedBox(height: 2),
            SizedBox(
              height: _kSubstageTrackHeight,
              child: showTrackPulse
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(1),
                      child: LinearProgressIndicator(
                        minHeight: _kSubstageTrackHeight,
                        backgroundColor: tokens.primary.withValues(alpha: 0.25),
                        color: tokens.onPrimary,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityProgressBar extends StatelessWidget {
  const _ActivityProgressBar({
    required this.progress,
    required this.tokens,
    this.freezeActiveMotion = false,
  });

  final double? progress;
  final VolwardTokens tokens;
  final bool freezeActiveMotion;

  @override
  Widget build(BuildContext context) {
    const minHeight = 5.0;
    final value = freezeActiveMotion
        ? (progress ?? 0.0).clamp(0.0, 1.0)
        : progress?.clamp(0.0, 1.0);
    if (value != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(minHeight),
        child: LinearProgressIndicator(
          value: value,
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
