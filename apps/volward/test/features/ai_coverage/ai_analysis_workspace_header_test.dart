import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/features/ai_coverage/ai_analysis_workspace_keys.dart';
import 'package:volward/features/ai_coverage/models/ai_analysis_workspace_display_state.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_header.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_view_state.dart';
import 'package:volward/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('workspace header renders chrome from a shell snapshot', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AiAnalysisWorkspaceHeader(
          shell: AiWorkspaceOverviewState(
            displayState: AiWorkspaceDisplayState.results,
            resultsView: WorkspaceResultsView.overview,
            phaseStep: 4,
            hubStatus: WorkspaceHubStatus.ready,
          ),
          onBack: null,
        ),
      ),
    );

    expect(find.byKey(AiAnalysisWorkspaceKeys.headerKey), findsOneWidget);
    expect(
      find.byKey(AiAnalysisWorkspaceKeys.hubStatusChipKey),
      findsOneWidget,
    );
  });
}
