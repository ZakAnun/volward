import 'dart:async';

import 'package:flutter/foundation.dart';

import '../contracts/deletion_actions.dart';
import '../contracts/native_engine_ports.dart';
import 'catalog_session.dart';

abstract interface class DeletionSessionHost {
  bool get deletionReady;
  String? get deletionInitError;
  DeleteEnginePort? get deletionEngine;
  String? get deletionSnapshotId;
  void setDeletionLastError(String? value);
  void trackMoveToTrash({required int itemCount, required bool success});
  void trackEmptyTrash({required bool success});
}

typedef DeleteRunnerForTest =
    FutureOr<Map<String, dynamic>> Function(
      String snapshotId,
      List<String> targets,
      bool dryRun,
    );

/// Owns active delete operations and the latest delete report.
class DeletionSession extends ChangeNotifier implements DeletionActions {
  DeletionSession({
    required this.host,
    required this.catalog,
    this.deleteRunnerForTest,
  });

  final DeletionSessionHost host;
  final CatalogSession catalog;

  bool _deleting = false;
  Map<String, dynamic>? _lastDeleteReport;
  int _ownerGeneration = 0;
  @visibleForTesting
  DeleteRunnerForTest? deleteRunnerForTest;

  bool get deleting => _deleting;
  Map<String, dynamic>? get lastDeleteReport => _lastDeleteReport;
  @visibleForTesting
  int get ownerGenerationForTest => _ownerGeneration;

  void detachOwner() {
    _ownerGeneration++;
  }

  bool _isCurrentOwner(int generation) => generation == _ownerGeneration;

  void _notifyIfCurrentOwner(int generation) {
    if (_isCurrentOwner(generation)) notifyListeners();
  }

  void clearState() {
    _lastDeleteReport = null;
  }

  @override
  Future<Map<String, dynamic>> deleteEntries(
    List<String> targets, {
    String? expectedSnapshotId,
    bool dryRun = false,
    bool rescanAfterDelete = false,
    String? refreshPath,
    Map<String, String>? targetPathById,
  }) async {
    final engine = host.deletionEngine;
    final testRunner = deleteRunnerForTest;
    if (!host.deletionReady || (engine == null && testRunner == null)) {
      throw StateError(host.deletionInitError ?? 'Native engine not ready');
    }
    final snapshotId = host.deletionSnapshotId;
    if (snapshotId == null || snapshotId.isEmpty) {
      throw StateError('No scan snapshot — run a scan first');
    }
    if (expectedSnapshotId != null && expectedSnapshotId != snapshotId) {
      throw StateError('Snapshot changed — refresh the analysis and try again');
    }

    final ownerGeneration = _ownerGeneration;
    _deleting = true;
    if (_isCurrentOwner(ownerGeneration)) {
      host.setDeletionLastError(null);
      notifyListeners();
    }
    final batchRefresh = !dryRun && rescanAfterDelete;
    final deleteTargetDir = batchRefresh
        ? (refreshPath ?? catalog.refreshTargetPath)
        : null;
    late Map<String, dynamic> completedReport;
    String? pendingRefreshPath;
    var moveToTrashSucceeded = false;
    var moveToTrashItemCount = targets.length;
    try {
      final report = testRunner != null
          ? await Future<Map<String, dynamic>>.sync(
              () => testRunner(snapshotId, targets, dryRun),
            )
          : engine!.deleteEntries(snapshotId, targets, dryRun: dryRun);
      if (report.containsKey('error')) {
        throw StateError(report['error'].toString());
      }
      completedReport = report;
      if (!dryRun) {
        _lastDeleteReport = report;
        moveToTrashSucceeded = true;
        moveToTrashItemCount =
            (report['deleted_count'] as num?)?.toInt() ?? targets.length;
      }
      if (!dryRun && rescanAfterDelete && deleteTargetDir != null) {
        catalog.applySuccessfulDeleteOverlay(
          deleteTargetDir,
          targets,
          report,
          targetPathById: targetPathById,
          notify: false,
        );
        pendingRefreshPath = deleteTargetDir;
      }
    } catch (e) {
      if (_isCurrentOwner(ownerGeneration)) {
        host.setDeletionLastError('$e');
      }
      rethrow;
    } finally {
      _deleting = false;
      _notifyIfCurrentOwner(ownerGeneration);
      if (!dryRun && _isCurrentOwner(ownerGeneration)) {
        host.trackMoveToTrash(
          itemCount: moveToTrashItemCount,
          success: moveToTrashSucceeded,
        );
      }
    }
    if (pendingRefreshPath != null && _isCurrentOwner(ownerGeneration)) {
      catalog.scheduleDirectoryRefreshAfterDelete(pendingRefreshPath);
    }
    return completedReport;
  }

  @override
  Future<Map<String, dynamic>> emptyTrash({
    bool rescanAfterEmpty = true,
  }) async {
    final engine = host.deletionEngine;
    if (!host.deletionReady || engine == null) {
      throw StateError(host.deletionInitError ?? 'Native engine not ready');
    }

    final ownerGeneration = _ownerGeneration;
    _deleting = true;
    if (_isCurrentOwner(ownerGeneration)) {
      host.setDeletionLastError(null);
      notifyListeners();
    }
    var succeeded = false;
    try {
      final report = engine.emptyTrash();
      if (report.containsKey('error')) {
        throw StateError(report['error'].toString());
      }
      succeeded = true;
      if (rescanAfterEmpty && host.deletionSnapshotId != null) {
        await catalog.refreshCurrentDirectory();
      }
      return report;
    } catch (e) {
      if (_isCurrentOwner(ownerGeneration)) {
        host.setDeletionLastError('$e');
      }
      rethrow;
    } finally {
      _deleting = false;
      _notifyIfCurrentOwner(ownerGeneration);
      if (_isCurrentOwner(ownerGeneration)) {
        host.trackEmptyTrash(success: succeeded);
      }
    }
  }

  @visibleForTesting
  void applyOverlayForTest(
    String directoryPath,
    List<String> targets,
    Map<String, dynamic> report, {
    Map<String, String>? targetPathById,
  }) {
    catalog.applySuccessfulDeleteOverlay(
      directoryPath,
      targets,
      report,
      targetPathById: targetPathById,
    );
  }

  @override
  void dispose() {
    _ownerGeneration++;
    super.dispose();
  }
}
