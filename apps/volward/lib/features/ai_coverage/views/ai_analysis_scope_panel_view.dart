import 'package:flutter/material.dart';

import '../../../ai/coverage_ui_helpers.dart';
import '../../../theme/apple_tokens.dart';
import 'ai_analysis_coverage_banner_view.dart';
import 'ai_analysis_precheck_view.dart';
import 'ai_analysis_workspace_view_actions.dart';
import 'ai_analysis_workspace_view_state.dart';

/// Renders the expanded scope panel: optional coverage banner plus precheck,
/// purchase and budget content.
class AiAnalysisScopePanelView extends StatelessWidget {
  const AiAnalysisScopePanelView({
    super.key,
    required this.precheck,
    required this.coverage,
    required this.runPresentation,
    required this.actions,
    required this.onOpenSettings,
    required this.banner,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onRaiseBudget,
    required this.onRestart,
  });

  final AiWorkspacePrecheckState precheck;
  final AiWorkspaceCoverageState coverage;
  final CoverageRunPresentation runPresentation;
  final AiAnalysisWorkspaceViewActions actions;
  final VoidCallback onOpenSettings;
  final AiWorkspaceCoverageBannerState? banner;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onRaiseBudget;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (banner case final bannerState?) ...[
          AiAnalysisCoverageBannerView(
            state: bannerState,
            onPause: onPause,
            onResume: onResume,
            onCancel: onCancel,
            onRaiseBudget: onRaiseBudget,
            onRestart: onRestart,
          ),
          const SizedBox(height: AppleSpacing.md),
        ],
        AiAnalysisPrecheckView(
          precheck: precheck,
          coverage: coverage,
          actions: actions,
          onOpenSettings: onOpenSettings,
          runPresentation: runPresentation,
          showPlanDetails: false,
        ),
      ],
    );
  }
}
