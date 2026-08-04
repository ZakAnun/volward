import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/snapshot_query.dart';
import 'package:volward/snapshot_view_cache.dart';
import 'package:volward/widgets/scan_filter_bar.dart';

void main() {
  test('index summary snapshot keeps only root metadata in Dart', () {
    final snapshot = ScanSnapshotState.fromIndexSummary({
      'snapshot_id': 'snap-index',
      'root_path': '/Users/test',
      'root_size_bytes': 4096,
      'scanned_at_ms': 123,
      'version': 7,
      'scan_state': 'Done',
      'reclaimable_estimate_bytes': 64,
      'entry_count': 3,
      'deletable_count': 2,
      'category_counts': {'Cache': 2, 'Media': 1},
      'deletable_counts': {'Cache': 2},
    });

    expect(snapshot.snapshotId, 'snap-index');
    expect(snapshot.filesInSnapshot, 3);
    expect(snapshot.deletableCount, 2);
    expect(snapshot.reclaimableEstimateBytes, 64);
    expect(snapshot.stats['files_in_snapshot'], 3);
    expect(snapshot.stats['scan_state'], 'Done');
    expect(snapshot.tree?.path, '/Users/test');
    expect(snapshot.tree?.children, isEmpty);
    expect(snapshot.hasFlatEntries, isFalse);
    expect(snapshot.categoryCounts['Cache'], 2);
    expect(snapshot.deletableCategoryCounts['Cache'], 2);
    expect(snapshot.extraFields.containsKey('tree'), isFalse);
    expect(snapshot.extraFields.containsKey('entries'), isFalse);
  });

  test('repeated category switches keep snapshot view cache bounded', () {
    final snapshot = ScanSnapshotState.fromWire({
      'snapshot_id': 'memory-regression',
      'entries': <Map<String, dynamic>>[],
      'tree': {
        'name': 'root',
        'path': '/root',
        'is_dir': true,
        'children': [
          {
            'name': 'Library',
            'path': '/root/Library',
            'is_dir': true,
            'children': [
              {
                'name': 'cache.db',
                'path': '/root/Library/cache.db',
                'is_dir': false,
                'entry_id': 'cache',
                'size_bytes': 10,
                'category': 'Cache',
                'deletable': true,
              },
              {
                'name': 'notes.txt',
                'path': '/root/Library/notes.txt',
                'is_dir': false,
                'entry_id': 'notes',
                'size_bytes': 20,
                'category': 'Document',
                'deletable': false,
              },
            ],
          },
        ],
      },
    });
    final cache = SnapshotViewCache<SnapshotQueryResult>(capacity: 2);
    const filters = [null, 'Cache'];

    for (var i = 0; i < 100; i++) {
      final key = SnapshotQueryKey(
        snapshotId: snapshot.snapshotId,
        version: 3,
        path: '/root/Library',
        categoryFilter: filters[i % 2],
        deletableOnly: i.isOdd,
        sortMode: ScanSortMode.nameAsc,
      );
      final cached = cache[key];
      if (cached == null) cache[key] = snapshot.catalog.query(key);
    }

    final stableKey = SnapshotQueryKey(
      snapshotId: snapshot.snapshotId,
      version: 3,
      path: '/root/Library',
      categoryFilter: 'Cache',
      deletableOnly: true,
      sortMode: ScanSortMode.nameAsc,
    );
    final stableSlice = cache[stableKey];
    expect(stableSlice, isNotNull);
    expect(cache[stableKey], same(stableSlice));

    final firstKey = SnapshotQueryKey(
      snapshotId: snapshot.snapshotId,
      version: 3,
      path: '/root/Library',
      categoryFilter: null,
      deletableOnly: false,
      sortMode: ScanSortMode.nameAsc,
    );
    expect(cache[firstKey], isNotNull);

    for (var i = 0; i < 100; i++) {
      final key = firstKey.copyWith(path: '/root/Library/$i');
      cache[key] = snapshot.catalog.query(key);
    }
    expect(
      cache[firstKey],
      isNull,
      reason: 'capacity must evict old slices instead of growing forever',
    );
    expect(
      cache[stableKey],
      isNull,
      reason: 'the bounded cache may evict older category slices',
    );
  });
}
