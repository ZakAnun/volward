import 'dart:ffi';

import '../bridge/native_bridge.dart';
import 'coverage_engine.dart';
import 'coverage_models.dart';
import 'coverage_native_responses.dart';
import 'coverage_verdict_store.dart';

/// FFI-backed [CoverageEngine] that delegates to Rust coverage plan APIs.
class NativeCoverageEngine implements CoverageEngine {
  NativeCoverageEngine({
    required this.bridge,
    required this.engine,
    this.pageSize = 200,
  });

  final VolwardNativeBridge bridge;
  final Pointer<Void> engine;
  final int pageSize;

  String _requireJson(String? raw, String operation) {
    if (raw == null || raw.isEmpty) {
      throw CoverageEngineException('error:native $operation unavailable');
    }
    return raw;
  }

  @override
  Future<CoveragePlanSummary> buildPlan(String snapshotId) async {
    final raw = _requireJson(
      bridge.buildAiCoveragePlanJson(engine, snapshotId),
      'build coverage plan',
    );
    final summary = parseCoveragePlanSummary(raw);
    if (summary.snapshotId != snapshotId) {
      throw CoverageEngineException('error:coverage plan snapshot mismatch');
    }
    return summary;
  }

  @override
  Future<CoveragePage> nextPage(
    String snapshotId,
    int planVersion,
    int cursor,
  ) async {
    final raw = _requireJson(
      bridge.nextAiCoveragePageJson(
        engine,
        snapshotId,
        planVersion,
        cursor,
        pageSize: pageSize,
      ),
      'next coverage page',
    );
    final page = parseCoveragePage(raw);
    if (page.snapshotId != snapshotId || page.planVersion != planVersion) {
      throw CoverageEngineException('error:coverage page mismatch');
    }
    return page;
  }

  @override
  Future<CoveragePlanSummary> buildTreePlan(String snapshotId) async {
    final raw = _requireJson(
      bridge.buildAiTreeCoveragePlanJson(engine, snapshotId),
      'build tree coverage plan',
    );
    final summary = parseCoveragePlanSummary(raw);
    if (summary.snapshotId != snapshotId) {
      throw CoverageEngineException(
        'error:tree coverage plan snapshot mismatch',
      );
    }
    return summary;
  }

  @override
  Future<CoverageTreePage> nextTreePage(
    String snapshotId,
    int planVersion,
    int cursor, {
    int? pageSize,
  }) async {
    final raw = _requireJson(
      bridge.nextAiTreeCoveragePageJson(
        engine,
        snapshotId,
        planVersion,
        cursor,
        pageSize: pageSize ?? this.pageSize,
      ),
      'next tree coverage page',
    );
    final page = parseCoverageTreePage(raw);
    if (page.snapshotId != snapshotId || page.planVersion != planVersion) {
      throw CoverageEngineException('error:tree coverage page mismatch');
    }
    return page;
  }

  @override
  Future<CoverageTailPage> nextTailPage(
    String snapshotId,
    int planVersion,
    int cursor, {
    int? pageSize,
  }) async {
    final raw = _requireJson(
      bridge.nextAiTailCoveragePageJson(
        engine,
        snapshotId,
        planVersion,
        cursor,
        pageSize: pageSize ?? this.pageSize,
      ),
      'next tail coverage page',
    );
    final page = parseCoverageTailPage(raw);
    if (page.snapshotId != snapshotId || page.planVersion != planVersion) {
      throw CoverageEngineException('error:tail coverage page mismatch');
    }
    return page;
  }

  @override
  Future<List<CoverageTreeNode>> expandTreeNode(
    String snapshotId,
    String dirPath,
  ) async {
    final raw = _requireJson(
      bridge.expandAiTreeNodeJson(engine, snapshotId, dirPath),
      'expand tree node',
    );
    return parseCoverageTreeExpandNodes(raw);
  }

  @override
  Future<List<CoverageVerdict>> applyDirVerdict(
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
  ) async {
    final raw = _requireJson(
      bridge.applyAiDirVerdictJson(
        engine,
        snapshotId,
        dirPath,
        verdict,
        confidence,
        roleSnakeCase,
      ),
      'apply dir verdict',
    );
    return parseApplyDirVerdictResponse(raw);
  }

  @override
  Future<LocalCoverageVerdictPage> fetchLocalVerdictsPage(
    String snapshotId, {
    int cursor = 0,
    int limit = 5000,
  }) async {
    final raw = _requireJson(
      bridge.listLocalCoverageVerdictsJson(
        engine,
        snapshotId,
        cursor,
        limit: limit,
      ),
      'list local coverage verdicts',
    );
    return parseLocalCoverageVerdictPage(raw);
  }

  @override
  Future<List<Map<String, dynamic>>> resolveGroupMembers(
    String snapshotId,
    String groupPath,
  ) async {
    final raw = _requireJson(
      bridge.resolveAiCoverageGroupJson(engine, snapshotId, groupPath),
      'resolve coverage group',
    );
    return parseCoverageGroupMembers(raw);
  }
}
