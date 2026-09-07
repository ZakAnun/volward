import 'package:flutter/material.dart';

import '../ai/coverage_job_state.dart';
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
    final isRunning = state.status == CoverageJobStatus.running;
    final isPaused = state.status == CoverageJobStatus.paused;
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
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.aiCoverageProgress(
                  state.analyzedFiles,
                  state.totalUnclassified,
                ),
                style: context.vwBodyStrong,
              ),
            ),
            if (isRunning || isPaused) ...[
              const SizedBox(width: AppleSpacing.sm),
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
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
