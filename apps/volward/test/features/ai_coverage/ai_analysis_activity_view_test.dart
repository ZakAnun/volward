import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_analysis_activity_model.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_activity_view.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_view_state.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/widgets/ai_analysis_activity_card.dart';

void main() {
  testWidgets(
    'activity view renders a compact card from an activity snapshot',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AiAnalysisActivityView(
            compact: true,
            activity: AiWorkspaceActivityState(
              analyzing: true,
              coverageRunning: true,
              macroPhase: AiActivityMacroPhase.analyzing,
              useFullCoverage: true,
              candidateCount: 3,
              mode: AiMode.byok,
              freezeActiveMotion: true,
            ),
          ),
        ),
      );

      expect(find.byType(AiAnalysisActivityCard), findsOneWidget);
      expect(find.byKey(AiAnalysisActivityCard.compactKey), findsOneWidget);
    },
  );
}
