import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/ai/coverage_models.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_ui_helpers.dart';
import 'package:volward/features/ai_coverage/ai_analysis_workspace_keys.dart';
import 'package:volward/features/ai_coverage/models/ai_analysis_workspace_display_state.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_precheck_view.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_body_view.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_view_actions.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_view_state.dart';
import 'package:volward/ai/ai_result_overview.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/widgets/ai_analysis_activity_card.dart';
import 'package:volward/widgets/ai_analysis_scope_panel.dart';

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

    expect(find.text('Candidate discovery'), findsOneWidget);
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

  testWidgets('failed local coverage does not show an AI waiting state', (
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
            useFullCoverage: true,
          ),
          coverage: AiWorkspaceCoverageState(),
          runPresentation: const CoverageRunPresentation(
            localPhase: CoverageLocalPhase.failed,
            localResolvedFiles: 5,
            localPlannedFiles: 20,
            localProgressFraction: null,
            aiPhase: ClassificationAiPhase.notStarted,
            aiResolvedFiles: 0,
            aiPlannedFiles: 0,
            aiProgressFraction: null,
          ),
          actions: _NoopActions(),
          onOpenSettings: _noop,
        ),
      ),
    );

    expect(
      find.text('AI analysis waits for local rules to finish.'),
      findsNothing,
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('running local coverage shows an active loading indicator', (
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
            useFullCoverage: true,
          ),
          coverage: AiWorkspaceCoverageState(),
          runPresentation: const CoverageRunPresentation(
            localPhase: CoverageLocalPhase.running,
            localResolvedFiles: 4,
            localPlannedFiles: 20,
            localProgressFraction: 0.2,
            aiPhase: ClassificationAiPhase.notStarted,
            aiResolvedFiles: 0,
            aiPlannedFiles: 10,
            aiProgressFraction: null,
          ),
          actions: _NoopActions(),
          onOpenSettings: _noop,
        ),
      ),
    );

    expect(find.text('4 / 20 items classified locally'), findsOneWidget);
    expect(find.byType(AiAnalysisActivityInlineSpinner), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('discovery and partial coverage keep their progress separate', (
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
            useFullCoverage: true,
            candidatesBootstrapPending: true,
            displayUnknownCount: 77,
          ),
          coverage: AiWorkspaceCoverageState(
            jobState: _completedJob(analyzedFiles: 317),
            planSummary: _coveragePlan,
          ),
          actions: _NoopActions(),
          onOpenSettings: _noop,
        ),
      ),
    );

    expect(find.byType(AiAnalysisActivityInlineSpinner), findsOneWidget);
    expect(find.text('Discovering candidates · 77 found'), findsOneWidget);
    expect(find.textContaining('317 / 4610'), findsOneWidget);
    expect(find.textContaining('4293'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('disclosure content starts twelve pixels below its header', (
    tester,
  ) async {
    const headerKey = Key('disclosure-header');
    const childKey = Key('disclosure-child');
    await tester.pumpWidget(
      const MaterialApp(
        home: AiAnalysisDisclosureCard(
          header: SizedBox(key: headerKey, height: 20),
          child: SizedBox(key: childKey, height: 20),
        ),
      ),
    );

    final headerBottom = tester.getBottomLeft(find.byKey(headerKey)).dy;
    final childTop = tester.getTopLeft(find.byKey(childKey)).dy;
    expect(childTop - headerBottom, 12);
  });

  testWidgets('partial coverage explains its range and continues in place', (
    tester,
  ) async {
    var resumed = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AiAnalysisCoverageContinuationCard(
          targetLabel: 'testDir',
          truth: const CoverageCompletionTruth(
            phase: CoverageCompletionPhase.partial,
            analyzedFiles: 317,
            totalFiles: 4610,
          ),
          onContinue: () => resumed = true,
        ),
      ),
    );

    expect(find.textContaining('testDir'), findsOneWidget);
    expect(find.textContaining('317'), findsOneWidget);
    expect(find.textContaining('4293'), findsOneWidget);
    final button = find.byKey(AiAnalysisWorkspaceKeys.continueCoverageKey);
    expect(button, findsOneWidget);

    await tester.tap(button);
    expect(resumed, isTrue);
  });

  testWidgets('complete coverage does not offer continuation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AiAnalysisCoverageContinuationCard(
          targetLabel: 'testDir',
          truth: const CoverageCompletionTruth(
            phase: CoverageCompletionPhase.completed,
            analyzedFiles: 4610,
            totalFiles: 4610,
          ),
          onContinue: () {},
        ),
      ),
    );

    expect(
      find.byKey(AiAnalysisWorkspaceKeys.continueCoverageKey),
      findsNothing,
    );
  });

  testWidgets('non-partial coverage states do not offer continuation', (
    tester,
  ) async {
    const ineligibleTruths = [
      CoverageCompletionTruth(
        phase: CoverageCompletionPhase.running,
        analyzedFiles: 317,
        totalFiles: 4610,
      ),
      CoverageCompletionTruth(
        phase: CoverageCompletionPhase.indeterminate,
        analyzedFiles: 317,
        totalFiles: 4610,
      ),
      CoverageCompletionTruth(
        phase: CoverageCompletionPhase.indeterminate,
        analyzedFiles: 0,
        totalFiles: null,
      ),
    ];

    for (final truth in ineligibleTruths) {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AiAnalysisCoverageContinuationCard(
            targetLabel: 'testDir',
            truth: truth,
            onContinue: () {},
          ),
        ),
      );

      expect(
        find.byKey(AiAnalysisWorkspaceKeys.continueCoverageKey),
        findsNothing,
      );
    }
  });

  testWidgets(
    'partial results continue through the persisted coverage action',
    (tester) async {
      final actions = _TrackingActions();
      final scrollController = ScrollController();
      final searchController = TextEditingController();
      addTearDown(scrollController.dispose);
      addTearDown(searchController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SizedBox(
            height: 900,
            child: AiAnalysisWorkspaceBodyView(
              state: AiAnalysisWorkspaceViewState(
                precheck: const AiWorkspacePrecheckState(useFullCoverage: true),
                coverage: AiWorkspaceCoverageState(
                  useFullCoverage: true,
                  jobState: _completedJob(analyzedFiles: 317),
                  planSummary: _coveragePlan,
                ),
                results: AiWorkspaceResultsState(overview: _partialOverview),
                overview: const AiWorkspaceOverviewState(
                  displayState: AiWorkspaceDisplayState.results,
                  resultsView: WorkspaceResultsView.overview,
                ),
              ),
              actions: actions,
              onOpenSettings: _noop,
              scrollController: scrollController,
              searchController: searchController,
            ),
          ),
        ),
      );

      final button = find.byKey(AiAnalysisWorkspaceKeys.continueCoverageKey);
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pump();

      expect(actions.resumeCoverageCalls, 1);
      expect(actions.startAnalysisCalls, 0);
    },
  );
}

const _coveragePlan = CoveragePlanSummary(
  snapshotId: 'snapshot',
  planVersion: 3,
  rootPath: '/tmp',
  totalUnclassified: 4610,
  preClassifiedCount: 0,
  groupRows: 0,
  fileRows: 4610,
  estimatedPages: 2,
  treePendingFiles: 4610,
);

CoverageJobState _completedJob({required int analyzedFiles}) =>
    CoverageJobState(
      snapshotId: 'snapshot',
      rootPath: '/tmp',
      planVersion: 3,
      cursor: analyzedFiles,
      totalUnclassified: 4610,
      analyzedFiles: analyzedFiles,
      preClassifiedCount: 0,
      status: CoverageJobStatus.completed,
      usedTokens: 0,
      usedCredits: 0,
      budgetTokens: 0,
      budgetCredits: 0,
      updatedAtMs: 1,
      localRuleFiles: 0,
      aiResolvedFiles: analyzedFiles,
      localPhaseComplete: true,
    );

const _partialOverview = AiAnalysisConclusionOverview(
  targetLabel: 'testDir',
  rootPath: '/tmp',
  safeBytes: 0,
  reviewCount: 0,
  keepCount: 0,
  analyzedItemCount: 317,
  analyzedTotalBytes: 0,
  rootSizeBytes: 0,
  shareOfRootPct: null,
  truncated: false,
  fullCoverage: true,
  directories: [],
);

void _noop() {}

class _NoopActions implements AiAnalysisWorkspaceViewActions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TrackingActions extends _NoopActions {
  var resumeCoverageCalls = 0;
  var startAnalysisCalls = 0;

  @override
  Future<void> resumeCoverage() async {
    resumeCoverageCalls++;
  }

  @override
  Future<void> startAnalysis({required bool fullCoverage}) async {
    startAnalysisCalls++;
  }
}
