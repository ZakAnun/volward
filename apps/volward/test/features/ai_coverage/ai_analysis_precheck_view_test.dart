import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/features/ai_coverage/ai_analysis_workspace_keys.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_precheck_view.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_view_actions.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_view_state.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/widgets/ai_analysis_activity_card.dart';

void main() {
  testWidgets('precheck shows settings prompt when provider is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AiAnalysisPrecheckView(
          precheck: const AiWorkspacePrecheckState(
            mode: AiMode.byok,
            hasProvider: false,
            error: null,
          ),
          coverage: AiWorkspaceCoverageState(),
          actions: _NoopActions(),
          onOpenSettings: _noop,
        ),
      ),
    );

    expect(find.byKey(AiAnalysisWorkspaceKeys.settingsKey), findsOneWidget);
    expect(find.byType(AiAnalysisPrecheckView), findsOneWidget);
  });

  testWidgets('precheck shows inline spinner while candidates load', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AiAnalysisPrecheckView(
          precheck: const AiWorkspacePrecheckState(
            mode: AiMode.byok,
            hasProvider: true,
            candidatesBootstrapPending: true,
          ),
          coverage: AiWorkspaceCoverageState(),
          actions: _NoopActions(),
          onOpenSettings: _noop,
        ),
      ),
    );

    expect(find.byType(AiAnalysisActivityInlineSpinner), findsOneWidget);
  });
}

void _noop() {}

class _NoopActions implements AiAnalysisWorkspaceViewActions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
