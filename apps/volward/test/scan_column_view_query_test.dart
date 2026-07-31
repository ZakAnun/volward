import 'package:flutter_test/flutter_test.dart';
import 'package:volward/snapshot_query.dart';

void main() {
  group('SnapshotNodeRecord', () {
    test('carries all fields needed by the column view', () {
      const node = SnapshotNodeRecord(
        path: '/root/Documents/a.txt',
        name: 'a.txt',
        isDirectory: false,
        sizeBytes: 40,
        entryId: 'e1',
        category: 'Cache',
        deletable: true,
        scanned: true,
      );
      expect(node.path, '/root/Documents/a.txt');
      expect(node.name, 'a.txt');
      expect(node.isDirectory, isFalse);
      expect(node.sizeBytes, 40);
      expect(node.entryId, 'e1');
      expect(node.category, 'Cache');
      expect(node.deletable, isTrue);
      expect(node.scanned, isTrue);
    });

    test('fromJson parses all fields correctly', () {
      final json = <String, dynamic>{
        'path': '/root/Downloads',
        'name': 'Downloads',
        'is_directory': true,
        'size_bytes': 1024,
        'entry_id': null,
        'category': 'Folder',
        'deletable': false,
        'scanned': true,
      };
      final node = SnapshotNodeRecord.fromJson(json);
      expect(node.path, '/root/Downloads');
      expect(node.isDirectory, isTrue);
      expect(node.sizeBytes, 1024);
      expect(node.deletable, isFalse);
    });

    test('fromJson uses defaults for missing optional fields', () {
      final json = <String, dynamic>{
        'path': '/root/x',
        'name': 'x',
        'is_directory': false,
        'size_bytes': 0,
      };
      final node = SnapshotNodeRecord.fromJson(json);
      expect(node.deletable, isFalse);
      expect(node.scanned, isTrue);
      expect(node.entryId, isNull);
    });

    test('toScanTreeNode converts path and name correctly', () {
      const node = SnapshotNodeRecord(
        path: '/root/Documents',
        name: 'Documents',
        isDirectory: true,
        sizeBytes: 512,
        scanned: false,
      );
      final treeNode = node.toScanTreeNode();
      expect(treeNode.path, '/root/Documents');
      expect(treeNode.name, 'Documents');
      expect(treeNode.isDirectory, isTrue);
      expect(treeNode.scanned, isFalse);
    });

    test('directory node defaults: deletable=false, scanned=true', () {
      const node = SnapshotNodeRecord(
        path: '/root/dir',
        name: 'dir',
        isDirectory: true,
        sizeBytes: 0,
      );
      expect(node.deletable, isFalse);
      expect(node.scanned, isTrue);
    });
  });
}
