import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/ai_result_groups.dart';
import 'package:volward/features/ai_coverage/controllers/ai_analysis_results_controller.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_view_state.dart';

void main() {
  test('late narrative completion after rebind is ignored', () async {
    final results = AiAnalysisResultsController.forTest(delayedNarrative: true);

    final pending = results.generateNarrative();
    results.rebindOwner('owner-b');
    results.completeDelayedNarrative('stale narrative');
    await pending;

    expect(results.narrativeState.text, isNull);
  });

  test('narrative publishes when the owner remains current', () async {
    final results = AiAnalysisResultsController.forTest(delayedNarrative: true);

    final pending = results.generateNarrative(signature: 'hash-a');
    results.completeDelayedNarrative('fresh narrative');
    await pending;

    expect(results.narrativeState.text, 'fresh narrative');
    expect(results.narrativeState.signature, 'hash-a');
  });

  test('review include decision selects the path and keep deselects it', () {
    final results = AiAnalysisResultsController.forTest();

    results.setReviewDecision('/a', WorkspaceReviewDecision.include);
    expect(results.selected, contains('/a'));

    results.setReviewDecision('/a', WorkspaceReviewDecision.keep);
    expect(results.selected, isNot(contains('/a')));
  });

  test('results state defensively copies collections', () {
    final results = AiAnalysisResultsController.forTest();
    results.toggleSelection('/a', true);

    final state = results.resultsState;
    results.toggleSelection('/a', false);

    expect(state.selectedPaths, contains('/a'));
    expect(results.selected, isNot(contains('/a')));
  });

  test('normalized group cache is owner-owned and unmodifiable', () {
    final results = AiAnalysisResultsController.forTest();
    final groups = groupAiResults(
      const [
        AiVerdict(
          path: '/tmp/a',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: '',
        ),
      ],
      const {'/tmp/a': 10},
      rootPath: '/tmp',
    );

    results.setNormalizedGroupsCache(groups);
    final cached = results.normalizedGroupsCache!;

    expect(cached, hasLength(1));
    expect(() => cached.add(groups.first), throwsUnsupportedError);
    expect(cached.first.items, hasLength(1));
    expect(() => cached.first.items.clear(), throwsUnsupportedError);
  });

  test(
    'projection derives groups, totals and overview from context inputs',
    () {
      final results = AiAnalysisResultsController.forTest();
      const safe = AiVerdict(
        path: '/tmp/a.cache',
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: 'cache',
      );
      const review = AiVerdict(
        path: '/tmp/b.log',
        verdict: 'review_needed',
        confidence: 'high',
        reason: 'log',
      );
      final projection = results.buildProjection(
        const AiResultsProjectionInput(
          verdicts: [safe, review],
          selected: {'/tmp/a.cache'},
          reviewDecisions: {'/tmp/b.log': WorkspaceReviewDecision.pending},
          expandedGroupPaths: {},
          expandedGroupItemLimits: {},
          expandedReviewPaths: {},
          sizeByPath: {'/tmp/a.cache': 10, '/tmp/b.log': 20},
          searchTextByPath: {
            '/tmp/a.cache': '/tmp/a.cache cache',
            '/tmp/b.log': '/tmp/b.log log',
          },
          preClassified: [],
          unanalyzedVerdicts: [],
          rootPath: '/tmp',
          targetLabel: 'tmp',
          useFullCoverage: false,
          truncated: false,
          filter: WorkspaceResultFilter.all,
          sort: WorkspaceResultSort.size,
          query: '',
          directoryFilter: null,
          showsFilteredItems: false,
          heavyResultsLayoutThreshold: 200,
          aiResultGroupDisplayItemCap: 512,
          firstLevelDirectoryPaths: {'/tmp'},
          directoryPathsForGrouping: {'/tmp'},
          coverageResultsLoadTruncated: false,
          analyzedItemCountOverride: null,
        ),
      );

      expect(projection.safeBytes, 10);
      expect(projection.safeItemCount, 1);
      expect(projection.reviewCount, 1);
      expect(projection.normalizedGroups, isNotEmpty);
      expect(projection.overview.analyzedItemCount, 2);
      expect(() => projection.visibleGroups.clear(), throwsUnsupportedError);
    },
  );

  test(
    'full coverage projection keeps aggregate safe counts beyond visible rows',
    () {
      final results = AiAnalysisResultsController.forTest();
      const safe = AiVerdict(
        path: '/tmp/cache/a.bin',
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: 'cache',
      );
      final projection = results.buildProjection(
        const AiResultsProjectionInput(
          verdicts: [safe],
          selected: {},
          reviewDecisions: {},
          expandedGroupPaths: {},
          expandedGroupItemLimits: {},
          expandedReviewPaths: {},
          sizeByPath: {'/tmp/cache/a.bin': 10},
          searchTextByPath: {'/tmp/cache/a.bin': '/tmp/cache/a.bin cache'},
          preClassified: [],
          unanalyzedVerdicts: [],
          rootPath: '/tmp',
          targetLabel: 'tmp',
          useFullCoverage: true,
          truncated: false,
          filter: WorkspaceResultFilter.all,
          sort: WorkspaceResultSort.size,
          query: '',
          directoryFilter: null,
          showsFilteredItems: false,
          heavyResultsLayoutThreshold: 0,
          aiResultGroupDisplayItemCap: 0,
          firstLevelDirectoryPaths: {'/tmp/cache'},
          directoryPathsForGrouping: {'/tmp/cache'},
          coverageResultsLoadTruncated: true,
          analyzedItemCountOverride: 10,
        ),
      );

      expect(projection.overview.analyzedItemCount, 10);
      expect(projection.safeItemCount, 1);
    },
  );

  test('keep filter only exposes retained verdicts', () {
    final results = AiAnalysisResultsController.forTest();
    const safe = AiVerdict(
      path: '/tmp/safe.cache',
      verdict: 'safe_to_remove',
      confidence: 'high',
      reason: 'cache',
    );
    const keep = AiVerdict(
      path: '/tmp/keep.db',
      verdict: 'keep',
      confidence: 'high',
      reason: 'database',
    );
    final projection = results.buildProjection(
      const AiResultsProjectionInput(
        verdicts: [safe, keep],
        selected: {},
        reviewDecisions: {},
        expandedGroupPaths: {},
        expandedGroupItemLimits: {},
        expandedReviewPaths: {},
        sizeByPath: {'/tmp/safe.cache': 10, '/tmp/keep.db': 20},
        searchTextByPath: {
          '/tmp/safe.cache': '/tmp/safe.cache cache',
          '/tmp/keep.db': '/tmp/keep.db database',
        },
        preClassified: [],
        unanalyzedVerdicts: [],
        rootPath: '/tmp',
        targetLabel: 'tmp',
        useFullCoverage: false,
        truncated: false,
        filter: WorkspaceResultFilter.keep,
        sort: WorkspaceResultSort.size,
        query: '',
        directoryFilter: null,
        showsFilteredItems: true,
        heavyResultsLayoutThreshold: 200,
        aiResultGroupDisplayItemCap: 512,
        firstLevelDirectoryPaths: {'/tmp'},
        directoryPathsForGrouping: {'/tmp'},
        coverageResultsLoadTruncated: false,
        analyzedItemCountOverride: null,
      ),
    );

    expect(projection.visibleGroups.single.items.map((item) => item.path), [
      '/tmp/keep.db',
    ]);
  });
}
