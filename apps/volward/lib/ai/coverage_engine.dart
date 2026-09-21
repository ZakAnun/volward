import 'coverage_models.dart';

abstract interface class CoverageEngine {
  Future<CoveragePlanSummary> buildPlan(String snapshotId);

  Future<CoveragePage> nextPage(String snapshotId, int planVersion, int cursor);

  Future<CoveragePlanSummary> buildTreePlan(String snapshotId);

  Future<CoverageTreePage> nextTreePage(
    String snapshotId,
    int planVersion,
    int cursor, {
    int? pageSize,
  });

  Future<CoverageTailPage> nextTailPage(
    String snapshotId,
    int planVersion,
    int cursor, {
    int? pageSize,
  });

  Future<List<CoverageTreeNode>> expandTreeNode(
    String snapshotId,
    String dirPath,
  );

  Future<List<Map<String, dynamic>>> resolveGroupMembers(
    String snapshotId,
    String groupPath,
  );
}

class FakeCoverageEngine implements CoverageEngine {
  FakeCoverageEngine({
    required this.summary,
    required this.pages,
    this.treeSummary,
    this.treePages = const [],
    this.tailPages = const [],
    this.expandNodes = const [],
    this.groupMembers = const [],
    this.onBuildPlan,
  });

  final CoveragePlanSummary summary;
  final List<CoveragePage> pages;
  final CoveragePlanSummary? treeSummary;
  final List<CoverageTreePage> treePages;
  final List<CoverageTailPage> tailPages;
  final List<CoverageTreeNode> expandNodes;
  final List<Map<String, dynamic>> groupMembers;
  final void Function()? onBuildPlan;

  @override
  Future<CoveragePlanSummary> buildPlan(String snapshotId) async {
    onBuildPlan?.call();
    return summary;
  }

  @override
  Future<CoveragePage> nextPage(
    String snapshotId,
    int planVersion,
    int cursor,
  ) async {
    final index = pages.indexWhere(
      (page) => page.rows.isNotEmpty && page.rows.first.rowIndex == cursor,
    );
    if (index >= 0) return pages[index];
    return CoveragePage(
      snapshotId: snapshotId,
      planVersion: planVersion,
      nextCursor: null,
      rows: const [],
    );
  }

  @override
  Future<CoveragePlanSummary> buildTreePlan(String snapshotId) async =>
      treeSummary ?? summary;

  @override
  Future<CoverageTreePage> nextTreePage(
    String snapshotId,
    int planVersion,
    int cursor, {
    int? pageSize,
  }) async {
    if (treePages.isNotEmpty) return treePages.first;
    return CoverageTreePage(
      snapshotId: snapshotId,
      planVersion: planVersion,
      nextCursor: null,
      nodes: const [],
    );
  }

  @override
  Future<CoverageTailPage> nextTailPage(
    String snapshotId,
    int planVersion,
    int cursor, {
    int? pageSize,
  }) async {
    if (tailPages.isNotEmpty) return tailPages.first;
    return CoverageTailPage(
      snapshotId: snapshotId,
      planVersion: planVersion,
      nextCursor: null,
      rows: const [],
    );
  }

  @override
  Future<List<CoverageTreeNode>> expandTreeNode(
    String snapshotId,
    String dirPath,
  ) async => expandNodes;

  @override
  Future<List<Map<String, dynamic>>> resolveGroupMembers(
    String snapshotId,
    String groupPath,
  ) async => groupMembers;
}
