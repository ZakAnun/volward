import '../../snapshot_query.dart';

/// Read-only access to the current native catalog. A null result requests fallback.
abstract interface class CatalogReader {
  bool get hasIndexApi;
  List<SnapshotNodeRecord>? queryDirectoryChildrenFromCatalog(
    String path, {
    String? categoryFilter,
    bool deletableOnly = false,
    String sortMode = 'size_desc',
  });
}
