import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/ai_result_groups.dart';
import 'package:volward/ai/ai_result_overview.dart';

void main() {
  test(
    'buildAiAnalysisConclusionOverview aggregates safe bytes and reasons',
    () {
      const verdicts = [
        AiVerdict(
          path: '/home/Library/Caches/foo',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'Application cache',
        ),
        AiVerdict(
          path: '/home/Library/Caches/bar',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'Application cache',
        ),
        AiVerdict(
          path: '/home/Documents/note.txt',
          verdict: 'review_needed',
          confidence: 'medium',
          reason: 'Personal document',
        ),
      ];
      final overview = buildAiAnalysisConclusionOverview(
        const AiResultOverviewBuildInput(
          targetLabel: 'Home',
          rootPath: '/home',
          verdicts: verdicts,
          sizeByPath: {
            '/home/Library/Caches/foo': 100,
            '/home/Library/Caches/bar': 300,
            '/home/Documents/note.txt': 50,
          },
          rootSizeBytesHint: 1000,
        ),
      );

      expect(overview.safeBytes, 400);
      expect(overview.reviewCount, 1);
      expect(overview.shareOfRootPct, closeTo(40.0, 0.01));
      expect(overview.directories.length, 2);
      final library = overview.directories.firstWhere(
        (dir) => dir.displayLabel == 'Library',
      );
      expect(library.safeBytes, 400);
      expect(library.reasonHighlights, contains('Application cache'));
    },
  );

  test('extractReasonHighlights prefers largest safe reasons', () {
    const verdicts = [
      AiVerdict(
        path: '/a',
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: 'Small cache',
      ),
      AiVerdict(
        path: '/b',
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: 'Large build artifact',
      ),
    ];
    final highlights = extractReasonHighlights(verdicts, {'/a': 10, '/b': 900});
    expect(highlights.first, 'Large build artifact');
  });

  test('keeps local-rule and AI verdict counts separate', () {
    const verdicts = [
      AiVerdict(
        path: '/scan/cache.bin',
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: 'cache',
        classificationSource: 'local:kb',
      ),
      AiVerdict(
        path: '/scan/notes.txt',
        verdict: 'keep',
        confidence: 'high',
        reason: 'document',
        classificationSource: 'local:funnel',
      ),
      AiVerdict(
        path: '/scan/output',
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: 'build output',
        classificationSource: 'file',
      ),
      AiVerdict(
        path: '/scan/project',
        verdict: 'keep',
        confidence: 'high',
        reason: 'project',
        classificationSource: 'group:/scan/project',
      ),
    ];

    final overview = buildAiAnalysisConclusionOverview(
      const AiResultOverviewBuildInput(
        targetLabel: 'scan',
        rootPath: '/scan',
        verdicts: verdicts,
        sizeByPath: {
          '/scan/cache.bin': 10,
          '/scan/notes.txt': 20,
          '/scan/output': 30,
          '/scan/project': 40,
        },
      ),
    );

    expect(overview.localSafeCount, 1);
    expect(overview.aiSafeCount, 1);
    expect(overview.localKeepCount, 1);
    expect(overview.aiKeepCount, 1);
  });

  test('excludes tree drill directives from analyzed totals', () {
    const verdicts = [
      AiVerdict(
        path: '/scan/cache',
        verdict: 'drill_down',
        confidence: 'high',
        reason: 'inspect children',
      ),
      AiVerdict(
        path: '/scan/cache/a.bin',
        verdict: 'keep',
        confidence: 'high',
        reason: 'retained child',
      ),
    ];

    final overview = buildAiAnalysisConclusionOverview(
      const AiResultOverviewBuildInput(
        targetLabel: 'scan',
        rootPath: '/scan',
        verdicts: verdicts,
        sizeByPath: {'/scan/cache': 200, '/scan/cache/a.bin': 100},
        rootSizeBytesHint: 100,
      ),
    );

    expect(overview.analyzedItemCount, 1);
    expect(overview.analyzedTotalBytes, 100);
    expect(overview.keepCount, 1);
  });

  test('buildAiAnalysisConclusionOverviewFromGroups uses group aggregates', () {
    final verdicts = List.generate(
      10,
      (i) => AiVerdict(
        path: '/home/Library/$i.bin',
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: 'cache',
      ),
    );
    final sizes = {for (var i = 0; i < 10; i++) '/home/Library/$i.bin': 100};
    var groups = groupAiResults(verdicts, sizes, rootPath: '/home');
    groups = capAiResultGroupsForDisplay(groups, sizes, maxItemsPerGroup: 2);
    final overview = buildAiAnalysisConclusionOverviewFromGroups(
      AiResultOverviewBuildInput(
        targetLabel: 'Home',
        rootPath: '/home',
        verdicts: const [],
        sizeByPath: sizes,
        fullCoverage: true,
        analyzedItemCountOverride: 10,
      ),
      groups,
    );
    expect(overview.analyzedItemCount, 10);
    expect(overview.safeBytes, 1000);
    expect(overview.directories.single.safeBytes, 1000);
  });

  test(
    'group overview preserves source counts after display items are capped',
    () {
      final verdicts = List.generate(
        10,
        (i) => AiVerdict(
          path: '/home/cache/$i.bin',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'cache',
          classificationSource: 'local:kb',
        ),
      );
      final sizes = {for (var i = 0; i < 10; i++) '/home/cache/$i.bin': 100};
      final groups = capAiResultGroupsForDisplay(
        groupAiResults(verdicts, sizes, rootPath: '/home'),
        sizes,
        maxItemsPerGroup: 2,
      );

      final overview = buildAiAnalysisConclusionOverviewFromGroups(
        AiResultOverviewBuildInput(
          targetLabel: 'Home',
          rootPath: '/home',
          verdicts: const [],
          sizeByPath: sizes,
          fullCoverage: true,
        ),
        groups,
      );

      expect(overview.localSafeCount, 10);
      expect(overview.aiSafeCount, 0);
    },
  );
}
