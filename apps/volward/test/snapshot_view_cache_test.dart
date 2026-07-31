import 'package:flutter_test/flutter_test.dart';
import 'package:volward/snapshot_view_cache.dart';
import 'package:volward/snapshot_query.dart';
import 'package:volward/widgets/scan_filter_bar.dart';

void main() {
  group('SnapshotViewCache', () {
    SnapshotQueryKey makeKey(String path, {int version = 1}) =>
        SnapshotQueryKey(
          snapshotId: 's',
          version: version,
          path: path,
          categoryFilter: null,
          deletableOnly: false,
          sortMode: ScanSortMode.sizeDesc,
        );

    test('stores and retrieves a value', () {
      final cache = SnapshotViewCache<List<int>>(capacity: 4);
      final key = makeKey('/root');
      cache[key] = [1, 2, 3];
      expect(cache[key], [1, 2, 3]);
    });

    test('containsKey returns true for stored key', () {
      final cache = SnapshotViewCache<List<int>>(capacity: 4);
      final key = makeKey('/root');
      cache[key] = [1];
      expect(cache.containsKey(key), isTrue);
    });

    test('containsKey returns false for missing key', () {
      final cache = SnapshotViewCache<List<int>>(capacity: 4);
      expect(cache.containsKey(makeKey('/root')), isFalse);
    });

    test('invalidatePath removes matching path and its children', () {
      final cache = SnapshotViewCache<List<int>>(capacity: 8);
      final k1 = makeKey('/root');
      final k2 = makeKey('/root/Documents');
      final k3 = makeKey('/root/Documents/sub');
      final k4 = makeKey('/root/Downloads');
      cache[k1] = [1];
      cache[k2] = [2];
      cache[k3] = [3];
      cache[k4] = [4];

      cache.invalidatePath('/root/Documents');

      expect(cache.containsKey(k1), isTrue,
          reason: '/root should be preserved');
      expect(cache.containsKey(k2), isFalse,
          reason: '/root/Documents should be removed');
      expect(cache.containsKey(k3), isFalse,
          reason: '/root/Documents/sub should be removed');
      expect(cache.containsKey(k4), isTrue,
          reason: '/root/Downloads should be preserved');
    });

    test('capacity eviction removes oldest entries', () {
      final cache = SnapshotViewCache<int>(capacity: 3);
      cache[makeKey('/a')] = 1;
      cache[makeKey('/b')] = 2;
      cache[makeKey('/c')] = 3;
      // Adding a 4th entry should evict /a (LRU)
      cache[makeKey('/d')] = 4;
      expect(cache.containsKey(makeKey('/a')), isFalse);
      expect(cache.containsKey(makeKey('/d')), isTrue);
    });

    test('version change in key produces cache miss', () {
      final cache = SnapshotViewCache<List<int>>(capacity: 4);
      final k1 = makeKey('/root', version: 1);
      final k2 = makeKey('/root', version: 2);
      cache[k1] = [1];
      expect(cache[k2], isNull, reason: 'different version must miss');
    });

    test('clear removes all entries', () {
      final cache = SnapshotViewCache<int>(capacity: 4);
      cache[makeKey('/a')] = 1;
      cache[makeKey('/b')] = 2;
      cache.clear();
      expect(cache.containsKey(makeKey('/a')), isFalse);
      expect(cache.containsKey(makeKey('/b')), isFalse);
    });
  });
}
