import 'coverage_models.dart';

abstract interface class CoverageEngine {
  Future<CoveragePlanSummary> buildPlan(String snapshotId);

  Future<CoveragePage> nextPage(String snapshotId, int planVersion, int cursor);

  Future<List<Map<String, dynamic>>> resolveGroupMembers(
    String snapshotId,
    String groupPath,
  );
}

class FakeCoverageEngine implements CoverageEngine {
  FakeCoverageEngine({
    required this.summary,
    required this.pages,
    this.groupMembers = const [],
  });

  final CoveragePlanSummary summary;
  final List<CoveragePage> pages;
  final List<Map<String, dynamic>> groupMembers;

  @override
  Future<CoveragePlanSummary> buildPlan(String snapshotId) async => summary;

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
  Future<List<Map<String, dynamic>>> resolveGroupMembers(
    String snapshotId,
    String groupPath,
  ) async => groupMembers;
}
