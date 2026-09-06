import 'package:flutter/material.dart';

import '../ai/coverage_job_state.dart';
import '../ai/coverage_ui_helpers.dart';
import '../ai/coverage_verdict_store.dart';
import '../l10n/l10n.dart';
import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';
import 'apple_widgets.dart';

/// Coverage job progress banner (Design §9).
class CoverageJobBanner extends StatelessWidget {
  const CoverageJobBanner({
    super.key,
    required this.state,
    required this.verdictRows,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onRaiseBudget,
  });

  final CoverageJobState state;
  final List<CoverageVerdict> verdictRows;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onRaiseBudget;

  @override
  Widget build(BuildContext context) {
    if (state.status == CoverageJobStatus.idle ||
        state.status == CoverageJobStatus.cancelled) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final tokens = context.volward;
    final isRunning = state.status == CoverageJobStatus.running;
    final isPaused = state.status == CoverageJobStatus.paused;
    final isCompleted = state.status == CoverageJobStatus.completed;
    final pending = (state.totalUnclassified - state.analyzedFiles).clamp(
      0,
      state.totalUnclassified,
    );
    final sourceStats = computeCoverageSourceStats(
      verdicts: verdictRows,
      preClassifiedCount: state.preClassifiedCount,
    );
    final budgetUsed = state.budgetTokens > 0
        ? state.usedTokens
        : state.usedCredits;
    final budgetLimit = state.budgetTokens > 0
        ? state.budgetTokens
        : state.budgetCredits;
    final budgetPaused =
        isPaused && state.pauseReason == CoveragePauseReason.budget;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppleSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.aiCoverageProgress(
                state.analyzedFiles,
                state.totalUnclassified,
              ),
              style: context.vwBodyStrong,
            ),
            if (pending > 0 && !isCompleted) ...[
              const SizedBox(height: AppleSpacing.xs),
              Text(
                l10n.aiCoverageUnanalyzedCount(pending),
                style: AppleTypography.caption.copyWith(color: tokens.warning),
              ),
            ],
            if (!sourceStats.isEmpty) ...[
              const SizedBox(height: AppleSpacing.xs),
              Text(
                l10n.aiCoverageSourceStats(
                  sourceStats.fileVerdicts,
                  sourceStats.groupVerdicts,
                  sourceStats.localPreClassified,
                ),
                style: context.vwCaption,
              ),
            ],
            if (budgetPaused) ...[
              const SizedBox(height: AppleSpacing.xs),
              Text(
                l10n.aiCoverageBudgetPaused(budgetUsed, budgetLimit),
                style: AppleTypography.caption.copyWith(color: tokens.warning),
              ),
            ],
            if (isCompleted) ...[
              const SizedBox(height: AppleSpacing.xs),
              Text(l10n.aiCoverageCompletedNotice, style: context.vwCaption),
            ],
            if (isRunning || isPaused) ...[
              const SizedBox(height: AppleSpacing.sm),
              Wrap(
                spacing: AppleSpacing.sm,
                runSpacing: AppleSpacing.sm,
                children: [
                  if (isRunning && onPause != null)
                    AppleButton(
                      label: l10n.aiCoveragePause,
                      icon: Icons.pause_outlined,
                      variant: AppleButtonVariant.pearl,
                      onPressed: onPause,
                    ),
                  if (isPaused && onResume != null)
                    AppleButton(
                      label: l10n.aiCoverageResume,
                      icon: Icons.play_arrow_outlined,
                      variant: AppleButtonVariant.pearl,
                      onPressed: onResume,
                    ),
                  if (budgetPaused && onRaiseBudget != null)
                    AppleButton(
                      label: l10n.aiCoverageRaiseBudget,
                      icon: Icons.trending_up_outlined,
                      variant: AppleButtonVariant.pearl,
                      onPressed: onRaiseBudget,
                    ),
                  if (onCancel != null)
                    AppleButton(
                      label: l10n.aiCoverageCancel,
                      icon: Icons.stop_outlined,
                      variant: AppleButtonVariant.pearl,
                      onPressed: onCancel,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
