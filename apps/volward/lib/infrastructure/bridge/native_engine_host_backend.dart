import 'dart:ffi';

import '../../core/contracts/engine_host_backend.dart';
import '../../core/contracts/native_engine_ports.dart';
import 'native_engine_bridge_set.dart';

/// Infrastructure implementation of the EngineHost backend contract.
final class NativeEngineHostBackend implements EngineHostBackend {
  const NativeEngineHostBackend(this.bridges);

  final NativeEngineBridgeSet bridges;

  @override
  Pointer<Void> createEngine() => bridges.engine.createEngine();

  @override
  void freeEngine(Pointer<Void> engine) => bridges.engine.freeEngine(engine);

  @override
  Map<String, dynamic> probeCapabilities(Pointer<Void> engine) =>
      bridges.capability.probeCapabilities(engine);

  @override
  bool isDeepScanReady(Pointer<Void> engine) =>
      bridges.capability.isDeepScanReady(engine);

  @override
  ScanEnginePort bindScan(Pointer<Void> engine, void Function() ensureOpen) =>
      _BoundScanPort(engine, ensureOpen, bridges.scan);

  @override
  IndexEnginePort bindIndex(Pointer<Void> engine, void Function() ensureOpen) =>
      _BoundIndexPort(engine, ensureOpen, bridges.index);

  @override
  DeleteEnginePort bindDelete(
    Pointer<Void> engine,
    void Function() ensureOpen,
  ) => _BoundDeletePort(engine, ensureOpen, bridges.delete);

  @override
  CapabilityEnginePort bindCapability(
    Pointer<Void> engine,
    void Function() ensureOpen,
  ) => _BoundCapabilityPort(engine, ensureOpen, bridges.capability);

  @override
  AiEnginePort bindAi(Pointer<Void> engine, void Function() ensureOpen) =>
      _BoundAiPort(engine, ensureOpen, bridges.ai);
}

abstract class _BoundPort {
  _BoundPort(this.rawEngine, this.ensureOpen);

  final Pointer<Void> rawEngine;
  final void Function() ensureOpen;

  Pointer<Void> get engine {
    ensureOpen();
    return rawEngine;
  }
}

class _BoundScanPort extends _BoundPort implements ScanEnginePort {
  _BoundScanPort(super.rawEngine, super.ensureOpen, this.bridge);

  final ScanBridge bridge;

  @override
  bool get hasScanOptionsApi => bridge.hasScanOptionsApi;
  @override
  bool get hasQuickListApi => bridge.hasQuickListApi;
  @override
  String startScan(String jobId, List<String> roots) =>
      bridge.startScan(engine, jobId, roots);
  @override
  String startScanAsync(String jobId, List<String> roots) =>
      bridge.startScanAsync(engine, jobId, roots);
  @override
  String startScanAsyncWithOptions(
    String jobId,
    List<String> roots, {
    required bool incremental,
  }) => bridge.startScanAsyncWithOptions(
    engine,
    jobId,
    roots,
    incremental: incremental,
  );
  @override
  bool isScanRunning() => bridge.isScanRunning(engine);
  @override
  Map<String, dynamic>? getLastProgress() => bridge.getLastProgress(engine);
  @override
  void cancelScan() => bridge.cancelScan(engine);
  @override
  String requestScanPause(String root, String cacheDir) =>
      bridge.requestScanPause(engine, root, cacheDir);
  @override
  String? getLastPauseError() => bridge.getLastPauseError(engine);
  @override
  List<Map<String, dynamic>> quickListDir(String path) =>
      bridge.quickListDir(engine, path);
}

class _BoundIndexPort extends _BoundPort implements IndexEnginePort {
  _BoundIndexPort(super.rawEngine, super.ensureOpen, this.bridge);

  final IndexBridge bridge;

  @override
  bool get hasSnapshotFileApi => bridge.hasSnapshotFileApi;
  @override
  bool get hasSnapshotFilePbApi => bridge.hasSnapshotFilePbApi;
  @override
  bool get hasCheckpointApi => bridge.hasCheckpointApi;
  @override
  bool get hasIndexApi => bridge.hasIndexApi;
  @override
  bool get hasReplaceSubtreeApi => bridge.hasReplaceSubtreeApi;
  @override
  bool get hasAsyncIndexLoadApi => bridge.hasAsyncIndexLoadApi;
  @override
  Map<String, dynamic>? getLastSnapshot() => bridge.getLastSnapshot(engine);
  @override
  bool setLastSnapshot(Map<String, dynamic> snapshot) =>
      bridge.setLastSnapshot(engine, snapshot);
  @override
  String writeLastSnapshotToPath(String path) =>
      bridge.writeLastSnapshotToPath(engine, path);
  @override
  bool loadLastSnapshotFromPath(String path) =>
      bridge.loadLastSnapshotFromPath(engine, path);
  @override
  String? writeLastCheckpointToPath(String path) =>
      bridge.writeLastCheckpointToPath(engine, path);
  @override
  String writeLastSnapshotToPathPb(String path) =>
      bridge.writeLastSnapshotToPathPb(engine, path);
  @override
  String? writeLastCheckpointToPathPb(String path) =>
      bridge.writeLastCheckpointToPathPb(engine, path);
  @override
  Map<String, dynamic> queryDirectoryJson(
    String path, {
    String? categoryFilter,
    bool deletableOnly = false,
    String sortMode = 'size_desc',
  }) => bridge.queryDirectoryJson(
    engine,
    path,
    categoryFilter: categoryFilter,
    deletableOnly: deletableOnly,
    sortMode: sortMode,
  );
  @override
  Map<String, dynamic> refreshDirectory(String path) =>
      bridge.refreshDirectory(engine, path);
  @override
  bool loadIndexFromPath(String path) => bridge.loadIndexFromPath(engine, path);
  @override
  int? replaceDirectoryWithSubtree(String targetPath, String subtreeJson) =>
      bridge.replaceDirectoryWithSubtree(engine, targetPath, subtreeJson);
  @override
  String? startLoadIndexFromPathAsync(String path) =>
      bridge.startLoadIndexFromPathAsync(engine, path);
  @override
  bool isIndexLoading() => bridge.isIndexLoading(engine);
  @override
  void invalidateIndexLoad() => bridge.invalidateIndexLoad(engine);
  @override
  String? getLastIndexLoadError() => bridge.getLastIndexLoadError(engine);
  @override
  String? writeLastIndexToPath(String path) =>
      bridge.writeLastIndexToPath(engine, path);
  @override
  Map<String, dynamic>? getIndexSummaryJson() =>
      bridge.getIndexSummaryJson(engine);
  @override
  int indexVersion() => bridge.indexVersion(engine);
}

class _BoundDeletePort extends _BoundPort implements DeleteEnginePort {
  _BoundDeletePort(super.rawEngine, super.ensureOpen, this.bridge);

  final DeleteBridge bridge;

  @override
  Map<String, dynamic> deleteEntries(
    String snapshotId,
    List<String> entryIds, {
    bool dryRun = false,
  }) => bridge.deleteEntries(engine, snapshotId, entryIds, dryRun: dryRun);
  @override
  Map<String, dynamic> emptyTrash() => bridge.emptyTrash(engine);
}

class _BoundCapabilityPort extends _BoundPort implements CapabilityEnginePort {
  _BoundCapabilityPort(super.rawEngine, super.ensureOpen, this.bridge);

  final CapabilityBridge bridge;

  @override
  bool get hasCapabilityApi => bridge.hasCapabilityApi;
  @override
  Map<String, dynamic> probeCapabilities() => bridge.probeCapabilities(engine);
  @override
  bool isDeepScanReady() => bridge.isDeepScanReady(engine);
  @override
  bool openPermissionSettings() => bridge.openPermissionSettings(engine);
  @override
  String analyzeCapability(
    String snapshotId,
    String capability,
    String optionsJson,
  ) => bridge.analyzeCapability(engine, snapshotId, capability, optionsJson);
  @override
  String startCapabilityAnalysis(
    String snapshotId,
    String capability,
    String optionsJson,
  ) => bridge.startCapabilityAnalysis(
    engine,
    snapshotId,
    capability,
    optionsJson,
  );
  @override
  String getCapabilityJobStatus(String jobId) =>
      bridge.getCapabilityJobStatus(engine, jobId);
  @override
  bool cancelCapabilityAnalysis(String jobId) =>
      bridge.cancelCapabilityAnalysis(engine, jobId);
}

class _BoundAiPort extends _BoundPort implements AiEnginePort {
  _BoundAiPort(super.rawEngine, super.ensureOpen, this.bridge);

  final AiBridge bridge;

  @override
  bool get hasApplyDirVerdictToFileApi => bridge.hasApplyDirVerdictToFileApi;
  @override
  bool get hasAsyncAiCandidatesApi => bridge.hasAsyncAiCandidatesApi;
  @override
  bool get hasAsyncAiCoveragePlanApi => bridge.hasAsyncAiCoveragePlanApi;
  @override
  bool get hasAiSessionApi => bridge.hasAiSessionApi;
  @override
  bool get hasAiContractApi => bridge.hasAiContractApi;
  @override
  bool get hasAiTreeContractApi => bridge.hasAiTreeContractApi;
  @override
  bool get hasAiCoverageApi => bridge.hasAiCoverageApi;
  @override
  bool get hasAiTreeCoverageApi => bridge.hasAiTreeCoverageApi;
  @override
  String? buildAiCandidatesJson(String snapshotId) =>
      bridge.buildAiCandidatesJson(engine, snapshotId);
  @override
  String? startBuildAiCandidatesAsync(String snapshotId) =>
      bridge.startBuildAiCandidatesAsync(engine, snapshotId);
  @override
  bool isAiCandidatesBuilding() => bridge.isAiCandidatesBuilding(engine);
  @override
  String? getAiCandidatesJson() => bridge.getAiCandidatesJson(engine);
  @override
  String? takeAiCandidatesSpillPath() =>
      bridge.takeAiCandidatesSpillPath(engine);
  @override
  String? startBuildAiCoveragePlanAsync(
    String snapshotId, {
    required bool tree,
  }) => bridge.startBuildAiCoveragePlanAsync(engine, snapshotId, tree: tree);
  @override
  bool isAiCoveragePlanBuilding() => bridge.isAiCoveragePlanBuilding(engine);
  @override
  String? getAiCoveragePlanJson() => bridge.getAiCoveragePlanJson(engine);
  @override
  String? buildAiCoveragePlanJson(String snapshotId) =>
      bridge.buildAiCoveragePlanJson(engine, snapshotId);
  @override
  String? listLocalCoverageVerdictsJson(
    String snapshotId,
    int cursor, {
    int limit = 5000,
  }) => bridge.listLocalCoverageVerdictsJson(
    engine,
    snapshotId,
    cursor,
    limit: limit,
  );
  @override
  String? nextAiCoveragePageJson(
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 40,
  }) => bridge.nextAiCoveragePageJson(
    engine,
    snapshotId,
    planVersion,
    cursor,
    pageSize: pageSize,
  );
  @override
  String? resolveAiCoverageGroupJson(String snapshotId, String groupPath) =>
      bridge.resolveAiCoverageGroupJson(engine, snapshotId, groupPath);
  @override
  String? buildAiTreeCoveragePlanJson(String snapshotId) =>
      bridge.buildAiTreeCoveragePlanJson(engine, snapshotId);
  @override
  String? nextAiTreeCoveragePageJson(
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 80,
  }) => bridge.nextAiTreeCoveragePageJson(
    engine,
    snapshotId,
    planVersion,
    cursor,
    pageSize: pageSize,
  );
  @override
  String? nextAiTailCoveragePageJson(
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 40,
  }) => bridge.nextAiTailCoveragePageJson(
    engine,
    snapshotId,
    planVersion,
    cursor,
    pageSize: pageSize,
  );
  @override
  String? expandAiTreeNodeJson(String snapshotId, String dirPath) =>
      bridge.expandAiTreeNodeJson(engine, snapshotId, dirPath);
  @override
  String? applyAiDirVerdictJson(
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
  ) => bridge.applyAiDirVerdictJson(
    engine,
    snapshotId,
    dirPath,
    verdict,
    confidence,
    roleSnakeCase,
  );
  @override
  String? applyAiDirVerdictToFile(
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
    String outPath,
  ) => bridge.applyAiDirVerdictToFile(
    engine,
    snapshotId,
    dirPath,
    verdict,
    confidence,
    roleSnakeCase,
    outPath,
  );
  @override
  bool saveAiResultJson(String snapshotId, String resultJson) =>
      bridge.saveAiResultJson(engine, snapshotId, resultJson);
  @override
  String? loadAiResultJson(String snapshotId) =>
      bridge.loadAiResultJson(engine, snapshotId);
  @override
  String? aiUpstreamEndpoint() => bridge.aiUpstreamEndpoint();
  @override
  int? aiBatchSize() => bridge.aiBatchSize();
  @override
  String? aiBuildRequestJson(String candidatesJson) =>
      bridge.aiBuildRequestJson(candidatesJson);
  @override
  String? aiBuildConclusionSynthesisJson(String userJson) =>
      bridge.aiBuildConclusionSynthesisJson(userJson);
  @override
  String? aiParseResponseJson(String upstreamBody, String batchJson) =>
      bridge.aiParseResponseJson(upstreamBody, batchJson);
  @override
  int? aiTreeBatchSize() => bridge.aiTreeBatchSize();
  @override
  String? aiBuildTreeRequestJson(String nodesJson) =>
      bridge.aiBuildTreeRequestJson(nodesJson);
  @override
  String? aiParseTreeResponseJson(String upstreamBody, String batchJson) =>
      bridge.aiParseTreeResponseJson(upstreamBody, batchJson);
}
