import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_snapshot_merge.dart';

void main() {
  group('mergeSubtreeIntoSnapshot', () {
    Map<String, dynamic> baseSnapshot() => {
          'snapshot_id': 'preview',
          'entries': <Map<String, dynamic>>[],
          'tree': {
            'name': 'root',
            'path': '/root',
            'is_dir': true,
            'size_bytes': 0,
            'scanned': false,
            'children': [
              {
                'name': 'Documents',
                'path': '/root/Documents',
                'is_dir': true,
                'size_bytes': 0,
                'scanned': false,
                'children': <Map<String, dynamic>>[],
              },
              {
                'name': 'Downloads',
                'path': '/root/Downloads',
                'is_dir': true,
                'size_bytes': 0,
                'scanned': false,
                'children': <Map<String, dynamic>>[],
              },
            ],
          },
        };

    test('replaces only the targeted subtree, leaving siblings untouched', () {
      final merged = mergeSubtreeIntoSnapshot(
        snapshot: baseSnapshot(),
        targetPath: '/root/Documents',
        subtreeTree: {
          'name': 'Documents',
          'path': '/root/Documents',
          'is_dir': true,
          'size_bytes': 500,
          'scanned': true,
          'children': [
            {
              'name': 'a.txt',
              'path': '/root/Documents/a.txt',
              'is_dir': false,
              'size_bytes': 500,
              'entry_id': 'e1',
              'scanned': true,
              'children': <Map<String, dynamic>>[],
            },
          ],
        },
        subtreeEntries: [
          {
            'id': 'e1',
            'path_or_uri': '/root/Documents/a.txt',
            'size_bytes': 500,
            'category': 'Unknown',
            'deletable': false,
          },
        ],
      );

      final tree = merged['tree'] as Map<String, dynamic>;
      final children = tree['children'] as List;

      final documents =
          children.firstWhere((c) => c['path'] == '/root/Documents') as Map;
      expect(documents['size_bytes'], 500);
      expect(documents['scanned'], isTrue);
      expect((documents['children'] as List), hasLength(1));

      final downloads =
          children.firstWhere((c) => c['path'] == '/root/Downloads') as Map;
      expect(downloads['scanned'], isFalse, reason: 'sibling must be untouched');

      expect(merged['entries'], hasLength(1));
    });

    test('overwrites an existing entry with the same id instead of duplicating', () {
      final snapshot = baseSnapshot();
      snapshot['entries'] = [
        {'id': 'e1', 'size_bytes': 100, 'deletable': true},
      ];

      final merged = mergeSubtreeIntoSnapshot(
        snapshot: snapshot,
        targetPath: '/root/Documents',
        subtreeTree:
            (snapshot['tree'] as Map)['children'][0] as Map<String, dynamic>,
        subtreeEntries: [
          {'id': 'e1', 'size_bytes': 200, 'deletable': true},
        ],
      );

      final entries = merged['entries'] as List;
      expect(entries, hasLength(1));
      expect(entries.single['size_bytes'], 200);
      expect(merged['reclaimable_estimate_bytes'], 200);
    });

    test('is a pure function that does not mutate the input snapshot', () {
      final snapshot = baseSnapshot();
      final originalTree = snapshot['tree'];

      mergeSubtreeIntoSnapshot(
        snapshot: snapshot,
        targetPath: '/root/Documents',
        subtreeTree: {
          'name': 'Documents',
          'path': '/root/Documents',
          'is_dir': true,
          'size_bytes': 999,
          'scanned': true,
          'children': <Map<String, dynamic>>[],
        },
        subtreeEntries: const [],
      );

      expect(identical(snapshot['tree'], originalTree), isTrue);
    });

    test('merging at the root path replaces the whole tree (checkpoint case)', () {
      final merged = mergeSubtreeIntoSnapshot(
        snapshot: baseSnapshot(),
        targetPath: '/root',
        subtreeTree: {
          'name': 'root',
          'path': '/root',
          'is_dir': true,
          'size_bytes': 1000,
          'scanned': true,
          'children': <Map<String, dynamic>>[],
        },
        subtreeEntries: const [],
      );

      final tree = merged['tree'] as Map<String, dynamic>;
      expect(tree['size_bytes'], 1000);
      expect(tree['scanned'], isTrue);
    });
  });
}
