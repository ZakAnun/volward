import '../../scan_root_record.dart';
import '../../scan_snapshot_state.dart';
import 'native_engine_ports.dart';
import 'scan_contracts.dart';

/// Narrow composition boundary between scan ownership and the compatibility
/// Session facade. It must not expose VolwardSession itself.
abstract interface class ScanSessionHost {
  bool get ready;
  String? get initError;
  String? get lastError;
  set lastError(String? value);
  bool get canUseIncrementalScan;
  bool get hasSnapshotFileApi;
  bool get persistSessionStateEnabled;

  ScanEnginePort get scanEngine;
  IndexEnginePort get indexEngine;
  ScanRootRecordStore get rootRecordStore;

  void invalidateCapabilityCache(String? snapshotId);
  void resetBrowseStateForRootChange();
  void clearDeletionState();
  Future<void> commitMergedSnapshot({
    required ScanSnapshotState snapshot,
    required String targetPath,
    required Map<String, dynamic> subtreeTree,
    required List<Map<String, dynamic>> subtreeEntries,
    required bool authoritative,
  });

  Future<void> previewTargetFromHost({int? expectedGeneration});
  Future<bool> peekScanFromHost(String path, {bool force = false});
  Future<String> runScanFromHost({required ScanRunMode mode});

  void trackScanRootSelected(String root);
  void trackScanStarted({required String root, required bool incremental});
  void trackScanCompleted({
    required String root,
    required Duration elapsed,
    required int entryCount,
  });
}
