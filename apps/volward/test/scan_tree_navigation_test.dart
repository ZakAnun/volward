import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/scan_tree_navigation.dart';

void main() {
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
