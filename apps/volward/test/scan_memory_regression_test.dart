import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/snapshot_query.dart';
import 'package:volward/snapshot_view_cache.dart';
import 'package:volward/widgets/scan_filter_bar.dart';

void main() {
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
