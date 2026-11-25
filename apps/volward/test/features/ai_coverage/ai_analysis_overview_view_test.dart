import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_ui_helpers.dart';
import 'package:volward/ai/ai_result_overview.dart';
import 'package:volward/features/ai_coverage/ai_analysis_workspace_keys.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_overview_view.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_view_state.dart';
import 'package:volward/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('dashboard presents reclaimable outcome from conclusion data', (
    tester,
  ) async {
    final state = AiAnalysisWorkspaceViewState(
      results: AiWorkspaceResultsState(overview: _dashboardOverview()),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AiAnalysisOverviewView(
            state: state,
            hasVerdicts: true,
            safeCount: 30,
            analyzing: true,
            canGenerateNarrative: false,
            showNarrativeCreditHint: false,
            emptyState: const SizedBox.shrink(),
            onOpenDetailList: (_, {directoryPath}) {},
            onOpenReviewQueue: () {},
            onDirectoryTypeFilterChanged: (_) {},
            onGenerateNarrative: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(AiAnalysisWorkspaceKeys.cleanupDashboardKey),
      findsOneWidget,
    );
    expect(
      find.byKey(AiAnalysisWorkspaceKeys.cleanupReclaimRingKey),
      findsOneWidget,
    );
    expect(find.text('156.3 MB'), findsOneWidget);
    expect(find.text('30 items'), findsOneWidget);
  });

  testWidgets('dashboard omits reclaim percentage when root size is unknown', (
    tester,
  ) async {
    final state = AiAnalysisWorkspaceViewState(
      results: AiWorkspaceResultsState(
        overview: _dashboardOverview(shareOfRootPct: null),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AiAnalysisOverviewView(
            state: state,
            hasVerdicts: true,
            safeCount: 30,
            analyzing: false,
            canGenerateNarrative: false,
            showNarrativeCreditHint: false,
            emptyState: const SizedBox.shrink(),
            onOpenDetailList: (_, {directoryPath}) {},
            onOpenReviewQueue: () {},
            onDirectoryTypeFilterChanged: (_) {},
            onGenerateNarrative: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(AiAnalysisWorkspaceKeys.cleanupReclaimRingKey),
      findsNothing,
    );
    expect(find.textContaining('14.6%'), findsNothing);
  });

  testWidgets('dashboard keeps local-rule progress visible while it runs', (
    tester,
  ) async {
    final state = AiAnalysisWorkspaceViewState(
      results: AiWorkspaceResultsState(
        overview: _dashboardOverview(),
        coverageRunPresentation: const CoverageRunPresentation(
          localPhase: CoverageLocalPhase.running,
          localResolvedFiles: 4,
          localPlannedFiles: 20,
          localProgressFraction: 0.2,
          aiPhase: ClassificationAiPhase.notStarted,
          aiResolvedFiles: 0,
          aiPlannedFiles: 10,
          aiProgressFraction: null,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AiAnalysisOverviewView(
            state: state,
            hasVerdicts: true,
            safeCount: 30,
            analyzing: true,
            canGenerateNarrative: false,
            showNarrativeCreditHint: false,
            emptyState: const SizedBox.shrink(),
            onOpenDetailList: (_, {directoryPath}) {},
            onOpenReviewQueue: () {},
            onDirectoryTypeFilterChanged: (_) {},
            onGenerateNarrative: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(AiAnalysisWorkspaceKeys.cleanupLocalProgressKey),
      findsOneWidget,
    );
    expect(find.text('4 / 20 items classified locally'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
  });

  testWidgets('does not label local keep outcomes as AI decisions', (
    tester,
  ) async {
    final state = AiAnalysisWorkspaceViewState(
      results: AiWorkspaceResultsState(
        overview: _dashboardOverview(localKeepCount: 2470),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AiAnalysisOverviewView(
            state: state,
            hasVerdicts: true,
            safeCount: 30,
            analyzing: true,
            canGenerateNarrative: false,
            showNarrativeCreditHint: false,
            emptyState: const SizedBox.shrink(),
            onOpenDetailList: (_, {directoryPath}) {},
            onOpenReviewQueue: () {},
            onDirectoryTypeFilterChanged: (_) {},
            onGenerateNarrative: () {},
          ),
        ),
      ),
    );

    expect(find.text('Local rule kept'), findsOneWidget);
    expect(find.text('AI kept'), findsNothing);
  });

  testWidgets('overview view renders conclusions and directory summaries', (
    tester,
  ) async {
    final state = AiAnalysisWorkspaceViewState(
      results: AiWorkspaceResultsState(
        overview: _overview(),
        directoryBucketCount: 1,
        directoryTypeFilter: WorkspaceDirectoryTypeFilter.safe,
      ),
      narrative: const AiWorkspaceNarrativeState(enabled: true, auto: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiAnalysisOverviewView(
              state: state,
              hasVerdicts: true,
              safeCount: 1,
              analyzing: false,
              canGenerateNarrative: true,
              showNarrativeCreditHint: false,
              emptyState: const SizedBox.shrink(),
              onOpenDetailList: (_, {directoryPath}) {},
              onOpenReviewQueue: () {},
              onDirectoryTypeFilterChanged: (_) {},
              onGenerateNarrative: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(AiAnalysisWorkspaceKeys.resultsHeroKey), findsOneWidget);
    expect(
      find.byKey(AiAnalysisWorkspaceKeys.directoryGridKey),
      findsOneWidget,
    );
    expect(
      find.byKey(AiAnalysisWorkspaceKeys.conclusionNarrativeGenerateKey),
      findsOneWidget,
    );
  });

  testWidgets('metric cards open their matching result filters', (
    tester,
  ) async {
    WorkspaceResultFilter? openedFilter;
    final state = AiAnalysisWorkspaceViewState(
      results: AiWorkspaceResultsState(
        overview: _overview(),
        directoryBucketCount: 1,
        directoryTypeFilter: WorkspaceDirectoryTypeFilter.safe,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiAnalysisOverviewView(
              state: state,
              hasVerdicts: true,
              safeCount: 1,
              analyzing: false,
              canGenerateNarrative: false,
              showNarrativeCreditHint: false,
              emptyState: const SizedBox.shrink(),
              onOpenDetailList: (filter, {directoryPath}) {
                openedFilter = filter;
              },
              onOpenReviewQueue: () {},
              onDirectoryTypeFilterChanged: (_) {},
              onGenerateNarrative: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(AiAnalysisWorkspaceKeys.resultsMetricSafeKey));
    expect(openedFilter, WorkspaceResultFilter.safeToRemove);

    await tester.tap(find.byKey(AiAnalysisWorkspaceKeys.resultsMetricKeepKey));
    expect(openedFilter, WorkspaceResultFilter.keep);
  });

  testWidgets('labels incremental results as still analyzing', (tester) async {
    final state = AiAnalysisWorkspaceViewState(
      results: AiWorkspaceResultsState(overview: _overview()),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiAnalysisOverviewView(
              state: state,
              hasVerdicts: true,
              safeCount: 1,
              analyzing: true,
              canGenerateNarrative: false,
              showNarrativeCreditHint: false,
              emptyState: const SizedBox.shrink(),
              onOpenDetailList: (_, {directoryPath}) {},
              onOpenReviewQueue: () {},
              onDirectoryTypeFilterChanged: (_) {},
              onGenerateNarrative: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(AiAnalysisWorkspaceKeys.classificationAiStatusKey),
      findsOneWidget,
    );
  });

  testWidgets('shows source counts and running AI status separately', (
    tester,
  ) async {
    final state = AiAnalysisWorkspaceViewState(
      results: AiWorkspaceResultsState(
        overview: _overview(),
        classificationProvenance: const ClassificationProvenanceSummary(
          bootstrapLocalCount: 3,
          localRuleCount: 4,
          aiResolvedCount: 7,
          aiPlannedCount: 20,
          phase: ClassificationAiPhase.running,
          localPlannedCount: 4,
          localPhaseComplete: true,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiAnalysisOverviewView(
              state: state,
              hasVerdicts: true,
              safeCount: 1,
              analyzing: true,
              canGenerateNarrative: false,
              showNarrativeCreditHint: false,
              emptyState: const SizedBox.shrink(),
              onOpenDetailList: (_, {directoryPath}) {},
              onOpenReviewQueue: () {},
              onDirectoryTypeFilterChanged: (_) {},
              onGenerateNarrative: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(AiAnalysisWorkspaceKeys.classificationProvenanceKey),
      findsOneWidget,
    );
    expect(
      find.byKey(AiAnalysisWorkspaceKeys.classificationBootstrapKey),
      findsOneWidget,
    );
    expect(
      find.byKey(AiAnalysisWorkspaceKeys.classificationLocalRulesKey),
      findsOneWidget,
    );
    expect(
      find.byKey(AiAnalysisWorkspaceKeys.classificationAiMetricKey),
      findsOneWidget,
    );
    expect(
      find.byKey(AiAnalysisWorkspaceKeys.classificationAiProgressKey),
      findsOneWidget,
    );
    expect(find.text('7 / 20'), findsOneWidget);
    expect(
      find.textContaining('Candidate-stage local preclassification'),
      findsNothing,
    );
  });

  testWidgets('shows active loading affordance while local rules run', (
    tester,
  ) async {
    final state = AiAnalysisWorkspaceViewState(
      results: AiWorkspaceResultsState(
        overview: _overview(),
        classificationProvenance: const ClassificationProvenanceSummary(
          bootstrapLocalCount: 3,
          localRuleCount: 4,
          aiResolvedCount: 0,
          aiPlannedCount: 20,
          phase: ClassificationAiPhase.notStarted,
          localPlannedCount: 20,
          localPhase: CoverageLocalPhase.running,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiAnalysisOverviewView(
              state: state,
              hasVerdicts: true,
              safeCount: 1,
              analyzing: true,
              canGenerateNarrative: false,
              showNarrativeCreditHint: false,
              emptyState: const SizedBox.shrink(),
              onOpenDetailList: (_, {directoryPath}) {},
              onOpenReviewQueue: () {},
              onDirectoryTypeFilterChanged: (_) {},
              onGenerateNarrative: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(AiAnalysisWorkspaceKeys.classificationLocalLoadingKey),
      findsOneWidget,
    );
    expect(
      find.byKey(AiAnalysisWorkspaceKeys.classificationAiProgressKey),
      findsNothing,
    );
  });

  testWidgets('does not present an unknown local-rule total as zero percent', (
    tester,
  ) async {
    final state = AiAnalysisWorkspaceViewState(
      results: AiWorkspaceResultsState(
        overview: _overview(),
        classificationProvenance: const ClassificationProvenanceSummary(
          bootstrapLocalCount: 200,
          localRuleCount: 0,
          aiResolvedCount: 0,
          aiPlannedCount: 317,
          phase: ClassificationAiPhase.notStarted,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiAnalysisOverviewView(
              state: state,
              hasVerdicts: true,
              safeCount: 1,
              analyzing: true,
              canGenerateNarrative: false,
              showNarrativeCreditHint: false,
              emptyState: const SizedBox.shrink(),
              onOpenDetailList: (_, {directoryPath}) {},
              onOpenReviewQueue: () {},
              onDirectoryTypeFilterChanged: (_) {},
              onGenerateNarrative: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(AiAnalysisWorkspaceKeys.classificationLocalProgressKey),
      findsNothing,
    );
    expect(find.text('Preparing local rules'), findsOneWidget);
    expect(find.text('Local 0%'), findsNothing);
  });

  testWidgets('shows local-only status without claiming AI completed', (
    tester,
  ) async {
    final state = AiAnalysisWorkspaceViewState(
      results: AiWorkspaceResultsState(
        overview: _overview(),
        classificationProvenance: const ClassificationProvenanceSummary(
          bootstrapLocalCount: 1,
          localRuleCount: 2,
          aiResolvedCount: 0,
          aiPlannedCount: 0,
          phase: ClassificationAiPhase.notRequired,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiAnalysisOverviewView(
              state: state,
              hasVerdicts: true,
              safeCount: 1,
              analyzing: false,
              canGenerateNarrative: false,
              showNarrativeCreditHint: false,
              emptyState: const SizedBox.shrink(),
              onOpenDetailList: (_, {directoryPath}) {},
              onOpenReviewQueue: () {},
              onDirectoryTypeFilterChanged: (_) {},
              onGenerateNarrative: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(AiAnalysisWorkspaceKeys.classificationAiStatusKey),
      findsOneWidget,
    );
    expect(
      find.byKey(AiAnalysisWorkspaceKeys.classificationAiProgressKey),
      findsNothing,
    );
    expect(find.textContaining('AI analysis is complete'), findsNothing);
  });

  testWidgets('explains when optional AI summary is disabled', (tester) async {
    final state = AiAnalysisWorkspaceViewState(
      results: AiWorkspaceResultsState(overview: _overview()),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiAnalysisOverviewView(
              state: state,
              hasVerdicts: true,
              safeCount: 1,
              analyzing: false,
              canGenerateNarrative: false,
              showNarrativeCreditHint: false,
              emptyState: const SizedBox.shrink(),
              onOpenDetailList: (_, {directoryPath}) {},
              onOpenReviewQueue: () {},
              onDirectoryTypeFilterChanged: (_) {},
              onGenerateNarrative: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(AiAnalysisWorkspaceKeys.conclusionNarrativeUnavailableKey),
      findsOneWidget,
    );
    expect(
      find.text(
        'AI summary is disabled. The structured classification '
        'results above are complete and ready to use.',
      ),
      findsOneWidget,
    );
  });
}

AiAnalysisConclusionOverview _overview() {
  return const AiAnalysisConclusionOverview(
    targetLabel: 'Downloads',
    rootPath: '/tmp/root',
    safeBytes: 2048,
    reviewCount: 2,
    keepCount: 1,
    analyzedItemCount: 5,
    analyzedTotalBytes: 4096,
    rootSizeBytes: 8192,
    shareOfRootPct: 25,
    truncated: false,
    fullCoverage: false,
    directories: [
      AiDirectoryConclusion(
        path: '/tmp/root/a',
        displayLabel: 'a',
        safeBytes: 1024,
        reviewCount: 1,
        keepCount: 0,
        shareOfSafePct: 50,
        reasonHighlights: [],
      ),
    ],
  );
}

AiAnalysisConclusionOverview _dashboardOverview({
  double? shareOfRootPct = 14.6,
  int localKeepCount = 0,
}) {
  return AiAnalysisConclusionOverview(
    targetLabel: 'testDir',
    rootPath: '/tmp/testDir',
    safeBytes: 163892429,
    reviewCount: 0,
    keepCount: 2470,
    analyzedItemCount: 94592,
    analyzedTotalBytes: 1406601789,
    rootSizeBytes: shareOfRootPct == null ? 0 : 963173019,
    shareOfRootPct: shareOfRootPct,
    truncated: false,
    fullCoverage: true,
    directories: const [],
    localKeepCount: localKeepCount,
  );
}
