import 'package:flutter_test/flutter_test.dart';
import 'package:volward/core/contracts/native_engine_ports.dart';
import 'package:volward/core/session/catalog_session.dart';
import 'package:volward/features/browse/scan_sort_mode.dart';
import 'package:volward/scan_entry_record.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/snapshot_query.dart';

void main() {
  test('catalog query and refresh stay owned by CatalogSession', () async {
    final snapshot = _snapshotWithFile('/root/a.txt');
    final host = _CatalogHost(snapshot: snapshot);
    final catalog = CatalogSession(host: host, initialSnapshot: snapshot);
    addTearDown(catalog.dispose);
    var notifications = 0;
    catalog.addListener(() => notifications++);

    const key = SnapshotQueryKey(
      snapshotId: 'catalog-snapshot',
      version: 1,
      path: '/root',
      categoryFilter: null,
      deletableOnly: false,
      sortMode: ScanSortMode.nameAsc,
    );
    final result = catalog.query(key);

    expect(result.directEntries.single.pathOrUri, '/root/a.txt');
    catalog.setCurrentDirectory('/root/sub');
    await catalog.refreshCurrentDirectory();

    expect(host.peeks, ['/root/sub']);
    expect(host.endBatchNotifyValues, [false]);
    expect(notifications, greaterThanOrEqualTo(2));
    expect(catalog.catalogVersion, greaterThan(0));
    expect(catalog.currentDirectoryPath, '/root/sub');

    final notificationsBeforeCommit = notifications;
    await catalog.commitMergedSnapshot(
      snapshot: snapshot,
      targetPath: '/root/sub',
      subtreeTree: const {},
      subtreeEntries: const [],
      authoritative: false,
    );
    expect(notifications, greaterThan(notificationsBeforeCommit));
  });

  test('root reset clears overlays and invalidations', () {
    final catalog = CatalogSession(host: _CatalogHost());
    addTearDown(catalog.dispose);

    catalog.setCurrentDirectory('/root/child');
    catalog.resetBrowseStateForRootChange();

    expect(catalog.currentDirectoryPath, isNull);
    expect(catalog.invalidatedPrefixes, isEmpty);
  });
}

class _CatalogHost implements CatalogSessionHost {
  _CatalogHost({this.snapshot});

  final ScanSnapshotState? snapshot;
  final List<String> peeks = [];
  final List<void> refreshBatches = [];
  final List<bool> endBatchNotifyValues = [];

  @override
  bool get catalogEngineReady => true;
  @override
  bool get catalogHasIndexApi => false;
  @override
  bool get catalogHasSnapshotFileApi => true;
  @override
  int get catalogIndexVersion => 0;
  @override
  int get catalogRootSwitchGeneration => 0;
  @override
  bool get catalogScanning => false;
  @override
  ScanSnapshotState? get catalogSnapshot => snapshot;
  @override
  List<String> get catalogScanRoots => const ['/root'];
  @override
  Set<String> get catalogPeekInFlight => const {};
  @override
  String get catalogDefaultRoot => '/root';
  @override
  IndexEnginePort? get catalogIndexEngine => null;

  @override
  Future<void> runCatalogRootRefresh() async {}
  @override
  Future<bool> peekScanForCatalog(String path, {bool force = false}) async {
    peeks.add(path);
    return true;
  }

  @override
  void invalidateCapabilityCacheForCatalog(String? snapshotId) {}
  @override
  void setCatalogLastError(String? value) {}
  @override
  void beginCatalogNotificationBatch() => refreshBatches.add(null);
  @override
  void endCatalogNotificationBatch({bool notify = true}) {
    refreshBatches.add(null);
    endBatchNotifyValues.add(notify);
  }

  @override
  void trackCatalogRefreshTriggered() {}
}

ScanSnapshotState _snapshotWithFile(String path) {
  final file = ScanTreeNode(
    name: path.split('/').last,
    path: path,
    isDirectory: false,
    entry: ScanEntryRecord(
      id: 'file',
      displayName: path.split('/').last,
      pathOrUri: path,
      sizeBytes: 10,
      category: 'Other',
      deletable: false,
    ),
  );
  return ScanSnapshotState(
    snapshotId: 'catalog-snapshot',
    scannedAtMs: 1,
    stats: const {},
    reclaimableEstimateBytes: 0,
    tree: ScanTreeNode(
      name: 'root',
      path: '/root',
      isDirectory: true,
      children: [
        file,
        ScanTreeNode(
          name: 'sub',
          path: '/root/sub',
          isDirectory: true,
          children: const [],
        ),
      ],
    ),
    entryCount: 1,
    categoryCounts: const {},
    deletableCategoryCounts: const {},
    deletableCount: 0,
    extraFields: const {},
  );
}
