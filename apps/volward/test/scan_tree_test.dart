import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/scan_tree_filter.dart';
import 'package:volward/scan_tree_flatten.dart';

void main() {
  group('ScanTreeNode.fromSnapshotJson', () {
    test('parses tree and attaches entries by entry_id', () {
      final entriesById = {
        'e1': {
          'id': 'e1',
          'category': 'Cache',
          'deletable': true,
          'size_bytes': 100,
        },
      };

      final root = ScanTreeNode.fromSnapshotJson(
        {
          'name': 'root',
          'path': '/root',
          'is_dir': true,
          'size_bytes': 100,
          'entry_id': null,
          'children': [
            {
              'name': 'a.txt',
              'path': '/root/a.txt',
              'is_dir': false,
              'size_bytes': 100,
              'entry_id': 'e1',
              'children': [],
            },
          ],
        },
        entriesById: entriesById,
      );

      expect(root.name, 'root');
      expect(root.isDirectory, isTrue);
      expect(root.children, hasLength(1));
      expect(root.children.single.entry?['category'], 'Cache');
      expect(root.children.single.entryId, 'e1');
    });
  });

  group('pruneTree', () {
    late ScanTreeNode root;

    setUp(() {
      root = ScanTreeNode(
        name: 'root',
        path: '/root',
        isDirectory: true,
        children: [
          ScanTreeNode(
            name: 'cache.txt',
            path: '/root/cache.txt',
            isDirectory: false,
            entry: {'id': '1', 'category': 'Cache', 'deletable': true},
          ),
          ScanTreeNode(
            name: 'other.txt',
            path: '/root/other.txt',
            isDirectory: false,
            entry: {'id': '2', 'category': 'Unknown', 'deletable': false},
          ),
        ],
      );
    });

    test('keeps only matching files and prunes empty branches', () {
      final pruned = pruneTree(
        root,
        (entry) => entry['category'] == 'Cache',
      );

      expect(pruned, isNotNull);
      expect(pruned!.children, hasLength(1));
      expect(pruned.children.single.name, 'cache.txt');
    });

    test('returns null when nothing matches', () {
      final pruned = pruneTree(
        root,
        (entry) => entry['category'] == 'Media',
      );
      expect(pruned, isNull);
    });
  });

  group('ScanTreeBuilder.build fallback', () {
    test('builds tree from flat entries when snapshot tree has no children', () {
      final entries = [
        {
          'id': 'e1',
          'path_or_uri': '/home/user/docs/a.txt',
          'size_bytes': 10,
          'category': 'Unknown',
          'deletable': false,
        },
        {
          'id': 'e2',
          'path_or_uri': '/home/user/docs/sub/b.txt',
          'size_bytes': 20,
          'category': 'Cache',
          'deletable': true,
        },
      ];
      final tree = ScanTreeBuilder.build(entries: entries, rootPath: '/home/user');
      expect(tree.children, isNotEmpty);
      expect(tree.fileCount, 2);
    });
  });

  group('ScanTreeNode.withAggregatedCounts', () {
    test('fills subtreeFileCount for every directory', () {
      final root = ScanTreeNode(
        name: 'root',
        path: '/root',
        isDirectory: true,
        children: [
          ScanTreeNode(
            name: 'dir',
            path: '/root/dir',
            isDirectory: true,
            children: [
              ScanTreeNode(
                name: 'a.txt',
                path: '/root/dir/a.txt',
                isDirectory: false,
              ),
              ScanTreeNode(
                name: 'b.txt',
                path: '/root/dir/b.txt',
                isDirectory: false,
              ),
            ],
          ),
          ScanTreeNode(
            name: 'c.txt',
            path: '/root/c.txt',
            isDirectory: false,
          ),
        ],
      );

      final annotated = ScanTreeNode.withAggregatedCounts(root);
      expect(annotated.subtreeFileCount, 3);
      expect(annotated.children.first.subtreeFileCount, 2);
      expect(annotated.fileCount, 3);
      expect(annotated.children.first.fileCount, 2);
    });
  });

  group('flattenVisible', () {
    test('only includes expanded branches', () {
      final root = ScanTreeNode(
        name: 'root',
        path: '/root',
        isDirectory: true,
        children: [
          ScanTreeNode(
            name: 'a',
            path: '/root/a',
            isDirectory: true,
            children: [
              ScanTreeNode(
                name: 'a1.txt',
                path: '/root/a/a1.txt',
                isDirectory: false,
                entry: {'id': '1'},
              ),
            ],
          ),
          ScanTreeNode(
            name: 'b',
            path: '/root/b',
            isDirectory: true,
            children: const [],
          ),
        ],
      );

      final rowsCollapsed = flattenVisible(root, {'/root'});
      expect(rowsCollapsed.map((r) => r.node.path).toList(), [
        '/root',
        '/root/a',
        '/root/b',
      ]);

      final rowsExpandedA = flattenVisible(root, {'/root', '/root/a'});
      expect(rowsExpandedA.map((r) => r.node.path).toList(), [
        '/root',
        '/root/a',
        '/root/a/a1.txt',
        '/root/b',
      ]);
    });
  });
}
