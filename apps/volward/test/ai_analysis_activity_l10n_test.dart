import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_analysis_activity_l10n.dart';
import 'package:volward/ai/ai_analysis_activity_model.dart';
import 'package:volward/l10n/generated/app_localizations.dart';

void main() {
  late AppLocalizationsAiAnalysisActivityL10n l10n;

  setUp(() {
    l10n = AppLocalizationsAiAnalysisActivityL10n(
      lookupAppLocalizations(const Locale('en')),
    );
  });

  test('substage labels are non-empty for every substage', () {
    for (final stage in AiActivitySubstage.values) {
      expect(l10n.substageLabel(stage), isNotEmpty);
    }
  });

  test('subtitleFor returns non-empty for every substage', () {
    const base = AiAnalysisActivityInput(
      macroPhase: AiActivityMacroPhase.analyzing,
      useFullCoverage: true,
      candidatesBootstrapPending: false,
      coverageHydrating: false,
      coverageHydrated: true,
      analyzingQuick: false,
      resultsLayoutPending: false,
      resumingJob: false,
      candidateCount: 12,
      modeLabel: 'Platform',
    );

    for (final stage in AiActivitySubstage.values) {
      final input = stage == AiActivitySubstage.tail
          ? const AiAnalysisActivityInput(
              macroPhase: AiActivityMacroPhase.analyzing,
              useFullCoverage: false,
              candidatesBootstrapPending: false,
              coverageHydrating: false,
              coverageHydrated: true,
              analyzingQuick: true,
              resultsLayoutPending: false,
              resumingJob: false,
              candidateCount: 12,
              modeLabel: 'Platform',
            )
          : base;
      expect(l10n.subtitleFor(active: stage, input: input), isNotEmpty);
    }
  });
}
