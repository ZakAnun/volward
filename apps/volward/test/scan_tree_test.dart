import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_entry_record.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/scan_tree_filter.dart';
import 'package:volward/scan_tree_flatten.dart';

void main() {
  group('ScanTreeNode.fromSnapshotJson', () {
    test('parses tree and attaches entries by entry_id', () {
      final entriesById = {
        'e1': const ScanEntryRecord(
          id: 'e1',
          displayName: 'a.txt',
          pathOrUri: '/root/a.txt',
          sizeBytes: 100,
          category: 'Cache',
          deletable: true,
        ),
      };

      final root = ScanTreeNode.fromSnapshotJson({
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
      }, entriesById: entriesById);

      expect(root.name, 'root');
      expect(root.isDirectory, isTrue);
      expect(root.children, hasLength(1));
      expect(root.children.single.entry?.category, 'Cache');
      expect(root.children.single.entryId, 'e1');
    });
  });

  group('ScanTreeNode.scanned', () {
    test('defaults to true when constructed directly', () {
      final node = ScanTreeNode(name: 'a', path: '/a', isDirectory: true);
      expect(node.scanned, isTrue);
    });

    test('fromSnapshotJson reads an explicit false value', () {
      final node = ScanTreeNode.fromSnapshotJson({
        'name': 'a',
        'path': '/a',
        'is_dir': true,
        'scanned': false,
        'children': [],
      });
      expect(node.scanned, isFalse);
    });

    test('fromSnapshotJson defaults to true when the key is absent', () {
      final node = ScanTreeNode.fromSnapshotJson({
        'name': 'a',
        'path': '/a',
        'is_dir': true,
        'children': [],
      });
      expect(node.scanned, isTrue);
    });

    test('withAggregatedCounts preserves scanned on the copy', () {
      final root = ScanTreeNode(
        name: 'root',
        path: '/root',
        isDirectory: true,
        scanned: false,
        children: [
          ScanTreeNode(name: 'a', path: '/root/a', isDirectory: false),
        ],
      );
      final annotated = ScanTreeNode.withAggregatedCounts(root);
      expect(annotated.scanned, isFalse);
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
            entry: const ScanEntryRecord(
              id: '1',
              displayName: 'cache.txt',
              pathOrUri: '/root/cache.txt',
              sizeBytes: 0,
              category: 'Cache',
              deletable: true,
            ),
          ),
          ScanTreeNode(
            name: 'other.txt',
            path: '/root/other.txt',
            isDirectory: false,
            entry: const ScanEntryRecord(
              id: '2',
              displayName: 'other.txt',
              pathOrUri: '/root/other.txt',
              sizeBytes: 0,
              category: 'Unknown',
              deletable: false,
            ),
          ),
        ],
      );
    });

    test('keeps only matching files and prunes empty branches', () {
      final pruned = pruneTree(root, (entry) => entry.category == 'Cache');

      expect(pruned, isNotNull);
      expect(pruned!.children, hasLength(1));
      expect(pruned.children.single.name, 'cache.txt');
    });

    test('returns null when nothing matches', () {
      final pruned = pruneTree(root, (entry) => entry.category == 'Media');
      expect(pruned, isNull);
    });

    test('preserves scanned on the pruned copy', () {
      final unscannedRoot = ScanTreeNode(
        name: 'root',
        path: '/root',
        isDirectory: true,
        scanned: false,
        children: [
          ScanTreeNode(
            name: 'cache.txt',
            path: '/root/cache.txt',
            isDirectory: false,
            entry: const ScanEntryRecord(
              id: '1',
              displayName: 'cache.txt',
              pathOrUri: '/root/cache.txt',
              sizeBytes: 0,
              category: 'Cache',
              deletable: true,
            ),
          ),
        ],
      );
      final pruned = pruneTree(
        unscannedRoot,
        (entry) => entry.category == 'Cache',
      );
      expect(pruned!.scanned, isFalse);
    });
  });

  group('ScanTreeBuilder.build fallback', () {
    test(
      'builds tree from flat entries when snapshot tree has no children',
      () {
        final entries = [
          const ScanEntryRecord(
            id: 'e1',
            displayName: 'a.txt',
            pathOrUri: '/home/user/docs/a.txt',
            sizeBytes: 10,
            category: 'Unknown',
            deletable: false,
          ),
          const ScanEntryRecord(
            id: 'e2',
            displayName: 'b.txt',
            pathOrUri: '/home/user/docs/sub/b.txt',
            sizeBytes: 20,
            category: 'Cache',
            deletable: true,
          ),
        ];
        final tree = ScanTreeBuilder.build(
          entries: entries,
          rootPath: '/home/user',
        );
        expect(tree.children, isNotEmpty);
        expect(tree.fileCount, 2);
      },
    );

    test('rejects false path prefixes when inserting flat entries', () {
      expect(isUnderFsRoot('/home/me2/x.txt', '/home/me'), isFalse);
      expect(isUnderFsRoot('//server/shareextra/a', '//server/share'), isFalse);
      expect(isUnderFsRoot('/home/me/docs/a.txt', '/home/me'), isTrue);

      final entries = [
        const ScanEntryRecord(
          id: 'ok',
          displayName: 'a.txt',
          pathOrUri: '/home/me/docs/a.txt',
          sizeBytes: 1,
          category: 'Unknown',
          deletable: false,
        ),
        const ScanEntryRecord(
          id: 'bad',
          displayName: 'x.txt',
          pathOrUri: '/home/me2/x.txt',
          sizeBytes: 2,
          category: 'Unknown',
          deletable: false,
        ),
      ];
      final tree = ScanTreeBuilder.build(
        entries: entries,
        rootPath: '/home/me',
      );
      expect(tree.fileCount, 1);
      expect(
        tree.children.any((child) => child.path.contains('me2')),
        isFalse,
      );
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
          ScanTreeNode(name: 'c.txt', path: '/root/c.txt', isDirectory: false),
        ],
      );

      final annotated = ScanTreeNode.withAggregatedCounts(root);
      expect(annotated.subtreeFileCount, 3);
      expect(annotated.children.first.subtreeFileCount, 2);
      expect(annotated.fileCount, 3);
      expect(annotated.children.first.fileCount, 2);
    });

    test(
      'precomputes directory display bytes for UI sorting and scrolling',
      () {
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
                  sizeBytes: 10,
                ),
                ScanTreeNode(
                  name: 'b.txt',
                  path: '/root/dir/b.txt',
                  isDirectory: false,
                  sizeBytes: 20,
                ),
              ],
            ),
          ],
        );

        final annotated = ScanTreeNode.withAggregatedCounts(root);
        expect(annotated.displayBytes, 30);
        expect(annotated.children.single.displayBytes, 30);
      },
    );
  });

  group('defaultScanRootPath', () {
    test('defaultScanRootPath uses USERPROFILE on Windows', () {
      expect(
        defaultScanRootPath(
          environment: {'USERPROFILE': r'C:\Users\me', 'HOME': '/Users/me'},
          isWindows: () => true,
        ),
        'C:/Users/me',
      );
      expect(
        defaultScanRootPath(
          environment: {'HOME': '/home/me'},
          isWindows: () => false,
        ),
        '/home/me',
      );
    });
  });

  group('path helpers', () {
    test('normalize and parent handle windows and unc', () {
      expect(normalizeFsPath(r'C:\Users\me\a'), 'C:/Users/me/a');
      expect(normalizeFsPath('C:/'), 'C:/');
      expect(parentFsPath('C:/Users'), 'C:/');
      expect(parentFsPath('C:/file.txt'), 'C:/');
      expect(normalizeFsPath(r'\\server\share\a\b'), '//server/share/a/b');
      expect(parentFsPath('//server/share/a/b'), '//server/share/a');
      expect(joinFsPath('//server/share', 'a'), '//server/share/a');
      expect(normalizeFsPath('/home/me/a/'), '/home/me/a');
      expect(parentFsPath('/home/me/a'), '/home/me');
      expect(joinFsPath('/home/me', 'docs'), '/home/me/docs');
    });

    test('unc rejects false prefixes for parent floor semantics', () {
      expect(parentFsPath('//server/share/a'), '//server/share');
      expect(normalizeFsPath('//server/share/'), '//server/share');
      expect(isUnderFsRoot('//server/shareextra/a', '//server/share'), isFalse);
      expect(isUnderFsRoot('//server/share/a', '//server/share'), isTrue);
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
                entry: const ScanEntryRecord(
                  id: '1',
                  displayName: 'a1.txt',
                  pathOrUri: '/root/a/a1.txt',
                  sizeBytes: 0,
                  category: 'Unknown',
                  deletable: false,
                ),
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
