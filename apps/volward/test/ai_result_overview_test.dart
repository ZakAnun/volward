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
}
