import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_preview.dart';
import 'package:volward/scan_tree.dart';

void main() {
  group('buildPreviewSnapshot', () {
    test('wraps quick-list entries into a renderable snapshot shape', () {
      final snapshot = buildPreviewSnapshot(
        rootPath: '/Users/test',
        quickListEntries: [
          {'path': '/Users/test/Documents', 'is_dir': true},
          {'path': '/Users/test/notes.txt', 'is_dir': false, 'size_bytes': 42},
        ],
      );

      expect(snapshot['snapshot_id'], 'preview');
      final tree = snapshot['tree'] as Map<String, dynamic>;
      expect(tree['scanned'], isFalse);
      expect(tree['path'], '/Users/test');

      final root = ScanTreeNode.fromSnapshotJson(tree);
      expect(root.children, hasLength(2));

      final dir = root.children.firstWhere((c) => c.name == 'Documents');
      expect(dir.isDirectory, isTrue);
      expect(dir.scanned, isFalse);

      final file = root.children.firstWhere((c) => c.name == 'notes.txt');
      expect(file.isDirectory, isFalse);
      expect(file.scanned, isTrue);
      expect(file.sizeBytes, 42);
    });

    test('handles an empty directory listing', () {
      final snapshot = buildPreviewSnapshot(
        rootPath: '/Users/test',
        quickListEntries: const [],
      );
      final tree = snapshot['tree'] as Map<String, dynamic>;
      expect(tree['children'], isEmpty);
    });

    test('strips a trailing slash from the root path when naming the root', () {
      final snapshot = buildPreviewSnapshot(
        rootPath: '/Users/test/',
        quickListEntries: const [],
      );
      final tree = snapshot['tree'] as Map<String, dynamic>;
      expect(tree['name'], 'test');
    });
  });
}
