import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/ai_result_groups.dart';
import 'package:volward/scan_tree.dart';

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
      rootPath: '/tmp',
    );

    expect(groups.map((group) => group.path), ['/tmp/project']);
    expect(groups.first.totalBytes, 1000);
    expect(groups.first.safeCount, 1);
    expect(groups.first.reviewCount, 1);
    expect(groups.first.keepCount, 2);
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
      const {'/root.log': 50},
      rootPath: '/tmp',
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

  test('groups by direct children of the scan root', () {
    final groups = groupAiResults(
      const [
        AiVerdict(
          path: '/tmp/project/cache/a.bin',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'Cache',
        ),
        AiVerdict(
          path: '/tmp/project/output/report.md',
          verdict: 'keep',
          confidence: 'high',
          reason: 'Document',
        ),
        AiVerdict(
          path: '/tmp/other/item.txt',
          verdict: 'keep',
          confidence: 'high',
          reason: 'Document',
        ),
      ],
      const {
        '/tmp/project/cache/a.bin': 300,
        '/tmp/project/output/report.md': 300,
        '/tmp/other/item.txt': 100,
      },
      rootPath: '/tmp',
    );

    expect(groups.map((group) => group.path), ['/tmp/project', '/tmp/other']);
    expect(groups.first.items, hasLength(2));
  });

  test('keeps a directory item in its own second-level group', () {
    final groups = groupAiResults(
      const [
        AiVerdict(
          path: '/tmp/project',
          verdict: 'review_needed',
          confidence: 'medium',
          reason: 'Project folder',
        ),
        AiVerdict(
          path: '/tmp/project/cache/a.bin',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'Cache',
        ),
      ],
      const {'/tmp/project/cache/a.bin': 100},
      rootPath: '/tmp',
      directoryPaths: {'/tmp/project'},
    );

    expect(groups.map((group) => group.path), ['/tmp/project']);
    expect(groups.first.items, hasLength(2));
  });

  test('normalizes Windows paths and keeps similarly named roots separate', () {
    final groups = groupAiResults(
      const [
        AiVerdict(
          path: r'C:\Users\me\Downloads\a.txt',
          verdict: 'keep',
          confidence: 'high',
          reason: 'a',
        ),
      ],
      const {r'C:\Users\me\Downloads\a.txt': 1},
      rootPath: r'C:\Users\me\Downloads',
    );

    expect(groups.single.path, normalizeFsPath(r'C:\Users\me\Downloads'));
  });

  test('groups order ties by path when review and size match', () {
    final groups = groupAiResults(
      const [
        AiVerdict(
          path: '/tmp/b/x',
          verdict: 'keep',
          confidence: 'high',
          reason: 'b',
        ),
        AiVerdict(
          path: '/tmp/a/x',
          verdict: 'keep',
          confidence: 'high',
          reason: 'a',
        ),
      ],
      const {'/tmp/b/x': 1, '/tmp/a/x': 1},
      rootPath: '/tmp',
    );

    expect(groups.map((g) => g.path), ['/tmp/a', '/tmp/b']);
  });

  test('ensureFirstLevelDirectoryGroups adds empty sibling folders', () {
    final groups = groupAiResults(
      const [
        AiVerdict(
          path: '/root/alpha/a.txt',
          verdict: 'review_needed',
          confidence: 'low',
          reason: 'r',
        ),
      ],
      const {'/root/alpha/a.txt': 1},
      rootPath: '/root',
    );
    final merged = ensureFirstLevelDirectoryGroups(groups, '/root', const [
      '/root/alpha',
      '/root/beta',
      '/root/gamma',
    ]);
    expect(merged.map((g) => g.path), [
      '/root/alpha',
      '/root/beta',
      '/root/gamma',
    ]);
    expect(merged[1].items, isEmpty);
  });

  test('firstLevelDirectoryUnderRoot maps nested files to top child', () {
    expect(
      firstLevelDirectoryUnderRoot('/root/alpha/deep/a.txt', '/root'),
      '/root/alpha',
    );
    expect(firstLevelDirectoryUnderRoot('/root/loose.txt', '/root'), '/root');
  });
}
