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

      // Unique per preview target so UI caches invalidate on root switches.
      expect(snapshot['snapshot_id'], startsWith('preview-'));
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

    test('preview snapshots keep a root-specific snapshot id', () {
      final first = buildPreviewSnapshot(
        rootPath: '/Users/test',
        quickListEntries: const [],
      );
      final second = buildPreviewSnapshot(
        rootPath: '/Users/test/Documents',
        quickListEntries: const [],
      );

      // Distinct roots must produce distinct snapshot ids so UI caches keyed
      // on snapshot_id invalidate correctly across a root switch.
      expect(first['snapshot_id'], isNot(second['snapshot_id']));
    });

    test('preview snapshots only expose direct children at the first level',
        () {
      final snapshot = buildPreviewSnapshot(
        rootPath: '/Users/test',
        quickListEntries: const [
          {'path': '/Users/test/Documents', 'is_dir': true},
          {'path': '/Users/test/notes.txt', 'is_dir': false, 'size_bytes': 42},
        ],
      );

      final root = ScanTreeNode.fromSnapshotJson(
        snapshot['tree'] as Map<String, dynamic>,
      );
      expect(root.children, hasLength(2));
      expect(root.scanned, isFalse);
      // First level only — the directory child carries no grandchildren.
      final dir = root.children.firstWhere((c) => c.name == 'Documents');
      expect(dir.children, isEmpty);
    });
  });
}
