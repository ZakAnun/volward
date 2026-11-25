import 'package:flutter/material.dart';

import '../../../ai/coverage_client_logic.dart';
import '../../../ai/coverage_job_state.dart';
import '../../../widgets/coverage_job_banner.dart';
import 'ai_analysis_workspace_view_state.dart';

/// Renders the coverage job progress banner from an immutable snapshot.
///
/// Button availability is derived here from [AiWorkspaceCoverageBannerState.job]
/// so the page controller supplies raw actions rather than presentation logic.
class AiAnalysisCoverageBannerView extends StatelessWidget {
  const AiAnalysisCoverageBannerView({
    super.key,
    required this.state,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onRaiseBudget,
    required this.onRestart,
  });

  final AiWorkspaceCoverageBannerState state;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onRaiseBudget;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final job = state.job;
    final isRunning = job.status == CoverageJobStatus.running;
    final isPaused = job.status == CoverageJobStatus.paused;
    final isBudgetPaused =
        isPaused && job.pauseReason == CoveragePauseReason.budget;
    final needsClientLogicUpgrade = coverageJobNeedsClientLogicUpgrade(job);

    return CoverageJobBanner(
      state: job,
      verdictRows: state.verdictRows,
      planSummary: state.planSummary,
      showPausedBeforeProgressNotice: state.showPausedBeforeProgressNotice,
      billingModeMismatch: state.billingModeMismatch,
      billingModeMismatchMessage: state.billingModeMismatchMessage,
      onPause: isRunning ? onPause : null,
      onResume: isPaused && !state.billingModeMismatch ? onResume : null,
      onCancel: (isRunning || isPaused) ? onCancel : null,
      onRaiseBudget: isBudgetPaused ? onRaiseBudget : null,
      onRestart: needsClientLogicUpgrade || state.billingModeMismatch
          ? onRestart
          : null,
    );
  }
}
