import 'package:flutter_test/flutter_test.dart';
import 'package:volward/features/browse/catalog_reader.dart';
import 'package:volward/features/browse/scan_sort_mode.dart';
import 'package:volward/features/browse/snapshot_catalog.dart' as browse;
import 'package:volward/scan_entry_record.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/snapshot_catalog.dart';
import 'package:volward/snapshot_query.dart';
import 'package:volward/snapshot_view_cache.dart';
import 'package:volward/volward_session.dart';

void main() {
  test('queries direct children and invalidates cached path prefixes', () {
    final notesNode = ScanTreeNode(
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
    );
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
          notesNode,
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
    expect(result.directNodes.map((node) => node.name), ['Library']);
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

  test('directNodes reuses existing file node references', () {
    final fileNode = ScanTreeNode(
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
    );
    final snapshot = ScanSnapshotState(
      snapshotId: 'snap-2',
      scannedAtMs: 1,
      stats: const {},
      reclaimableEstimateBytes: 0,
      tree: ScanTreeNode(
        name: 'root',
        path: '/root',
        isDirectory: true,
        children: [fileNode],
      ),
      entryCount: 1,
      categoryCounts: const {},
      deletableCategoryCounts: const {},
      deletableCount: 0,
      extraFields: const {},
    );
    const key = SnapshotQueryKey(
      snapshotId: 'snap-2',
      version: 1,
      path: '/root',
      categoryFilter: null,
      deletableOnly: false,
      sortMode: ScanSortMode.nameAsc,
    );

    final result = SnapshotCatalog(snapshot).query(key);

    expect(result.directNodes.single, same(fileNode));
    expect(result.directEntries.single.id, 'notes');
  });

  test(
    'explicit catalog reader supplies filters and preserves null fallback',
    () {
      final global = _CatalogSession(const []);
      final previous = VolwardSession.instance;
      VolwardSession.instance = global;
      addTearDown(() {
        VolwardSession.instance = previous;
        global.dispose();
      });
      final file = ScanTreeNode(
        name: 'cached.txt',
        path: '/root/cached.txt',
        isDirectory: false,
        entry: const ScanEntryRecord(
          id: 'cached',
          displayName: 'cached.txt',
          pathOrUri: '/root/cached.txt',
          sizeBytes: 7,
          category: 'Cache',
          deletable: true,
        ),
      );
      final root = ScanTreeNode(
        name: 'root',
        path: '/root',
        isDirectory: true,
        children: [file],
      );
      const key = SnapshotQueryKey(
        snapshotId: 'snapshot',
        version: 1,
        path: '/root',
        categoryFilter: 'Cache',
        deletableOnly: true,
        sortMode: ScanSortMode.nameAsc,
      );
      final reader = _CatalogSession(const [
        SnapshotNodeRecord(
          path: '/root/native.txt',
          name: 'native.txt',
          isDirectory: false,
          sizeBytes: 11,
          entryId: 'native',
          category: 'Cache',
          deletable: true,
        ),
      ]);
      addTearDown(reader.dispose);
      final catalog = browse.SnapshotCatalog(
        snapshotId: key.snapshotId,
        tree: root,
        reader: reader,
      );

      final native = catalog.query(key);
      expect(reader.lastQuery, ('/root', 'Cache', true, 'name_asc'));
      expect(native.directEntries.single.id, 'native');
      expect(native.totalBytes, 11);
      expect(native.reclaimableBytes, 11);

      reader.records = null;
      final fallback = catalog.query(key);
      expect(fallback.directNodes.single, same(file));
      expect(fallback.directEntries.single.id, 'cached');
      expect(fallback.totalBytes, 7);
      expect(global.lastQuery, isNull);

      final legacy = SnapshotCatalog.queryNode(key: key, node: root);
      expect(global.lastQuery, ('/root', 'Cache', true, 'name_asc'));
      expect(legacy.directNodes, isEmpty);
    },
  );
}

class _CatalogSession extends VolwardSession implements CatalogReader {
  _CatalogSession(this.records) : super.test();

  List<SnapshotNodeRecord>? records;
  (String, String?, bool, String)? lastQuery;

  @override
  bool get hasIndexApi => true;

  @override
  List<SnapshotNodeRecord>? queryDirectoryChildrenFromCatalog(
    String path, {
    String? categoryFilter,
    bool deletableOnly = false,
    String sortMode = 'size_desc',
  }) {
    lastQuery = (path, categoryFilter, deletableOnly, sortMode);
    return records;
  }
}
