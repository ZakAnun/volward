import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_entry_record.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/snapshot_catalog.dart';
import 'package:volward/snapshot_query.dart';
import 'package:volward/snapshot_view_cache.dart';
import 'package:volward/widgets/scan_filter_bar.dart';

void main() {
  test('queries direct children and invalidates cached path prefixes', () {
    final snapshot = ScanSnapshotState(
      snapshotId: 'snap-1',
      scannedAtMs: 1,
      stats: const {},
      reclaimableEstimateBytes: 0,
      tree: ScanTreeNode(
        name: 'root',
        path: '/root',
        isDirectory: true,
        children: [
          ScanTreeNode(
            name: 'Library',
            path: '/root/Library',
            isDirectory: true,
            children: [
              ScanTreeNode(
                name: 'cache.db',
                path: '/root/Library/cache.db',
                isDirectory: false,
                entry: const ScanEntryRecord(
                  id: 'cache',
                  displayName: 'cache.db',
                  pathOrUri: '/root/Library/cache.db',
                  sizeBytes: 10,
                  category: 'Cache',
                  deletable: true,
                ),
              ),
            ],
          ),
          ScanTreeNode(
            name: 'notes.txt',
            path: '/root/notes.txt',
            isDirectory: false,
            entry: const ScanEntryRecord(
              id: 'notes',
              displayName: 'notes.txt',
              pathOrUri: '/root/notes.txt',
              sizeBytes: 4,
              category: 'Media',
              deletable: false,
            ),
          ),
        ],
      ),
      entryCount: 2,
      categoryCounts: const {},
      deletableCategoryCounts: const {},
      deletableCount: 1,
      extraFields: const {},
    );
    final catalog = SnapshotCatalog(snapshot);
    const key = SnapshotQueryKey(
      snapshotId: 'snap-1',
      version: 1,
      path: '/root',
      categoryFilter: 'Cache',
      deletableOnly: true,
      sortMode: ScanSortMode.nameAsc,
    );
    final result = catalog.query(key);

    expect(result.directChildren.map((node) => node.name), ['Library']);
    expect(result.directEntries, isEmpty);
    expect(result.totalBytes, 0);
    expect(result.reclaimableBytes, 0);

    final cache = SnapshotViewCache<SnapshotQueryResult>(capacity: 2);
    cache[key] = result;
    final rootKey = key.copyWith(path: '/root/Library');
    cache[rootKey] = catalog.query(rootKey);
    cache.invalidatePath('/root/Library');
    expect(cache[key], same(result));
    expect(cache[rootKey], isNull);
  });
}
