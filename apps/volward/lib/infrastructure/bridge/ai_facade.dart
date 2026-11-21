import 'dart:ffi';

import 'ai_bridge.dart';

mixin AiBridgeFacade {
  AiBridge get aiBridge;

  bool get hasApplyDirVerdictToFileApi => aiBridge.hasApplyDirVerdictToFileApi;
  bool get hasAsyncAiCandidatesApi => aiBridge.hasAsyncAiCandidatesApi;
  bool get hasAsyncAiCoveragePlanApi => aiBridge.hasAsyncAiCoveragePlanApi;
  bool get hasAiSessionApi => aiBridge.hasAiSessionApi;
  bool get hasAiContractApi => aiBridge.hasAiContractApi;
  bool get hasAiTreeContractApi => aiBridge.hasAiTreeContractApi;
  bool get hasAiCoverageApi => aiBridge.hasAiCoverageApi;
  bool get hasAiTreeCoverageApi => aiBridge.hasAiTreeCoverageApi;

  String? buildAiCandidatesJson(Pointer<Void> engine, String snapshotId) =>
      aiBridge.buildAiCandidatesJson(engine, snapshotId);
  String? startBuildAiCandidatesAsync(
    Pointer<Void> engine,
    String snapshotId,
  ) => aiBridge.startBuildAiCandidatesAsync(engine, snapshotId);
  bool isAiCandidatesBuilding(Pointer<Void> engine) =>
      aiBridge.isAiCandidatesBuilding(engine);
  String? getAiCandidatesJson(Pointer<Void> engine) =>
      aiBridge.getAiCandidatesJson(engine);
  String? takeAiCandidatesSpillPath(Pointer<Void> engine) =>
      aiBridge.takeAiCandidatesSpillPath(engine);
  String? startBuildAiCoveragePlanAsync(
    Pointer<Void> engine,
    String snapshotId, {
    required bool tree,
  }) => aiBridge.startBuildAiCoveragePlanAsync(engine, snapshotId, tree: tree);
  bool isAiCoveragePlanBuilding(Pointer<Void> engine) =>
      aiBridge.isAiCoveragePlanBuilding(engine);
  String? getAiCoveragePlanJson(Pointer<Void> engine) =>
      aiBridge.getAiCoveragePlanJson(engine);
  String? buildAiCoveragePlanJson(Pointer<Void> engine, String snapshotId) =>
      aiBridge.buildAiCoveragePlanJson(engine, snapshotId);
  String? listLocalCoverageVerdictsJson(
    Pointer<Void> engine,
    String snapshotId,
    int cursor, {
    int limit = 5000,
  }) => aiBridge.listLocalCoverageVerdictsJson(
    engine,
    snapshotId,
    cursor,
    limit: limit,
  );
  String? nextAiCoveragePageJson(
    Pointer<Void> engine,
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 40,
  }) => aiBridge.nextAiCoveragePageJson(
    engine,
    snapshotId,
    planVersion,
    cursor,
    pageSize: pageSize,
  );
  String? resolveAiCoverageGroupJson(
    Pointer<Void> engine,
    String snapshotId,
    String groupPath,
  ) => aiBridge.resolveAiCoverageGroupJson(engine, snapshotId, groupPath);
  String? buildAiTreeCoveragePlanJson(
    Pointer<Void> engine,
    String snapshotId,
  ) => aiBridge.buildAiTreeCoveragePlanJson(engine, snapshotId);
  String? nextAiTreeCoveragePageJson(
    Pointer<Void> engine,
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 80,
  }) => aiBridge.nextAiTreeCoveragePageJson(
    engine,
    snapshotId,
    planVersion,
    cursor,
    pageSize: pageSize,
  );
  String? nextAiTailCoveragePageJson(
    Pointer<Void> engine,
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 40,
  }) => aiBridge.nextAiTailCoveragePageJson(
    engine,
    snapshotId,
    planVersion,
    cursor,
    pageSize: pageSize,
  );
  String? expandAiTreeNodeJson(
    Pointer<Void> engine,
    String snapshotId,
    String dirPath,
  ) => aiBridge.expandAiTreeNodeJson(engine, snapshotId, dirPath);
  String? applyAiDirVerdictJson(
    Pointer<Void> engine,
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
  ) => aiBridge.applyAiDirVerdictJson(
    engine,
    snapshotId,
    dirPath,
    verdict,
    confidence,
    roleSnakeCase,
  );
  String? applyAiDirVerdictToFile(
    Pointer<Void> engine,
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
    String outPath,
  ) => aiBridge.applyAiDirVerdictToFile(
    engine,
    snapshotId,
    dirPath,
    verdict,
    confidence,
    roleSnakeCase,
    outPath,
  );
  bool saveAiResultJson(
    Pointer<Void> engine,
    String snapshotId,
    String resultJson,
  ) => aiBridge.saveAiResultJson(engine, snapshotId, resultJson);
  String? loadAiResultJson(Pointer<Void> engine, String snapshotId) =>
      aiBridge.loadAiResultJson(engine, snapshotId);
  String? aiUpstreamEndpoint() => aiBridge.aiUpstreamEndpoint();
  int? aiBatchSize() => aiBridge.aiBatchSize();
  String? aiBuildRequestJson(String candidatesJson) =>
      aiBridge.aiBuildRequestJson(candidatesJson);
  String? aiBuildConclusionSynthesisJson(String userJson) =>
      aiBridge.aiBuildConclusionSynthesisJson(userJson);
  String? aiParseResponseJson(String upstreamBody, String batchJson) =>
      aiBridge.aiParseResponseJson(upstreamBody, batchJson);
  int? aiTreeBatchSize() => aiBridge.aiTreeBatchSize();
  String? aiBuildTreeRequestJson(String nodesJson) =>
      aiBridge.aiBuildTreeRequestJson(nodesJson);
  String? aiParseTreeResponseJson(String upstreamBody, String batchJson) =>
      aiBridge.aiParseTreeResponseJson(upstreamBody, batchJson);
}
