import 'package:flutter/material.dart';

import '../../../ai/ai_analysis_activity_l10n.dart';
import '../../../ai/ai_analysis_activity_model.dart';
import '../../../ai/ai_settings_store.dart';
import '../../../l10n/l10n.dart';
import '../widgets/analysis_activity_view.dart';
import 'ai_analysis_workspace_view_state.dart';

/// Renders the analysis activity card from an immutable activity snapshot.
///
/// The page aggregator computes [AiWorkspaceActivityState]; this view resolves
/// localization and presentation labels and builds the shared activity model.
class AiAnalysisActivityView extends StatelessWidget {
  const AiAnalysisActivityView({
    super.key,
    required this.activity,
    this.compact = false,
    this.macroPhase,
  });

  final AiWorkspaceActivityState activity;
  final bool compact;

  /// Overrides the snapshot phase for placeholders shown while results layout
  /// is still pending.
  final AiActivityMacroPhase? macroPhase;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizationsAiAnalysisActivityL10n(context.l10n);
    final model = _applyPauseSubtitle(
      buildAiAnalysisActivityModel(_activityInput(context), l10n),
      context,
    );
    return AnalysisActivityView(
      compact: compact,
      model: model,
      substageLabel: l10n.substageLabel,
      freezeActiveMotion: activity.freezeActiveMotion,
    );
  }

  AiAnalysisActivityInput _activityInput(BuildContext context) {
    final phase = macroPhase ?? activity.macroPhase;
    return AiAnalysisActivityInput(
      macroPhase: phase,
      useFullCoverage: activity.useFullCoverage,
      candidatesBootstrapPending: activity.candidatesBootstrapPending,
      coverageHydrating: activity.coverageHydrating,
      coverageHydrated: activity.coverageHydrated,
      analyzingQuick:
          phase != AiActivityMacroPhase.loading && !activity.useFullCoverage,
      resultsLayoutPending: activity.resultsLayoutPending,
      resumingJob: activity.resumingJob,
      candidateCount: activity.candidateCount,
      modeLabel: _modeLabel(context, activity.mode),
      job: activity.job,
    );
  }

  String _modeLabel(BuildContext context, AiMode mode) {
    return switch (mode) {
      AiMode.platform => context.l10n.aiSettingsPlatformLabel,
      AiMode.byok => context.l10n.aiSettingsByokLabel,
      AiMode.off => context.l10n.aiSettingsOffLabel,
    };
  }

  AiAnalysisActivityModel _applyPauseSubtitle(
    AiAnalysisActivityModel model,
    BuildContext context,
  ) {
    if (!activity.pauseInFlight) return model;
    return AiAnalysisActivityModel(
      visibleSubstages: model.visibleSubstages,
      activeSubstage: model.activeSubstage,
      completedSubstages: model.completedSubstages,
      title: model.title,
      subtitle: context.l10n.aiActivityPausing,
      progress: model.progress,
      progressLabel: model.progressLabel,
      metrics: model.metrics,
      lastUpdated: model.lastUpdated,
    );
  }
}
