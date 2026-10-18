import '../l10n/generated/app_localizations.dart';
import 'ai_analysis_activity_model.dart';

class AppLocalizationsAiAnalysisActivityL10n implements AiAnalysisActivityL10n {
  AppLocalizationsAiAnalysisActivityL10n(this._l10n);

  final AppLocalizations _l10n;

  @override
  String substageLabel(AiActivitySubstage stage) {
    switch (stage) {
      case AiActivitySubstage.session:
        return _l10n.aiActivitySubstageSession;
      case AiActivitySubstage.candidates:
        return _l10n.aiActivitySubstageCandidates;
      case AiActivitySubstage.plan:
        return _l10n.aiActivitySubstagePlan;
      case AiActivitySubstage.tree:
        return _l10n.aiActivitySubstageTree;
      case AiActivitySubstage.tail:
        return _l10n.aiActivitySubstageTail;
      case AiActivitySubstage.finalize:
        return _l10n.aiActivitySubstageFinalize;
    }
  }

  @override
  String subtitleFor({
    required AiActivitySubstage active,
    required AiAnalysisActivityInput input,
  }) {
    switch (active) {
      case AiActivitySubstage.session:
        return _l10n.aiActivitySubtitleSession;
      case AiActivitySubstage.candidates:
        return _l10n.aiActivitySubtitleCandidates(input.candidateCount);
      case AiActivitySubstage.plan:
        return _l10n.aiActivitySubtitlePlan;
      case AiActivitySubstage.tree:
        return _l10n.aiActivitySubtitleTree;
      case AiActivitySubstage.tail:
        if (input.analyzingQuick || !input.useFullCoverage) {
          return _l10n.aiActivitySubtitleQuickTail(
            input.candidateCount,
            input.modeLabel,
          );
        }
        return _l10n.aiActivitySubtitleTail;
      case AiActivitySubstage.finalize:
        return _l10n.aiActivitySubtitleFinalize;
    }
  }

  @override
  String progressLabel({required int analyzed, required int total}) =>
      _l10n.aiCoverageProgress(analyzed, total);

  @override
  String updatedAgo(int seconds) => _l10n.aiActivityUpdatedAgo(seconds);

  @override
  String metricAnalyzed(String value) => _l10n.aiActivityMetricAnalyzed(value);

  @override
  String metricCredits(String value) => _l10n.aiActivityMetricCredits(value);

  @override
  String metricLocalResolved(String value) =>
      _l10n.aiActivityMetricLocalResolved(value);

  @override
  String resumingJob() => _l10n.aiActivityResumingJob;
}
