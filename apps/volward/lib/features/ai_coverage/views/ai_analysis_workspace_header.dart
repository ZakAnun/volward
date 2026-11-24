import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/apple_tokens.dart';
import '../../../theme/volward_tokens.dart';
import '../../../widgets/apple_widgets.dart';
import '../ai_analysis_workspace_keys.dart';
import '../models/ai_analysis_workspace_display_state.dart';
import 'ai_analysis_workspace_view_state.dart';

/// The workspace chrome header: back action, title, hub status and step dots.
///
/// This view owns localization and semantics for the shell chrome. The
/// controller supplies only context-free [AiWorkspaceOverviewState].
class AiAnalysisWorkspaceHeader extends StatelessWidget {
  const AiAnalysisWorkspaceHeader({
    super.key,
    required this.shell,
    required this.onBack,
  });

  static const _phaseStepCount = 4;

  final AiWorkspaceOverviewState shell;
  final VoidCallback? onBack;

  String _phaseLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (shell.displayState) {
      AiWorkspaceDisplayState.loading => l10n.aiWorkspacePhaseLoading,
      AiWorkspaceDisplayState.precheck => l10n.aiResultsPhaseResults,
      AiWorkspaceDisplayState.privacy => l10n.aiWorkspacePhasePrivacy,
      AiWorkspaceDisplayState.analyzing => l10n.aiWorkspacePhaseAnalyzing,
      AiWorkspaceDisplayState.results => switch (shell.resultsView) {
        WorkspaceResultsView.overview => l10n.aiResultsPhaseResults,
        WorkspaceResultsView.reviewQueue => l10n.aiResultsPhaseReviewQueue,
        WorkspaceResultsView.detailList => l10n.aiResultsPhaseDetailList,
      },
      AiWorkspaceDisplayState.deleting => l10n.aiWorkspacePhaseDeleting,
      AiWorkspaceDisplayState.error => l10n.aiWorkspacePhaseRecovery,
    };
  }

  String? _hubStatusLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (shell.hubStatus) {
      WorkspaceHubStatus.awaitingAnalysis => l10n.aiResultsHubStatusAwaiting,
      WorkspaceHubStatus.analyzing => l10n.aiResultsHubStatusAnalyzing,
      WorkspaceHubStatus.partial => l10n.aiResultsHubStatusPartial,
      WorkspaceHubStatus.ready => l10n.aiResultsHubStatusReady,
      null => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.volward;
    final phaseLabel = _phaseLabel(context);
    final hubStatusLabel = _hubStatusLabel(context);
    final phaseSemantics = hubStatusLabel == null
        ? '$phaseLabel, step ${shell.phaseStep} of $_phaseStepCount'
        : '$phaseLabel, $hubStatusLabel, step ${shell.phaseStep} '
              'of $_phaseStepCount';
    final phaseIndicator = Semantics(
      value: phaseSemantics,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var step = 1; step <= _phaseStepCount; step++) ...[
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: step <= shell.phaseStep
                      ? tokens.primary
                      : tokens.inkMuted48.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
              ),
              if (step < _phaseStepCount)
                const SizedBox(width: AppleSpacing.xxs),
            ],
          ],
        ),
      ),
    );
    final title = Text(
      l10n.aiWorkspaceTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.vwBodyStrong.copyWith(fontSize: 15, height: 1.12),
    );
    final hubStatusChip = hubStatusLabel == null
        ? null
        : Container(
            key: AiAnalysisWorkspaceKeys.hubStatusChipKey,
            padding: const EdgeInsets.symmetric(
              horizontal: AppleSpacing.xs,
              vertical: AppleSpacing.xxs / 2,
            ),
            decoration: BoxDecoration(
              color: tokens.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppleRadius.pill),
              border: Border.all(color: tokens.primary.withValues(alpha: 0.22)),
            ),
            child: Text(
              hubStatusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.vwFinePrint.copyWith(
                color: tokens.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
    return DecoratedBox(
      key: AiAnalysisWorkspaceKeys.headerKey,
      decoration: const BoxDecoration(color: Colors.transparent),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppleSpacing.md,
            vertical: AppleSpacing.xs,
          ),
          child: Row(
            children: [
              AppleButton(
                key: AiAnalysisWorkspaceKeys.backKey,
                label: l10n.aiWorkspaceBack,
                icon: Icons.arrow_back,
                variant: AppleButtonVariant.pearl,
                onPressed: onBack,
              ),
              const SizedBox(width: AppleSpacing.xs),
              Expanded(child: title),
              if (hubStatusChip != null) ...[
                const SizedBox(width: AppleSpacing.xs),
                hubStatusChip,
              ],
              const SizedBox(width: AppleSpacing.sm),
              phaseIndicator,
            ],
          ),
        ),
      ),
    );
  }
}
