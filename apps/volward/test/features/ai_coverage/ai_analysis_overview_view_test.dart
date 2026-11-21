import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_result_overview.dart';
import 'package:volward/features/ai_coverage/ai_analysis_workspace_keys.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_overview_view.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_view_state.dart';
import 'package:volward/l10n/generated/app_localizations.dart';

void main() {
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
              onOpenDetailPage: ({String? directoryPath}) {},
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
