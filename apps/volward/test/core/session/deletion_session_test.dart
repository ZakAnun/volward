import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/core/contracts/native_engine_ports.dart';
import 'package:volward/core/session/catalog_session.dart';
import 'package:volward/core/session/deletion_session.dart';
import 'package:volward/scan_snapshot_state.dart';

void main() {
  test('delete completion clears busy state after a delayed runner', () async {
    final catalog = CatalogSession(host: _CatalogHost());
    final host = _DeletionHost();
    final session = DeletionSession(host: host, catalog: catalog);
    addTearDown(session.dispose);
    addTearDown(catalog.dispose);
    final release = Completer<Map<String, dynamic>>();
    session.deleteRunnerForTest = (_, _, _) => release.future;

    final pending = session.deleteEntries(['/root/a'], dryRun: true);
    expect(session.deleting, isTrue);
    release.complete({'deleted_count': 1});
    final report = await pending;

    expect(report['deleted_count'], 1);
    expect(session.deleting, isFalse);
    expect(host.errors, [null]);
  });

  test('empty trash contributes to the same owner state', () async {
    final catalog = CatalogSession(host: _CatalogHost());
    final host = _DeletionHost(engine: _DeletePort());
    final session = DeletionSession(host: host, catalog: catalog);
    addTearDown(session.dispose);
    addTearDown(catalog.dispose);

    final report = await session.emptyTrash(rescanAfterEmpty: false);

    expect(report['deleted_count'], 2);
    expect(session.deleting, isFalse);
    expect(host.emptyTrashEvents, 1);
  });

  test(
    'delete completion after owner handoff does not notify old owner',
    () async {
      final catalog = CatalogSession(host: _CatalogHost());
      final host = _DeletionHost();
      final session = DeletionSession(host: host, catalog: catalog);
      addTearDown(session.dispose);
      addTearDown(catalog.dispose);
      var notifications = 0;
      session.addListener(() => notifications++);
      final release = Completer<Map<String, dynamic>>();
      session.deleteRunnerForTest = (_, _, _) => release.future;

      final pending = session.deleteEntries(['/root/a'], dryRun: true);
      expect(session.deleting, isTrue);
      final notificationsBeforeHandoff = notifications;
      session.detachOwner();
      release.complete({'deleted_count': 1});
      await pending;

      expect(session.deleting, isFalse);
      expect(notifications, notificationsBeforeHandoff);
      expect(host.errors, [null]);
    },
  );
}

class _DeletionHost implements DeletionSessionHost {
  _DeletionHost({this.engine});

  final DeleteEnginePort? engine;
  final List<String?> errors = [];
  int emptyTrashEvents = 0;

  @override
  bool get deletionReady => true;
  @override
  String? get deletionInitError => null;
  @override
  DeleteEnginePort? get deletionEngine => engine;
  @override
  String? get deletionSnapshotId => 'snapshot-1';
  @override
  void setDeletionLastError(String? value) => errors.add(value);
  @override
  void trackMoveToTrash({required int itemCount, required bool success}) {}
  @override
  void trackEmptyTrash({required bool success}) => emptyTrashEvents++;
}

class _DeletePort implements DeleteEnginePort {
  @override
  Map<String, dynamic> deleteEntries(
    String snapshotId,
    List<String> entryIds, {
    bool dryRun = false,
  }) => {'deleted_count': entryIds.length};
  @override
  Map<String, dynamic> emptyTrash() => {'deleted_count': 2};
}

class _CatalogHost implements CatalogSessionHost {
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
  ScanSnapshotState? get catalogSnapshot => null;
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
  Future<bool> peekScanForCatalog(String path, {bool force = false}) async =>
      true;
  @override
  void invalidateCapabilityCacheForCatalog(String? snapshotId) {}
  @override
  void setCatalogLastError(String? value) {}
  @override
  void beginCatalogNotificationBatch() {}
  @override
  void endCatalogNotificationBatch({bool notify = true}) {}
  @override
  void trackCatalogRefreshTriggered() {}
}
