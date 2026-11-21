import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/ai_result_groups.dart';
import 'package:volward/features/ai_coverage/ai_analysis_workspace_keys.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_detail_list_view.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_view_actions.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_view_state.dart';
import 'package:volward/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('detail list renders summary, stream rows and delete action', (
    tester,
  ) async {
    final group = groupAiResults(
      [
        const AiVerdict(
          path: '/downloads/a.cache',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'test',
        ),
      ],
      {'/downloads/a.cache': 10},
    ).first;
    final visible = AiWorkspaceVisibleResultGroup(
      group: group,
      items: group.items,
      totalBytes: group.totalBytes,
      actionableCount: group.safeCount,
    );
    final scroll = ScrollController();
    final search = TextEditingController();
    addTearDown(() {
      scroll.dispose();
      search.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AiAnalysisDetailListView(
            state: AiAnalysisWorkspaceViewState(
              results: AiWorkspaceResultsState(
                groups: [group],
                visibleGroups: [visible],
                sizeByPath: {'/downloads/a.cache': 10},
                safeBytes: 10,
                reviewCount: 0,
              ),
            ),
            actions: _NoopActions(),
            scrollController: scroll,
            searchController: search,
            showCompactActivity: false,
          ),
        ),
      ),
    );

    expect(find.byKey(AiAnalysisWorkspaceKeys.summaryKey), findsOneWidget);
    expect(
      find.byKey(AiAnalysisWorkspaceKeys.decisionSummaryKey),
      findsOneWidget,
    );
    expect(find.byKey(AiAnalysisWorkspaceKeys.deleteKey), findsOneWidget);
    expect(find.byKey(const Key('ai-result-group:/downloads')), findsOneWidget);
  });

  test('detail list view has no page-controller coupling', () {
    final source = File(
      'lib/features/ai_coverage/views/ai_analysis_detail_list_view.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('ai_analysis_workspace_page_controller')));
    expect(source, isNot(contains('part of')));
  });
}

class _NoopActions implements AiAnalysisWorkspaceViewActions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
