import 'coverage_engine.dart';

/// Snapshot access needed to assemble a coverage job; owns no engine or state.
abstract interface class CoverageSnapshotReader {
  CoverageEngine? get coverageEngine;
  bool get hasAiTreeCoverageApi;
  bool get hasIndexApi;
  String? get currentCoverageSnapshotId;
  Future<String?> catalogIndexPathForAiCoverage(String snapshotId);
}
