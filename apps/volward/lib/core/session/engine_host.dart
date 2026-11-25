import 'dart:ffi';

import '../contracts/engine_host_backend.dart';
import '../contracts/native_engine_ports.dart';
import 'native_engine_lifetime.dart';

class EngineHost {
  EngineHost._({
    required this._engine,
    required this._freeEngine,
    required this.capabilities,
    required this.deepScanReady,
    required EngineHostBackend backend,
  }) {
    lifetime = NativeEngineLifetime();
    scan = backend.bindScan(_engine, _ensureOpen);
    index = backend.bindIndex(_engine, _ensureOpen);
    delete = backend.bindDelete(_engine, _ensureOpen);
    capability = backend.bindCapability(_engine, _ensureOpen);
    ai = backend.bindAi(_engine, _ensureOpen);
  }

  factory EngineHost.create({required EngineHostBackend backend}) {
    final engine = backend.createEngine();
    try {
      return EngineHost._(
        engine: engine,
        backend: backend,
        capabilities: backend.probeCapabilities(engine),
        deepScanReady: backend.isDeepScanReady(engine),
        freeEngine: () => backend.freeEngine(engine),
      );
    } catch (_) {
      backend.freeEngine(engine);
      rethrow;
    }
  }

  factory EngineHost.forTest({
    required Pointer<Void> engine,
    EngineHostBackend? backend,
    void Function()? freeEngine,
    Map<String, dynamic> capabilities = const {},
    bool deepScanReady = false,
  }) => EngineHost._(
    engine: engine,
    backend: backend ?? const _UnavailableEngineHostBackend(),
    freeEngine: freeEngine ?? () {},
    capabilities: capabilities,
    deepScanReady: deepScanReady,
  );

  final Pointer<Void> _engine;
  final void Function() _freeEngine;
  final Map<String, dynamic> capabilities;
  final bool deepScanReady;

  late final NativeEngineLifetime lifetime;
  late final ScanEnginePort scan;
  late final IndexEnginePort index;
  late final DeleteEnginePort delete;
  late final CapabilityEnginePort capability;
  late final AiEnginePort ai;

  bool get ready => !lifetime.isClosed;
  String? get initError => null;

  /// Transitional raw-pointer compatibility for legacy Session and worker
  /// calls. Tasks 5 and 6 migrate those exact call sites to typed ports and
  /// remove this getter.
  @Deprecated('Use typed ports. Removed by Tasks 5 and 6 of the SDD plan.')
  Pointer<Void> get legacyEnginePointer => _engine;

  NativeEngineLease borrow() => lifetime.scope();

  void _ensureOpen() {
    if (lifetime.isClosed) {
      throw StateError('Native engine is already released');
    }
  }

  void dispose() {
    if (lifetime.isClosed) return;
    lifetime.close(_freeEngine);
  }
}

class _UnavailableEngineHostBackend implements EngineHostBackend {
  const _UnavailableEngineHostBackend();

  @override
  Pointer<Void> createEngine() =>
      throw StateError('Engine backend unavailable');
  @override
  void freeEngine(Pointer<Void> engine) {}
  @override
  Map<String, dynamic> probeCapabilities(Pointer<Void> engine) =>
      throw StateError('Engine backend unavailable');
  @override
  bool isDeepScanReady(Pointer<Void> engine) => false;
  @override
  ScanEnginePort bindScan(Pointer<Void> engine, void Function() ensureOpen) =>
      const _UnavailableScanPort();
  @override
  IndexEnginePort bindIndex(Pointer<Void> engine, void Function() ensureOpen) =>
      const _UnavailableIndexPort();
  @override
  DeleteEnginePort bindDelete(
    Pointer<Void> engine,
    void Function() ensureOpen,
  ) => const _UnavailableDeletePort();
  @override
  CapabilityEnginePort bindCapability(
    Pointer<Void> engine,
    void Function() ensureOpen,
  ) => const _UnavailableCapabilityPort();
  @override
  AiEnginePort bindAi(Pointer<Void> engine, void Function() ensureOpen) =>
      const _UnavailableAiPort();
}

class _UnavailableScanPort implements ScanEnginePort {
  const _UnavailableScanPort();

  Never _unavailable() => throw StateError('Scan port is unavailable');

  @override
  bool get hasScanOptionsApi => false;
  @override
  bool get hasQuickListApi => false;
  @override
  String startScan(String jobId, List<String> roots) => _unavailable();
  @override
  String startScanAsync(String jobId, List<String> roots) => _unavailable();
  @override
  String startScanAsyncWithOptions(
    String jobId,
    List<String> roots, {
    required bool incremental,
  }) => _unavailable();
  @override
  bool isScanRunning() => _unavailable();
  @override
  Map<String, dynamic>? getLastProgress() => _unavailable();
  @override
  void cancelScan() => _unavailable();
  @override
  String requestScanPause(String root, String cacheDir) => _unavailable();
  @override
  String? getLastPauseError() => _unavailable();
  @override
  List<Map<String, dynamic>> quickListDir(String path) => _unavailable();
}

class _UnavailableIndexPort implements IndexEnginePort {
  const _UnavailableIndexPort();

  Never _unavailable() => throw StateError('Index port is unavailable');

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
  Map<String, dynamic>? getLastSnapshot() => _unavailable();
  @override
  bool setLastSnapshot(Map<String, dynamic> snapshot) => _unavailable();
  @override
  String writeLastSnapshotToPath(String path) => _unavailable();
  @override
  bool loadLastSnapshotFromPath(String path) => _unavailable();
  @override
  String? writeLastCheckpointToPath(String path) => _unavailable();
  @override
  String writeLastSnapshotToPathPb(String path) => _unavailable();
  @override
  String? writeLastCheckpointToPathPb(String path) => _unavailable();
  @override
  Map<String, dynamic> queryDirectoryJson(
    String path, {
    String? categoryFilter,
    bool deletableOnly = false,
    String sortMode = 'size_desc',
  }) => _unavailable();
  @override
  Map<String, dynamic> refreshDirectory(String path) => _unavailable();
  @override
  bool loadIndexFromPath(String path) => _unavailable();
  @override
  int? replaceDirectoryWithSubtree(String targetPath, String subtreeJson) =>
      _unavailable();
  @override
  String? startLoadIndexFromPathAsync(String path) => _unavailable();
  @override
  bool isIndexLoading() => _unavailable();
  @override
  void invalidateIndexLoad() => _unavailable();
  @override
  String? getLastIndexLoadError() => _unavailable();
  @override
  String? writeLastIndexToPath(String path) => _unavailable();
  @override
  Map<String, dynamic>? getIndexSummaryJson() => _unavailable();
  @override
  int indexVersion() => _unavailable();
}

class _UnavailableDeletePort implements DeleteEnginePort {
  const _UnavailableDeletePort();

  Never _unavailable() => throw StateError('Delete port is unavailable');

  @override
  Map<String, dynamic> deleteEntries(
    String snapshotId,
    List<String> entryIds, {
    bool dryRun = false,
  }) => _unavailable();
  @override
  Map<String, dynamic> emptyTrash() => _unavailable();
}

class _UnavailableCapabilityPort implements CapabilityEnginePort {
  const _UnavailableCapabilityPort();

  Never _unavailable() => throw StateError('Capability port is unavailable');

  @override
  bool get hasCapabilityApi => false;
  @override
  Map<String, dynamic> probeCapabilities() => _unavailable();
  @override
  bool isDeepScanReady() => _unavailable();
  @override
  bool openPermissionSettings() => _unavailable();
  @override
  String analyzeCapability(
    String snapshotId,
    String capability,
    String optionsJson,
  ) => _unavailable();
  @override
  String startCapabilityAnalysis(
    String snapshotId,
    String capability,
    String optionsJson,
  ) => _unavailable();
  @override
  String getCapabilityJobStatus(String jobId) => _unavailable();
  @override
  bool cancelCapabilityAnalysis(String jobId) => _unavailable();
}

class _UnavailableAiPort implements AiEnginePort {
  const _UnavailableAiPort();

  Never _unavailable() => throw StateError('AI port is unavailable');

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
  String? buildAiCandidatesJson(String snapshotId) => _unavailable();
  @override
  String? startBuildAiCandidatesAsync(String snapshotId) => _unavailable();
  @override
  bool isAiCandidatesBuilding() => _unavailable();
  @override
  String? getAiCandidatesJson() => _unavailable();
  @override
  String? takeAiCandidatesSpillPath() => _unavailable();
  @override
  String? startBuildAiCoveragePlanAsync(
    String snapshotId, {
    required bool tree,
  }) => _unavailable();
  @override
  bool isAiCoveragePlanBuilding() => _unavailable();
  @override
  String? getAiCoveragePlanJson() => _unavailable();
  @override
  String? buildAiCoveragePlanJson(String snapshotId) => _unavailable();
  @override
  String? listLocalCoverageVerdictsJson(
    String snapshotId,
    int cursor, {
    int limit = 5000,
  }) => _unavailable();
  @override
  String? nextAiCoveragePageJson(
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 40,
  }) => _unavailable();
  @override
  String? resolveAiCoverageGroupJson(String snapshotId, String groupPath) =>
      _unavailable();
  @override
  String? buildAiTreeCoveragePlanJson(String snapshotId) => _unavailable();
  @override
  String? nextAiTreeCoveragePageJson(
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 80,
  }) => _unavailable();
  @override
  String? nextAiTailCoveragePageJson(
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 40,
  }) => _unavailable();
  @override
  String? nextAiScopeCoveragePageJson(
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 1000,
  }) => _unavailable();
  @override
  String? expandAiTreeNodeJson(String snapshotId, String dirPath) =>
      _unavailable();
  @override
  String? applyAiDirVerdictJson(
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
  ) => _unavailable();
  @override
  String? applyAiDirVerdictToFile(
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
    String outPath,
  ) => _unavailable();
  @override
  bool saveAiResultJson(String snapshotId, String resultJson) => _unavailable();
  @override
  String? loadAiResultJson(String snapshotId) => _unavailable();
  @override
  String? aiUpstreamEndpoint() => _unavailable();
  @override
  int? aiBatchSize() => _unavailable();
  @override
  String? aiBuildRequestJson(String candidatesJson) => _unavailable();
  @override
  String? aiBuildConclusionSynthesisJson(String userJson) => _unavailable();
  @override
  String? aiParseResponseJson(String upstreamBody, String batchJson) =>
      _unavailable();
  @override
  int? aiTreeBatchSize() => _unavailable();
  @override
  String? aiBuildTreeRequestJson(String nodesJson) => _unavailable();
  @override
  String? aiParseTreeResponseJson(String upstreamBody, String batchJson) =>
      _unavailable();
}
