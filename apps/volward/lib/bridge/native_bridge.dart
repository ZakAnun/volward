import 'dart:ffi';

import 'package:flutter/foundation.dart';

import '../infrastructure/bridge/ai_facade.dart';
import '../infrastructure/bridge/native_engine_bridge_set.dart';
import '../infrastructure/bridge/native_engine_host_backend.dart';
import '../infrastructure/bridge/runtime/native_library.dart';
import '../core/session/engine_host.dart';

export 'bindings/ai.dart';
export 'bindings/capabilities.dart';
export 'bindings/delete.dart';
export 'bindings/index.dart';
export 'bindings/scan.dart';
export '../infrastructure/bridge/engine_bridge.dart'
    show
        VolwardEngineCreate,
        VolwardEngineCreateNative,
        VolwardEngineFree,
        VolwardEngineFreeNative,
        VolwardFreeString,
        VolwardFreeStringNative,
        VolwardBridge;

class VolwardNativeBridge with AiBridgeFacade implements VolwardBridge {
  VolwardNativeBridge._(NativeLibraryHandle library) {
    _engineBridge = EngineNativeBridge(library);
    final codec = _engineBridge.codec;
    _scanBridge = ScanNativeBridge(library, codec);
    _indexBridge = IndexNativeBridge(library, codec);
    _deleteBridge = DeleteNativeBridge(library, codec);
    _capabilityBridge = CapabilityNativeBridge(library, codec);
    _aiBridge = AiNativeBridge(library, codec);
  }
  @visibleForTesting
  VolwardNativeBridge.test({
    EngineBridge? engine,
    ScanBridge? scan,
    IndexBridge? index,
    DeleteBridge? delete,
    CapabilityBridge? capability,
    AiBridge? ai,
  }) : _engineBridge = engine ?? _UnavailableEngineBridge(),
       _scanBridge = scan ?? _UnavailableScanBridge(),
       _indexBridge = index ?? _UnavailableIndexBridge(),
       _deleteBridge = delete ?? _UnavailableDeleteBridge(),
       _capabilityBridge = capability ?? _UnavailableCapabilityBridge(),
       _aiBridge = ai ?? _UnavailableAiBridge();

  static VolwardNativeBridge? _instance;

  static VolwardNativeBridge get instance => _instance ??=
      VolwardNativeBridge._(DynamicNativeLibraryHandle.openExecutableSibling());

  static VolwardNativeBridge open() =>
      VolwardNativeBridge._(DynamicNativeLibraryHandle.openExecutableSibling());

  late final EngineBridge _engineBridge;
  late final ScanBridge _scanBridge;
  late final IndexBridge _indexBridge;
  late final DeleteBridge _deleteBridge;
  late final CapabilityBridge _capabilityBridge;
  late final AiBridge _aiBridge;

  @override
  AiBridge get aiBridge => _aiBridge;

  EngineHost createEngineHost() => EngineHost.create(
    backend: NativeEngineHostBackend(
      NativeEngineBridgeSet(
        engine: _engineBridge,
        scan: _scanBridge,
        index: _indexBridge,
        delete: _deleteBridge,
        capability: _capabilityBridge,
        ai: _aiBridge,
      ),
    ),
  );

  @override
  bool get hasSnapshotFileApi => _indexBridge.hasSnapshotFileApi;
  @override
  bool get hasSnapshotFilePbApi => _indexBridge.hasSnapshotFilePbApi;
  @override
  bool get hasScanOptionsApi => _scanBridge.hasScanOptionsApi;
  @override
  bool get hasCheckpointApi => _indexBridge.hasCheckpointApi;
  @override
  bool get hasQuickListApi => _scanBridge.hasQuickListApi;
  @override
  bool get hasIndexApi => _indexBridge.hasIndexApi;

  bool get hasReplaceSubtreeApi => _indexBridge.hasReplaceSubtreeApi;
  bool get hasAsyncIndexLoadApi => _indexBridge.hasAsyncIndexLoadApi;
  bool get hasCapabilityApi => _capabilityBridge.hasCapabilityApi;

  Pointer<Void> createEngine() => _engineBridge.createEngine();
  void freeEngine(Pointer<Void> engine) => _engineBridge.freeEngine(engine);
  Map<String, dynamic> probeCapabilities(Pointer<Void> engine) =>
      _capabilityBridge.probeCapabilities(engine);
  bool isDeepScanReady(Pointer<Void> engine) =>
      _capabilityBridge.isDeepScanReady(engine);
  bool openPermissionSettings(Pointer<Void> engine) =>
      _capabilityBridge.openPermissionSettings(engine);

  String startScan(Pointer<Void> engine, String jobId, List<String> roots) =>
      _scanBridge.startScan(engine, jobId, roots);
  String startScanAsync(
    Pointer<Void> engine,
    String jobId,
    List<String> roots,
  ) => _scanBridge.startScanAsync(engine, jobId, roots);
  String startScanAsyncWithOptions(
    Pointer<Void> engine,
    String jobId,
    List<String> roots, {
    required bool incremental,
  }) => _scanBridge.startScanAsyncWithOptions(
    engine,
    jobId,
    roots,
    incremental: incremental,
  );
  bool isScanRunning(Pointer<Void> engine) => _scanBridge.isScanRunning(engine);
  Map<String, dynamic>? getLastProgress(Pointer<Void> engine) =>
      _scanBridge.getLastProgress(engine);
  void cancelScan(Pointer<Void> engine) => _scanBridge.cancelScan(engine);
  String requestScanPause(Pointer<Void> engine, String root, String cacheDir) =>
      _scanBridge.requestScanPause(engine, root, cacheDir);
  String? getLastPauseError(Pointer<Void> engine) =>
      _scanBridge.getLastPauseError(engine);
  List<Map<String, dynamic>> quickListDir(Pointer<Void> engine, String path) =>
      _scanBridge.quickListDir(engine, path);

  Map<String, dynamic>? getLastSnapshot(Pointer<Void> engine) =>
      _indexBridge.getLastSnapshot(engine);
  bool setLastSnapshot(Pointer<Void> engine, Map<String, dynamic> snapshot) =>
      _indexBridge.setLastSnapshot(engine, snapshot);
  String writeLastSnapshotToPath(Pointer<Void> engine, String path) =>
      _indexBridge.writeLastSnapshotToPath(engine, path);
  bool loadLastSnapshotFromPath(Pointer<Void> engine, String path) =>
      _indexBridge.loadLastSnapshotFromPath(engine, path);
  String? writeLastCheckpointToPath(Pointer<Void> engine, String path) =>
      _indexBridge.writeLastCheckpointToPath(engine, path);
  String writeLastSnapshotToPathPb(Pointer<Void> engine, String path) =>
      _indexBridge.writeLastSnapshotToPathPb(engine, path);
  String? writeLastCheckpointToPathPb(Pointer<Void> engine, String path) =>
      _indexBridge.writeLastCheckpointToPathPb(engine, path);
  Map<String, dynamic> queryDirectoryJson(
    Pointer<Void> engine,
    String path, {
    String? categoryFilter,
    bool deletableOnly = false,
    String sortMode = 'size_desc',
  }) => _indexBridge.queryDirectoryJson(
    engine,
    path,
    categoryFilter: categoryFilter,
    deletableOnly: deletableOnly,
    sortMode: sortMode,
  );
  Map<String, dynamic> refreshDirectory(Pointer<Void> engine, String path) =>
      _indexBridge.refreshDirectory(engine, path);
  bool loadIndexFromPath(Pointer<Void> engine, String path) =>
      _indexBridge.loadIndexFromPath(engine, path);
  int? replaceDirectoryWithSubtree(
    Pointer<Void> engine,
    String targetPath,
    String subtreeJson,
  ) =>
      _indexBridge.replaceDirectoryWithSubtree(engine, targetPath, subtreeJson);
  String? startLoadIndexFromPathAsync(Pointer<Void> engine, String path) =>
      _indexBridge.startLoadIndexFromPathAsync(engine, path);
  bool isIndexLoading(Pointer<Void> engine) =>
      _indexBridge.isIndexLoading(engine);
  void invalidateIndexLoad(Pointer<Void> engine) =>
      _indexBridge.invalidateIndexLoad(engine);
  String? getLastIndexLoadError(Pointer<Void> engine) =>
      _indexBridge.getLastIndexLoadError(engine);
  String? writeLastIndexToPath(Pointer<Void> engine, String path) =>
      _indexBridge.writeLastIndexToPath(engine, path);
  Map<String, dynamic>? getIndexSummaryJson(Pointer<Void> engine) =>
      _indexBridge.getIndexSummaryJson(engine);
  int indexVersion(Pointer<Void> engine) => _indexBridge.indexVersion(engine);

  Map<String, dynamic> deleteEntries(
    Pointer<Void> engine,
    String snapshotId,
    List<String> entryIds, {
    bool dryRun = false,
  }) =>
      _deleteBridge.deleteEntries(engine, snapshotId, entryIds, dryRun: dryRun);
  Map<String, dynamic> emptyTrash(Pointer<Void> engine) =>
      _deleteBridge.emptyTrash(engine);

  String analyzeCapability(
    Pointer<Void> engine,
    String snapshotId,
    String capability,
    String optionsJson,
  ) => _capabilityBridge.analyzeCapability(
    engine,
    snapshotId,
    capability,
    optionsJson,
  );
  String startCapabilityAnalysis(
    Pointer<Void> engine,
    String snapshotId,
    String capability,
    String optionsJson,
  ) => _capabilityBridge.startCapabilityAnalysis(
    engine,
    snapshotId,
    capability,
    optionsJson,
  );
  String getCapabilityJobStatus(Pointer<Void> engine, String jobId) =>
      _capabilityBridge.getCapabilityJobStatus(engine, jobId);
  bool cancelCapabilityAnalysis(Pointer<Void> engine, String jobId) =>
      _capabilityBridge.cancelCapabilityAnalysis(engine, jobId);
}

class _UnavailableEngineBridge implements EngineBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Native engine bridge was not provided');
}

class _UnavailableScanBridge implements ScanBridge {
  @override
  bool get hasScanOptionsApi => false;
  @override
  bool get hasQuickListApi => false;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Native scan bridge was not provided');
}

class _UnavailableIndexBridge implements IndexBridge {
  @override
  bool get hasSnapshotFileApi => false;
  @override
  bool get hasSnapshotFilePbApi => false;
  @override
  bool get hasCheckpointApi => false;
  @override
  bool get hasIndexApi => false;
  @override
  bool get hasReplaceSubtreeApi => false;
  @override
  bool get hasAsyncIndexLoadApi => false;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Native index bridge was not provided');
}

class _UnavailableDeleteBridge implements DeleteBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Native delete bridge was not provided');
}

class _UnavailableCapabilityBridge implements CapabilityBridge {
  @override
  bool get hasCapabilityApi => false;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Native capability bridge was not provided');
}

class _UnavailableAiBridge implements AiBridge {
  @override
  bool get hasApplyDirVerdictToFileApi => false;
  @override
  bool get hasAsyncAiCandidatesApi => false;
  @override
  bool get hasAsyncAiCoveragePlanApi => false;
  @override
  bool get hasAiSessionApi => false;
  @override
  bool get hasAiContractApi => false;
  @override
  bool get hasAiTreeContractApi => false;
  @override
  bool get hasAiCoverageApi => false;
  @override
  bool get hasAiTreeCoverageApi => false;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Native AI bridge was not provided');
}
