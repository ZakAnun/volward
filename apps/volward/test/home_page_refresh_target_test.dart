import 'package:flutter_test/flutter_test.dart';
import 'package:volward/home_page.dart';
import 'package:volward/scan_tree.dart';

void main() {
  group('refreshPathFromFocus', () {
    test('returns focused directory path when a directory is focused', () {
      final focused = ScanTreeNode(
        name: 'Documents',
        path: '/root/Documents',
        isDirectory: true,
        sizeBytes: 100,
        entryId: null,
        children: const [],
      );
      expect(
        refreshPathFromFocus(rootPath: '/root', focused: focused),
        '/root/Documents',
      );
    });

    test('falls back to rootPath when focused node is a file', () {
      final focused = ScanTreeNode(
        name: 'a.txt',
        path: '/root/a.txt',
        isDirectory: false,
        sizeBytes: 40,
        entryId: 'e1',
        children: const [],
      );
      expect(
        refreshPathFromFocus(rootPath: '/root', focused: focused),
        '/root',
      );
    });

    test('falls back to rootPath when focused is null', () {
      expect(refreshPathFromFocus(rootPath: '/root', focused: null), '/root');
    });

    test('works with deeply nested directory', () {
      final focused = ScanTreeNode(
        name: 'cache',
        path: '/root/Library/Application Support/cache',
        isDirectory: true,
        sizeBytes: 0,
        entryId: null,
        children: const [],
      );
      expect(
        refreshPathFromFocus(rootPath: '/root', focused: focused),
        '/root/Library/Application Support/cache',
      );
    });
  });

  group('deleteTargetFromFocus', () {
    test('returns focused directory path for directory nodes', () {
      final focused = ScanTreeNode(
        name: 'Documents',
        path: '/root/Documents',
        isDirectory: true,
        sizeBytes: 100,
        entryId: null,
        children: const [],
      );
      expect(deleteTargetFromFocus(focused), '/root/Documents');
    });

    test('returns entry id for selected files when available', () {
      final focused = ScanTreeNode(
        name: 'a.txt',
        path: '/root/a.txt',
        isDirectory: false,
        sizeBytes: 40,
        entryId: 'e1',
        children: const [],
      );
      expect(deleteTargetFromFocus(focused), 'e1');
    });

    test('falls back to the node path when no entry id exists', () {
      final focused = ScanTreeNode(
        name: 'a.txt',
        path: '/root/a.txt',
        isDirectory: false,
        sizeBytes: 40,
        entryId: null,
        children: const [],
      );
      expect(deleteTargetFromFocus(focused), '/root/a.txt');
    });

    test('blocks protected system nodes', () {
      final focused = ScanTreeNode(
        name: 'System',
        path: '/System',
        isDirectory: true,
        sizeBytes: 0,
        entryId: null,
        category: 'System',
        children: const [],
      );
      expect(deleteTargetFromFocus(focused), isNull);
    });
  });
}
