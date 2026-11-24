import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/ai/coverage_models.dart';
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

  testWidgets('full coverage groups details behind the plan disclosure', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DecoratedBox(
          decoration: const BoxDecoration(color: Colors.white),
          child: SingleChildScrollView(
            child: AiAnalysisPrecheckView(
              precheck: const AiWorkspacePrecheckState(
                mode: AiMode.byok,
                hasProvider: true,
                useFullCoverage: true,
                displayPreClassifiedCount: 200,
                displayUnknownCount: 317,
              ),
              coverage: AiWorkspaceCoverageState(
                planSummary: const CoveragePlanSummary(
                  snapshotId: 'snapshot',
                  planVersion: 3,
                  rootPath: '/tmp/testDir',
                  totalUnclassified: 317,
                  preClassifiedCount: 0,
                  groupRows: 0,
                  fileRows: 317,
                  estimatedPages: 2,
                  localSafeFiles: 32,
                  localKeepFiles: 269,
                  treePendingFiles: 10,
                  tailFiles: 6,
                  estimatedTreeCredits: 1,
                  estimatedTailCredits: 1,
                ),
              ),
              actions: _NoopActions(),
              onOpenSettings: _noop,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    expect(find.text('Candidate preclassification'), findsOneWidget);
    expect(find.text('Local coverage rules'), findsOneWidget);
    expect(find.text('AI coverage analysis'), findsOneWidget);
    expect(
      find.byKey(AiAnalysisWorkspaceKeys.coveragePlanDetailsKey),
      findsOneWidget,
    );
    expect(
      find.byKey(AiAnalysisWorkspaceKeys.analysisPlanCardKey),
      findsOneWidget,
    );
    expect(find.text('▾'), findsOneWidget);
    expect(find.textContaining('Directory AI scope:'), findsNothing);

    await tester.tap(
      find.byKey(AiAnalysisWorkspaceKeys.coveragePlanDetailsKey),
    );
    await tester.pumpAndSettle();

    expect(find.text('▴'), findsOneWidget);
    expect(find.textContaining('Directory AI scope:'), findsOneWidget);
    expect(
      find.text('200 items pre-identified as safe to remove'),
      findsNothing,
    );
  });
}

void _noop() {}

class _NoopActions implements AiAnalysisWorkspaceViewActions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
