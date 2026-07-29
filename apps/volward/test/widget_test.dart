import 'package:flutter_test/flutter_test.dart';
import 'package:volward/snapshot_query.dart';
import 'package:volward/snapshot_view_cache.dart';
import 'package:volward/widgets/scan_filter_bar.dart';

void main() {
  test('volward test harness loads', () {
    // Full widget tests require libvolward_facade.dylib; run integration tests on macOS.
    expect(true, isTrue);
  });

  test('repeated snapshot view access reuses the cached result', () {
    const key = SnapshotQueryKey(
      snapshotId: 'snapshot',
      version: 7,
      path: '/root',
      categoryFilter: null,
      deletableOnly: false,
      sortMode: ScanSortMode.nameAsc,
    );
    final cache = SnapshotViewCache<Object>(capacity: 2);
    final result = Object();
    cache[key] = result;

    for (var i = 0; i < 100; i++) {
      expect(cache[key], same(result));
    }
  });
}
