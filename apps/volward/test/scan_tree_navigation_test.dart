import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/scan_tree_navigation.dart';
import 'package:volward/snapshot_query.dart';

void main() {
  group('selectColumnRange', () {
    final items = [
      const SnapshotNodeRecord(
        name: 'a.txt',
        path: '/root/a.txt',
        isDirectory: false,
        sizeBytes: 1,
      ),
      const SnapshotNodeRecord(
        name: 'b.txt',
        path: '/root/b.txt',
        isDirectory: false,
        sizeBytes: 2,
      ),
      const SnapshotNodeRecord(
        name: 'c.txt',
        path: '/root/c.txt',
        isDirectory: false,
        sizeBytes: 3,
      ),
    ];

    test('returns the inclusive range in either direction', () {
      expect(
        selectColumnRange(
          items,
          anchorPath: '/root/a.txt',
          targetPath: '/root/c.txt',
        ).map((item) => item.path).toList(),
        ['/root/a.txt', '/root/b.txt', '/root/c.txt'],
      );
      expect(
        selectColumnRange(
          items,
          anchorPath: '/root/c.txt',
          targetPath: '/root/a.txt',
        ).map((item) => item.path).toList(),
        ['/root/a.txt', '/root/b.txt', '/root/c.txt'],
      );
    });

    test('returns empty when the anchor is no longer visible', () {
      expect(
        selectColumnRange(
          items,
          anchorPath: '/root/missing.txt',
          targetPath: '/root/c.txt',
        ),
        isEmpty,
      );
    });
  });

  group('toggleColumnSelection', () {
    final rootDirectory = ScanTreeNode(
      name: 'Documents',
      path: '/root/Documents',
      isDirectory: true,
    );
    final childDirectory = ScanTreeNode(
      name: 'Projects',
      path: '/root/Documents/Projects',
      isDirectory: true,
    );
    final file = ScanTreeNode(
      name: 'readme.txt',
      path: '/root/Documents/readme.txt',
      isDirectory: false,
      entryId: 'readme',
    );

    test('clicking a selected top-level directory returns to root', () {
      final next = toggleColumnSelection([rootDirectory], 0, rootDirectory);

      expect(next, isEmpty);
      expect(browsedDirectoryPath(next), isNull);
    });

    test('clicking a selected nested directory returns to its parent', () {
      final next = toggleColumnSelection(
        [rootDirectory, childDirectory],
        1,
        childDirectory,
      );

      expect(next, [rootDirectory]);
      expect(browsedDirectoryPath(next), '/root/Documents');
    });

    test('clicking a selected file clears file focus but keeps its parent', () {
      final next = toggleColumnSelection([rootDirectory, file], 1, file);

      expect(next, [rootDirectory]);
      expect(browsedDirectoryPath(next), '/root/Documents');
    });

    test('selecting a root file resets the refresh target to root', () {
      final next = toggleColumnSelection([rootDirectory], 0, file);

      expect(next, [file]);
      expect(browsedDirectoryPath(next), isNull);
    });
  });

  group('refreshColumnChain', () {
    ScanTreeNode buildTree({required int aFileCount}) {
      return ScanTreeNode(
        name: 'root',
        path: '/root',
        isDirectory: true,
        children: [
          ScanTreeNode(
            name: 'a',
            path: '/root/a',
            isDirectory: true,
            children: List.generate(
              aFileCount,
              (i) => ScanTreeNode(
                name: 'f$i.txt',
                path: '/root/a/f$i.txt',
                isDirectory: false,
              ),
            ),
          ),
          ScanTreeNode(name: 'b', path: '/root/b', isDirectory: true),
        ],
      );
    }

    test('re-resolves a matching path prefix to the new node instances', () {
      final oldRoot = buildTree(aFileCount: 0);
      final oldChain = [oldRoot.children.first]; // '/root/a', empty children

      final newRoot = buildTree(aFileCount: 3); // '/root/a' now has 3 files
      final refreshed = refreshColumnChain(newRoot, oldChain);

      expect(refreshed, hasLength(1));
      expect(refreshed.single.path, '/root/a');
      expect(refreshed.single.children, hasLength(3));
    });

    test('truncates the chain when a path no longer exists', () {
      final oldRoot = buildTree(aFileCount: 0);
      final oldChain = [
        oldRoot.children.first,
        ScanTreeNode(name: 'gone', path: '/root/a/gone', isDirectory: true),
      ];

      final newRoot = buildTree(aFileCount: 0);
      final refreshed = refreshColumnChain(newRoot, oldChain);

      expect(refreshed, hasLength(1));
      expect(refreshed.single.path, '/root/a');
    });

    test('returns an empty chain when nothing matches', () {
      final newRoot = buildTree(aFileCount: 0);
      final refreshed = refreshColumnChain(newRoot, [
        ScanTreeNode(name: 'x', path: '/root/x', isDirectory: true),
      ]);
      expect(refreshed, isEmpty);
    });
  });
}
