import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/features/ai_coverage/ai_analysis_workspace_keys.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_purchase_view.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_view_state.dart';
import 'package:volward/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('purchase shows settings prompt when provider is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AiAnalysisPurchaseView(
            precheck: AiWorkspacePrecheckState(
              mode: AiMode.byok,
              hasProvider: false,
              error: null,
            ),
            onOpenSettings: _noop,
          ),
        ),
      ),
    );

    expect(find.byKey(AiAnalysisWorkspaceKeys.settingsKey), findsOneWidget);
    expect(find.text('Buy credits'), findsNothing);
    expect(find.text('AI Analysis'), findsOneWidget);
  });

  testWidgets('purchase shows insufficient-credit prompt for platform mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AiAnalysisPurchaseView(
            precheck: AiWorkspacePrecheckState(
              mode: AiMode.platform,
              hasProvider: true,
              platformCredits: 0,
            ),
            onOpenSettings: _noop,
          ),
        ),
      ),
    );

    expect(find.byKey(AiAnalysisWorkspaceKeys.settingsKey), findsOneWidget);
    expect(find.text('Buy credits'), findsOneWidget);
  });

  testWidgets('purchase hides settings prompt when context is usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AiAnalysisPurchaseView(
            precheck: AiWorkspacePrecheckState(
              mode: AiMode.platform,
              hasProvider: true,
              platformCredits: 10,
            ),
            onOpenSettings: _noop,
          ),
        ),
      ),
    );

    expect(find.byKey(AiAnalysisWorkspaceKeys.settingsKey), findsNothing);
  });

  testWidgets('purchase hides prompts while candidate context is loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AiAnalysisPurchaseView(
            precheck: AiWorkspacePrecheckState(
              mode: AiMode.byok,
              hasProvider: false,
              candidatesBootstrapPending: true,
            ),
            onOpenSettings: _noop,
          ),
        ),
      ),
    );

    expect(find.byKey(AiAnalysisWorkspaceKeys.settingsKey), findsNothing);
  });
}

void _noop() {}
