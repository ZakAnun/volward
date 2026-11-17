abstract interface class ScanEnginePort {
  bool get hasScanOptionsApi;
  bool get hasQuickListApi;

  String startScan(String jobId, List<String> roots);
  String startScanAsync(String jobId, List<String> roots);
  String startScanAsyncWithOptions(
    String jobId,
    List<String> roots, {
    required bool incremental,
  });
  bool isScanRunning();
  Map<String, dynamic>? getLastProgress();
  void cancelScan();
  String requestScanPause(String root, String cacheDir);
  String? getLastPauseError();
  List<Map<String, dynamic>> quickListDir(String path);
}

abstract interface class IndexEnginePort {
  bool get hasSnapshotFileApi;
  bool get hasSnapshotFilePbApi;
  bool get hasCheckpointApi;
  bool get hasIndexApi;
  bool get hasReplaceSubtreeApi;
  bool get hasAsyncIndexLoadApi;

  Map<String, dynamic>? getLastSnapshot();
  bool setLastSnapshot(Map<String, dynamic> snapshot);
  String writeLastSnapshotToPath(String path);
  bool loadLastSnapshotFromPath(String path);
  String? writeLastCheckpointToPath(String path);
  String writeLastSnapshotToPathPb(String path);
  String? writeLastCheckpointToPathPb(String path);
  Map<String, dynamic> queryDirectoryJson(
    String path, {
    String? categoryFilter,
    bool deletableOnly = false,
    String sortMode = 'size_desc',
  });
  Map<String, dynamic> refreshDirectory(String path);
  bool loadIndexFromPath(String path);
  int? replaceDirectoryWithSubtree(String targetPath, String subtreeJson);
  String? startLoadIndexFromPathAsync(String path);
  bool isIndexLoading();
  void invalidateIndexLoad();
  String? getLastIndexLoadError();
  String? writeLastIndexToPath(String path);
  Map<String, dynamic>? getIndexSummaryJson();
  int indexVersion();
}

abstract interface class DeleteEnginePort {
  Map<String, dynamic> deleteEntries(
    String snapshotId,
    List<String> entryIds, {
    bool dryRun = false,
  });
  Map<String, dynamic> emptyTrash();
}

abstract interface class CapabilityEnginePort {
  bool get hasCapabilityApi;

  Map<String, dynamic> probeCapabilities();
  bool isDeepScanReady();
  bool openPermissionSettings();
  String analyzeCapability(
    String snapshotId,
    String capability,
    String optionsJson,
  );
  String startCapabilityAnalysis(
    String snapshotId,
    String capability,
    String optionsJson,
  );
  String getCapabilityJobStatus(String jobId);
  bool cancelCapabilityAnalysis(String jobId);
}

abstract interface class AiEnginePort {
  bool get hasApplyDirVerdictToFileApi;
  bool get hasAsyncAiCandidatesApi;
  bool get hasAsyncAiCoveragePlanApi;
  bool get hasAiSessionApi;
  bool get hasAiContractApi;
  bool get hasAiTreeContractApi;
  bool get hasAiCoverageApi;
  bool get hasAiTreeCoverageApi;

  String? buildAiCandidatesJson(String snapshotId);
  String? startBuildAiCandidatesAsync(String snapshotId);
  bool isAiCandidatesBuilding();
  String? getAiCandidatesJson();
  String? takeAiCandidatesSpillPath();
  String? startBuildAiCoveragePlanAsync(
    String snapshotId, {
    required bool tree,
  });
  bool isAiCoveragePlanBuilding();
  String? getAiCoveragePlanJson();
  String? buildAiCoveragePlanJson(String snapshotId);
  String? listLocalCoverageVerdictsJson(
    String snapshotId,
    int cursor, {
    int limit = 5000,
  });
  String? nextAiCoveragePageJson(
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 40,
  });
  String? resolveAiCoverageGroupJson(String snapshotId, String groupPath);
  String? buildAiTreeCoveragePlanJson(String snapshotId);
  String? nextAiTreeCoveragePageJson(
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 80,
  });
  String? nextAiTailCoveragePageJson(
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 40,
  });
  String? expandAiTreeNodeJson(String snapshotId, String dirPath);
  String? applyAiDirVerdictJson(
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
  );
  String? applyAiDirVerdictToFile(
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
    String outPath,
  );
  bool saveAiResultJson(String snapshotId, String resultJson);
  String? loadAiResultJson(String snapshotId);
  String? aiUpstreamEndpoint();
  int? aiBatchSize();
  String? aiBuildRequestJson(String candidatesJson);
  String? aiBuildConclusionSynthesisJson(String userJson);
  String? aiParseResponseJson(String upstreamBody, String batchJson);
  int? aiTreeBatchSize();
  String? aiBuildTreeRequestJson(String nodesJson);
  String? aiParseTreeResponseJson(String upstreamBody, String batchJson);
}
