import 'dart:ffi';

import '../bridge/native_bridge.dart';
import 'coverage_engine.dart';
import 'coverage_models.dart';
import 'coverage_native_responses.dart';

/// FFI-backed [CoverageEngine] that delegates to Rust coverage plan APIs.
class NativeCoverageEngine implements CoverageEngine {
  NativeCoverageEngine({
    required this.bridge,
    required this.engine,
    this.pageSize = 40,
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
