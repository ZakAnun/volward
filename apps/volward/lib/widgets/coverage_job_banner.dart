import 'dart:math';

import 'package:flutter/material.dart';

import '../ai/coverage_analyze_batch.dart';
import '../ai/coverage_client_logic.dart';
import '../ai/coverage_job_state.dart';
import '../ai/coverage_pause_messages.dart';
import '../ai/coverage_verdict_store.dart';
import '../l10n/l10n.dart';
import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';
import 'apple_widgets.dart';

int _estimateRemainingCredits(CoverageJobState state) {
  if (state.planVersion >= 2 && state.estimatedCreditsRemaining != null) {
    return state.estimatedCreditsRemaining!;
  }
  final pending = max(0, state.totalUnclassified - state.analyzedFiles);
  return (pending / 40).ceil();
}

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
    this.onRestart,
  });

  final CoverageJobState state;
  final List<CoverageVerdict> verdictRows;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onRaiseBudget;
  final VoidCallback? onRestart;

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
    final budgetPaused =
        isPaused && state.pauseReason == CoveragePauseReason.budget;
    final failedPaused =
        isPaused && state.pauseReason == CoveragePauseReason.failed;
    final legacyLogic = coverageJobNeedsClientLogicUpgrade(state);
    final incompleteCount = verdictRows
        .where((row) => row.coverageSource == kIncompleteCoverageSource)
        .length;
    final usesCredits = state.budgetCredits > 0;
    final usesTokens = !usesCredits && state.budgetTokens > 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppleSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
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
                  if (isPaused) ...[
                    const SizedBox(height: AppleSpacing.xxs),
                    Text(
                      l10n.aiCoverageRemainingEstimate(
                        _estimateRemainingCredits(state),
                      ),
                      style: context.vwCaption,
                    ),
                  ],
                  if (usesCredits) ...[
                    const SizedBox(height: AppleSpacing.xxs),
                    Text(
                      l10n.aiCoverageBudgetCreditsUsage(
                        state.usedCredits,
                        state.budgetCredits,
                      ),
                      style: context.vwCaption,
                    ),
                  ] else if (usesTokens) ...[
                    const SizedBox(height: AppleSpacing.xxs),
                    Text(
                      l10n.aiCoverageBudgetTokensUsage(
                        state.usedTokens,
                        state.budgetTokens,
                      ),
                      style: context.vwCaption,
                    ),
                  ],
                  if (budgetPaused) ...[
                    const SizedBox(height: AppleSpacing.xxs),
                    Text(
                      usesCredits
                          ? l10n.aiCoverageBudgetPausedCredits(
                              state.usedCredits,
                              state.budgetCredits,
                            )
                          : l10n.aiCoverageBudgetPausedTokens(
                              state.usedTokens,
                              state.budgetTokens,
                            ),
                      style: AppleTypography.caption.copyWith(
                        color: tokens.warning,
                      ),
                    ),
                  ],
                  if (failedPaused && state.failedBatchPaths.isNotEmpty) ...[
                    const SizedBox(height: AppleSpacing.xxs),
                    Text(
                      state.creditsChargedNoVerdict > 0
                          ? l10n.aiCoverageFailedBatchCredits(
                              state.creditsChargedNoVerdict,
                              state.failedBatchPaths.length,
                            )
                          : l10n.aiCoverageFailedBatchItemsOnly(
                              state.failedBatchPaths.length,
                            ),
                      style: AppleTypography.caption.copyWith(
                        color: tokens.warning,
                      ),
                    ),
                    const SizedBox(height: AppleSpacing.xxs),
                    Text(
                      formatFailedBatchPathPreview(
                        l10n,
                        state.failedBatchPaths,
                      ),
                      style: context.vwCaption,
                    ),
                  ],
                  if (incompleteCount > 0) ...[
                    const SizedBox(height: AppleSpacing.xxs),
                    Text(
                      l10n.aiCoverageIncompleteGroupTitle(incompleteCount),
                      style: context.vwCaption,
                    ),
                  ],
                  if (legacyLogic) ...[
                    const SizedBox(height: AppleSpacing.xxs),
                    Text(
                      l10n.aiCoverageLegacyJobHint,
                      style: AppleTypography.caption.copyWith(
                        color: tokens.warning,
                      ),
                    ),
                  ],
                ],
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
                  if (isPaused && onResume != null && !budgetPaused)
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
                  if (legacyLogic && isPaused && onRestart != null)
                    AppleButton(
                      label: l10n.aiCoverageRestartFull,
                      icon: Icons.refresh_outlined,
                      variant: AppleButtonVariant.pearl,
                      onPressed: onRestart,
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
