import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/ai_result_groups.dart';

void main() {
  test('groups preserve paths and summarize verdicts', () {
    final groups = groupAiResults(
      const [
        AiVerdict(
          path: '/tmp/project/cache/a.bin',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'Rebuildable cache',
        ),
        AiVerdict(
          path: '/tmp/project/cache/b.bin',
          verdict: 'review_needed',
          confidence: 'medium',
          reason: 'Recent output',
        ),
        AiVerdict(
          path: '/tmp/project/output/report.md',
          verdict: 'keep',
          confidence: 'high',
          reason: 'User document',
        ),
        AiVerdict(
          path: '/tmp/project/output/notes.txt',
          verdict: 'keep',
          confidence: 'high',
          reason: 'User notes',
        ),
      ],
      const {
        '/tmp/project/cache/a.bin': 100,
        '/tmp/project/cache/b.bin': 200,
        '/tmp/project/output/report.md': 300,
        '/tmp/project/output/notes.txt': 400,
      },
    );

    expect(groups.map((group) => group.path), [
      '/tmp/project/cache',
      '/tmp/project/output',
    ]);
    expect(groups.first.totalBytes, 300);
    expect(groups.first.safeCount, 1);
    expect(groups.first.reviewCount, 1);
    expect(groups.first.keepCount, 0);
    expect(groups.last.totalBytes, 700);
    expect(groups.last.safeCount, 0);
    expect(groups.last.reviewCount, 0);
    expect(groups.last.keepCount, 2);
  });

  test('groups keep root-level paths and duplicate verdict items visible', () {
    final verdicts = groupAiResults(
      const [
        AiVerdict(
          path: '/root.log',
          verdict: 'review_needed',
          confidence: 'medium',
          reason: 'Needs review',
        ),
        AiVerdict(
          path: '/root.log',
          verdict: 'keep',
          confidence: 'high',
          reason: 'Duplicate path stays visible',
        ),
        AiVerdict(
          path: '/tmp/project/cache.bin',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'Cache',
        ),
      ],
      const {
        '/root.log': 50,
      },
    );

    expect(verdicts.map((group) => group.path), ['/', '/tmp/project']);
    expect(verdicts.first.totalBytes, 100);
    expect(verdicts.first.reviewCount, 1);
    expect(verdicts.first.keepCount, 1);
    expect(verdicts.first.items, hasLength(2));
    expect(verdicts.first.items.map((item) => item.path), [
      '/root.log',
      '/root.log',
    ]);
    expect(verdicts.last.totalBytes, 0);
    expect(verdicts.last.safeCount, 1);
    expect(verdicts.last.reviewCount, 0);
    expect(verdicts.last.keepCount, 0);
  });

  test('groups order ties by path when review and size match', () {
    final groups = groupAiResults(
      const [
        AiVerdict(
          path: '/tmp/beta/one.log',
          verdict: 'review_needed',
          confidence: 'medium',
          reason: 'Needs review',
        ),
        AiVerdict(
          path: '/tmp/alpha/two.log',
          verdict: 'review_needed',
          confidence: 'medium',
          reason: 'Needs review',
        ),
      ],
      const {
        '/tmp/beta/one.log': 25,
        '/tmp/alpha/two.log': 25,
      },
    );

    expect(groups.map((group) => group.path), [
      '/tmp/alpha',
      '/tmp/beta',
    ]);
  });
}
