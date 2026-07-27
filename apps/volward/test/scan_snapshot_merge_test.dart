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

    test(
      'merging at the root path updates root fields but preserves children '
      'the checkpoint has not rediscovered yet (checkpoint case)',
      () {
        final merged = mergeSubtreeIntoSnapshot(
          snapshot: baseSnapshot(),
          targetPath: '/root',
          subtreeTree: {
            'name': 'root',
            'path': '/root',
            'is_dir': true,
            'size_bytes': 1000,
            'scanned': true,
            // A background scan's checkpoint often hasn't walked every
            // previously-known child yet — it must not wipe them out.
            'children': <Map<String, dynamic>>[],
          },
          subtreeEntries: const [],
        );

        final tree = merged['tree'] as Map<String, dynamic>;
        expect(tree['size_bytes'], 1000);
        expect(tree['scanned'], isTrue);

        final children = tree['children'] as List;
        expect(children, hasLength(2), reason: 'Documents/Downloads preserved');
        expect(
          children.any((c) => c['path'] == '/root/Documents'),
          isTrue,
        );
        expect(
          children.any((c) => c['path'] == '/root/Downloads'),
          isTrue,
        );
      },
    );

    test(
      'keeps an already-resolved child (e.g. a completed Wave-2 peek scan) '
      'instead of regressing it to a less-complete checkpoint view',
      () {
        final snapshot = baseSnapshot();
        (snapshot['tree'] as Map)['children'] = [
          {
            'name': 'Documents',
            'path': '/root/Documents',
            'is_dir': true,
            'size_bytes': 5000,
            'scanned': true,
            // peekScanned marks this node as authoritative (Wave-2 peek) so
            // _pickMoreComplete keeps it over a smaller incoming checkpoint.
            'peekScanned': true,
            'children': [
              {
                'name': 'a.txt',
                'path': '/root/Documents/a.txt',
                'is_dir': false,
                'size_bytes': 5000,
                'scanned': true,
                'children': <Map<String, dynamic>>[],
              },
            ],
          },
        ];

        final merged = mergeSubtreeIntoSnapshot(
          snapshot: snapshot,
          targetPath: '/root',
          subtreeTree: {
            'name': 'root',
            'path': '/root',
            'is_dir': true,
            'size_bytes': 0,
            'scanned': true,
            'children': [
              {
                'name': 'Documents',
                'path': '/root/Documents',
                'is_dir': true,
                // The main scan's own checkpoint only just touched this
                // directory and hasn't recursed into it yet.
                'size_bytes': 0,
                'children': <Map<String, dynamic>>[],
              },
            ],
          },
          subtreeEntries: const [],
        );

        final tree = merged['tree'] as Map<String, dynamic>;
        final documents = (tree['children'] as List)
            .firstWhere((c) => c['path'] == '/root/Documents') as Map;
        expect(documents['size_bytes'], 5000, reason: 'peeked data preserved');
        expect((documents['children'] as List), hasLength(1));
      },
    );

    test(
      'a prior full-scan node without an explicit scanned:true does NOT '
      'block a smaller rescan checkpoint (e.g. after files were deleted)',
      () {
        // Mimics a previous completed scan's tree as stored in
        // `_lastSnapshot`: Rust never serializes `scanned`, so the field
        // is absent. A rescan after the user deleted files must be allowed
        // to shrink sizes via ordinary (non-authoritative) checkpoints.
        final snapshot = baseSnapshot();
        (snapshot['tree'] as Map)['children'] = [
          {
            'name': 'Documents',
            'path': '/root/Documents',
            'is_dir': true,
            'size_bytes': 5000,
            // intentionally no `scanned` field
            'children': [
              {
                'name': 'a.txt',
                'path': '/root/Documents/a.txt',
                'is_dir': false,
                'size_bytes': 5000,
                'children': <Map<String, dynamic>>[],
              },
            ],
          },
        ];

        final merged = mergeSubtreeIntoSnapshot(
          snapshot: snapshot,
          targetPath: '/root',
          subtreeTree: {
            'name': 'root',
            'path': '/root',
            'is_dir': true,
            'size_bytes': 800,
            'children': [
              {
                'name': 'Documents',
                'path': '/root/Documents',
                'is_dir': true,
                'size_bytes': 800,
                'children': [
                  {
                    'name': 'a.txt',
                    'path': '/root/Documents/a.txt',
                    'is_dir': false,
                    'size_bytes': 800,
                    'children': <Map<String, dynamic>>[],
                  },
                ],
              },
            ],
          },
          subtreeEntries: const [],
        );

        final documents = ((merged['tree'] as Map)['children'] as List)
            .firstWhere((c) => c['path'] == '/root/Documents') as Map;
        expect(
          documents['size_bytes'],
          800,
          reason: 'rescan checkpoint must shrink past a stale prior-scan size',
        );
      },
    );

    test(
      'checkpoint rediscovery clears preview scanned:false on that directory '
      'immediately (does not wait for full-scan Done)',
      () {
        final snapshot = baseSnapshot(); // Documents + Downloads scanned:false

        final merged = mergeSubtreeIntoSnapshot(
          snapshot: snapshot,
          targetPath: '/root',
          subtreeTree: {
            'name': 'root',
            'path': '/root',
            'is_dir': true,
            'size_bytes': 100,
            'children': [
              {
                'name': 'Documents',
                'path': '/root/Documents',
                'is_dir': true,
                'size_bytes': 100,
                // Rust checkpoint: no scanned field
                'children': [
                  {
                    'name': 'a.txt',
                    'path': '/root/Documents/a.txt',
                    'is_dir': false,
                    'size_bytes': 100,
                    'children': <Map<String, dynamic>>[],
                  },
                ],
              },
            ],
          },
          subtreeEntries: const [],
        );

        final children = (merged['tree'] as Map)['children'] as List;
        final documents =
            children.firstWhere((c) => c['path'] == '/root/Documents') as Map;
        final downloads =
            children.firstWhere((c) => c['path'] == '/root/Downloads') as Map;

        expect(documents['scanned'], isTrue,
            reason: 'rediscovered dir must drop the preview spinner');
        expect(documents['size_bytes'], 100);
        expect(downloads['scanned'], isFalse,
            reason: 'dirs not yet in this checkpoint keep their spinner');
      },
    );

    test(
      'when a peeked dir loses the size race, children are upserted so the '
      'peeked grandchild is not wiped by a partial checkpoint',
      () {
        final snapshot = baseSnapshot();
        (snapshot['tree'] as Map)['children'] = [
          {
            'name': 'Documents',
            'path': '/root/Documents',
            'is_dir': true,
            'size_bytes': 100,
            'scanned': true,
            // peekScanned marks this node as authoritative so children are
            // deep-merged rather than wholesale-replaced by the checkpoint.
            'peekScanned': true,
            'children': [
              {
                'name': 'peeked.txt',
                'path': '/root/Documents/peeked.txt',
                'is_dir': false,
                'size_bytes': 100,
                'scanned': true,
                'children': <Map<String, dynamic>>[],
              },
            ],
          },
        ];

        final merged = mergeSubtreeIntoSnapshot(
          snapshot: snapshot,
          targetPath: '/root',
          subtreeTree: {
            'name': 'root',
            'path': '/root',
            'is_dir': true,
            'size_bytes': 500,
            'children': [
              {
                'name': 'Documents',
                'path': '/root/Documents',
                'is_dir': true,
                // Larger than the peeked size → adopt checkpoint, but must
                // upsert children rather than wholesale-replace.
                'size_bytes': 500,
                'children': [
                  {
                    'name': 'new.txt',
                    'path': '/root/Documents/new.txt',
                    'is_dir': false,
                    'size_bytes': 500,
                    'children': <Map<String, dynamic>>[],
                  },
                ],
              },
            ],
          },
          subtreeEntries: const [],
        );

        final documents = ((merged['tree'] as Map)['children'] as List)
            .firstWhere((c) => c['path'] == '/root/Documents') as Map;
        final kids = documents['children'] as List;
        expect(documents['scanned'], isTrue);
        expect(documents['size_bytes'], 500);
        expect(kids.any((c) => c['path'] == '/root/Documents/peeked.txt'), isTrue);
        expect(kids.any((c) => c['path'] == '/root/Documents/new.txt'), isTrue);
      },
    );

    test(
      'preview dirs (scanned:false) wholesale-adopt checkpoint children '
      'without deep-preserving stale preview-only grandchildren',
      () {
        final snapshot = baseSnapshot();
        (snapshot['tree'] as Map)['children'] = [
          {
            'name': 'Documents',
            'path': '/root/Documents',
            'is_dir': true,
            'size_bytes': 0,
            'scanned': false,
            'children': [
              {
                'name': 'stale-preview-only',
                'path': '/root/Documents/stale-preview-only',
                'is_dir': true,
                'size_bytes': 0,
                'scanned': false,
                'children': <Map<String, dynamic>>[],
              },
            ],
          },
        ];

        final merged = mergeSubtreeIntoSnapshot(
          snapshot: snapshot,
          targetPath: '/root',
          subtreeTree: {
            'name': 'root',
            'path': '/root',
            'is_dir': true,
            'size_bytes': 50,
            'children': [
              {
                'name': 'Documents',
                'path': '/root/Documents',
                'is_dir': true,
                'size_bytes': 50,
                'children': [
                  {
                    'name': 'real.txt',
                    'path': '/root/Documents/real.txt',
                    'is_dir': false,
                    'size_bytes': 50,
                    'children': <Map<String, dynamic>>[],
                  },
                ],
              },
            ],
          },
          subtreeEntries: const [],
        );

        final documents = ((merged['tree'] as Map)['children'] as List)
            .firstWhere((c) => c['path'] == '/root/Documents') as Map;
        final kids = documents['children'] as List;
        expect(documents['scanned'], isTrue);
        expect(kids, hasLength(1));
        expect(kids.single['path'], '/root/Documents/real.txt');
        expect(
          kids.any((c) => c['path'] == '/root/Documents/stale-preview-only'),
          isFalse,
          reason: 'non-peek dirs must not pay for deep upsert',
        );
      },
    );

    test('adopts a newly-discovered child the checkpoint brings that was not known before', () {
      final merged = mergeSubtreeIntoSnapshot(
        snapshot: baseSnapshot(),
        targetPath: '/root',
        subtreeTree: {
          'name': 'root',
          'path': '/root',
          'is_dir': true,
          'size_bytes': 0,
          'scanned': true,
          'children': [
            {
              'name': 'Movies',
              'path': '/root/Movies',
              'is_dir': true,
              'size_bytes': 100,
              'children': <Map<String, dynamic>>[],
            },
          ],
        },
        subtreeEntries: const [],
      );

      final children = (merged['tree'] as Map)['children'] as List;
      expect(children, hasLength(3), reason: 'Documents + Downloads + new Movies');
      expect(children.any((c) => c['path'] == '/root/Movies'), isTrue);
    });

    test(
      'checkpoint rediscovery stamps scanned:true recursively on deeply-nested dirs',
      () {
        // Three-level tree: root → Documents → SubFolder (all scanned:false).
        // A checkpoint that lists both Documents and SubFolder must clear the
        // spinner on both levels immediately, not just the outermost one.
        final snapshot = {
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
                'children': [
                  {
                    'name': 'SubFolder',
                    'path': '/root/Documents/SubFolder',
                    'is_dir': true,
                    'size_bytes': 0,
                    'scanned': false,
                    'children': <Map<String, dynamic>>[],
                  },
                ],
              },
            ],
          },
        };

        final merged = mergeSubtreeIntoSnapshot(
          snapshot: snapshot,
          targetPath: '/root',
          subtreeTree: {
            'name': 'root',
            'path': '/root',
            'is_dir': true,
            'size_bytes': 300,
            // Checkpoint lists Documents and SubFolder — both should be stamped.
            'children': [
              {
                'name': 'Documents',
                'path': '/root/Documents',
                'is_dir': true,
                'size_bytes': 300,
                'children': [
                  {
                    'name': 'SubFolder',
                    'path': '/root/Documents/SubFolder',
                    'is_dir': true,
                    'size_bytes': 300,
                    'children': <Map<String, dynamic>>[],
                  },
                ],
              },
            ],
          },
          subtreeEntries: const [],
        );

        final tree = merged['tree'] as Map<String, dynamic>;
        final documents = (tree['children'] as List)
            .firstWhere((c) => c['path'] == '/root/Documents') as Map;
        final subFolder = (documents['children'] as List)
            .firstWhere((c) => c['path'] == '/root/Documents/SubFolder') as Map;

        expect(documents['scanned'], isTrue,
            reason: 'Documents (level-2) must be stamped scanned:true');
        expect(subFolder['scanned'], isTrue,
            reason: 'SubFolder (level-3) must be stamped scanned:true recursively');
        expect(documents['size_bytes'], 300);
        expect(subFolder['size_bytes'], 300);
      },
    );

    test('adopts checkpoint data once it progresses past the existing state', () {
      final merged = mergeSubtreeIntoSnapshot(
        snapshot: baseSnapshot(),
        targetPath: '/root',
        subtreeTree: {
          'name': 'root',
          'path': '/root',
          'is_dir': true,
          'size_bytes': 200,
          'scanned': true,
          'children': [
            {
              'name': 'Documents',
              'path': '/root/Documents',
              'is_dir': true,
              'size_bytes': 200,
              'scanned': true,
              'children': <Map<String, dynamic>>[],
            },
          ],
        },
        subtreeEntries: const [],
      );

      final documents = ((merged['tree'] as Map)['children'] as List)
          .firstWhere((c) => c['path'] == '/root/Documents') as Map;
      expect(documents['size_bytes'], 200);
      expect(documents['scanned'], isTrue);
    });

    test(
      'an authoritative (peek) merge trusts the new data wholesale, even '
      'when it is smaller than the old data — e.g. a file was deleted',
      () {
        final snapshot = baseSnapshot();
        (snapshot['tree'] as Map)['children'] = [
          {
            'name': 'Documents',
            'path': '/root/Documents',
            'is_dir': true,
            'size_bytes': 5000,
            'scanned': true,
            'children': [
              {
                'name': 'a.txt',
                'path': '/root/Documents/a.txt',
                'is_dir': false,
                'size_bytes': 3000,
                'scanned': true,
                'children': <Map<String, dynamic>>[],
              },
              {
                'name': 'deleted.txt',
                'path': '/root/Documents/deleted.txt',
                'is_dir': false,
                'size_bytes': 2000,
                'scanned': true,
                'children': <Map<String, dynamic>>[],
              },
            ],
          },
        ];

        // A fresh, complete peek re-scan of /root/Documents that no longer
        // finds deleted.txt (it was removed from disk in the meantime).
        final merged = mergeSubtreeIntoSnapshot(
          snapshot: snapshot,
          targetPath: '/root/Documents',
          subtreeTree: {
            'name': 'Documents',
            'path': '/root/Documents',
            'is_dir': true,
            'size_bytes': 3000,
            'scanned': true,
            'children': [
              {
                'name': 'a.txt',
                'path': '/root/Documents/a.txt',
                'is_dir': false,
                'size_bytes': 3000,
                'scanned': true,
                'children': <Map<String, dynamic>>[],
              },
            ],
          },
          subtreeEntries: const [],
          replacementIsAuthoritative: true,
        );

        final documents = ((merged['tree'] as Map)['children'] as List)
            .firstWhere((c) => c['path'] == '/root/Documents') as Map;
        expect(documents['size_bytes'], 3000, reason: 'trusts the fresh, smaller size');
        final children = documents['children'] as List;
        expect(children, hasLength(1));
        expect(
          children.any((c) => c['path'] == '/root/Documents/deleted.txt'),
          isFalse,
          reason: 'authoritative peek result drops the deleted file',
        );
      },
    );

    test(
      'an authoritative merge drops stale entries whose path was under the '
      'peeked subtree but is absent from the fresh peek result',
      () {
        final snapshot = baseSnapshot();
        snapshot['entries'] = [
          {
            'id': 'e-deleted',
            'path_or_uri': '/root/Documents/deleted.txt',
            'size_bytes': 2000,
            'category': 'Cache',
            'deletable': true,
          },
          {
            'id': 'e-other',
            'path_or_uri': '/root/Downloads/keep.txt',
            'size_bytes': 500,
            'category': 'Cache',
            'deletable': true,
          },
        ];

        final merged = mergeSubtreeIntoSnapshot(
          snapshot: snapshot,
          targetPath: '/root/Documents',
          subtreeTree: {
            'name': 'Documents',
            'path': '/root/Documents',
            'is_dir': true,
            'size_bytes': 0,
            'scanned': true,
            'children': <Map<String, dynamic>>[],
          },
          // The fresh peek re-scan no longer finds deleted.txt.
          subtreeEntries: const [],
          replacementIsAuthoritative: true,
        );

        final entries = merged['entries'] as List;
        expect(
          entries.any((e) => e['id'] == 'e-deleted'),
          isFalse,
          reason: 'stale entry under the peeked path must be dropped',
        );
        expect(
          entries.any((e) => e['id'] == 'e-other'),
          isTrue,
          reason: 'entries outside the peeked subtree must be untouched',
        );
        expect(merged['reclaimable_estimate_bytes'], 500);
      },
    );
  });
}
