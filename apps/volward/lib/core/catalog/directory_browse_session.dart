import '../../scan_tree.dart';
import 'catalog_reader.dart';

/// Catalog and directory navigation operations used by the browse page.
abstract interface class DirectoryBrowseSession implements CatalogReader {
  int get catalogVersion;
  Set<String> consumeInvalidatedPrefixes();
  ScanTreeNode? directoryOverlayForPath(String path);

  String? get currentDirectoryPath;
  String get refreshTargetPath;
  void setCurrentDirectory(String? path);

  Set<String> get refreshingDirectoryPaths;
  Set<String> get peekInFlight;
  bool isDirectoryRefreshing(String path);
  bool get canRefreshCurrentDirectory;
  Future<void> refreshCurrentDirectory([String? path]);
  Future<bool> peekScan(String path, {bool force = false});
}
