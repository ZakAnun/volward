import 'features/browse/catalog_reader.dart';
import 'features/browse/snapshot_catalog.dart' as browse;
import 'scan_tree.dart';
import 'snapshot_query.dart';

abstract interface class SnapshotCatalogSource {
  String get snapshotId;
  ScanTreeNode? get tree;
}

/// Legacy entry point, preserving live global-session lookup for old callers.
/// New browse callers inject their existing session through CatalogReader.
class SnapshotCatalog {
  SnapshotCatalog(SnapshotCatalogSource snapshot)
    : _catalog = browse.SnapshotCatalog(
        snapshotId: snapshot.snapshotId,
        tree: snapshot.tree,
        reader: const _LegacyCatalogReader(),
      );

  final browse.SnapshotCatalog _catalog;

  /// Composition root registers the active compatibility reader here.
  /// Keeping this indirection avoids a legacy-catalog dependency on Session.
  static CatalogReader? legacyReader;

  SnapshotQueryResult query(SnapshotQueryKey key) => _catalog.query(key);

  static SnapshotQueryResult queryNode({
    required SnapshotQueryKey key,
    required ScanTreeNode node,
    bool includeEntryRecords = true,
  }) => browse.SnapshotCatalog.queryNode(
    key: key,
    node: node,
    includeEntryRecords: includeEntryRecords,
    reader: legacyReader,
  );

  static int compareAsciiCaseInsensitive(String left, String right) =>
      browse.SnapshotCatalog.compareAsciiCaseInsensitive(left, right);
}

class _LegacyCatalogReader implements CatalogReader {
  const _LegacyCatalogReader();
  @override
  bool get hasIndexApi => SnapshotCatalog.legacyReader?.hasIndexApi ?? false;
  @override
  List<SnapshotNodeRecord>? queryDirectoryChildrenFromCatalog(
    String path, {
    String? categoryFilter,
    bool deletableOnly = false,
    String sortMode = 'size_desc',
  }) => SnapshotCatalog.legacyReader?.queryDirectoryChildrenFromCatalog(
    path,
    categoryFilter: categoryFilter,
    deletableOnly: deletableOnly,
    sortMode: sortMode,
  );
}
