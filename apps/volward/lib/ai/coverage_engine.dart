import 'coverage_models.dart';
import 'coverage_native_responses.dart';
import 'coverage_verdict_store.dart';

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

  Future<List<CoverageVerdict>> applyDirVerdict(
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
  );

  Future<List<Map<String, dynamic>>> resolveGroupMembers(
    String snapshotId,
    String groupPath,
  );

  Future<LocalCoverageVerdictPage> fetchLocalVerdictsPage(
    String snapshotId, {
    int cursor = 0,
    int limit = 5000,
  });
}

Future<List<CoverageVerdict>> fetchAllLocalVerdicts(
  CoverageEngine engine, {
  required String snapshotId,
  int pageLimit = 5000,
}) async {
  final all = <CoverageVerdict>[];
  var cursor = 0;
  while (true) {
    final page = await engine.fetchLocalVerdictsPage(
      snapshotId,
      cursor: cursor,
      limit: pageLimit,
    );
    if (page.verdicts.isEmpty) break;
    all.addAll(page.verdicts);
    final next = page.nextCursor;
    if (next == null) break;
    cursor = next;
  }
  return all;
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
    this.onBuildTreePlan,
    this.localVerdictFetcher,
    this.applyDirVerdictHandler,
    this.treePagesByCursor = const {},
  });

  final CoveragePlanSummary summary;
  final List<CoveragePage> pages;
  final CoveragePlanSummary? treeSummary;
  final List<CoverageTreePage> treePages;
  final List<CoverageTailPage> tailPages;
  final List<CoverageTreeNode> expandNodes;
  final List<Map<String, dynamic>> groupMembers;
  final void Function()? onBuildPlan;
  final void Function()? onBuildTreePlan;
  final List<CoverageVerdict> Function(int cursor)? localVerdictFetcher;
  final Future<List<CoverageVerdict>> Function(
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
  )?
  applyDirVerdictHandler;
  final Map<int, CoverageTreePage> treePagesByCursor;

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
  Future<CoveragePlanSummary> buildTreePlan(String snapshotId) async {
    onBuildTreePlan?.call();
    return treeSummary ?? summary;
  }

  @override
  Future<CoverageTreePage> nextTreePage(
    String snapshotId,
    int planVersion,
    int cursor, {
    int? pageSize,
  }) async {
    final byCursor = treePagesByCursor[cursor];
    if (byCursor != null) return byCursor;
    if (treePages.isNotEmpty && cursor == 0) return treePages.first;
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
  Future<List<CoverageVerdict>> applyDirVerdict(
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
  ) async {
    if (applyDirVerdictHandler != null) {
      return applyDirVerdictHandler!(
        dirPath,
        verdict,
        confidence,
        roleSnakeCase,
      );
    }
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> resolveGroupMembers(
    String snapshotId,
    String groupPath,
  ) async => groupMembers;

  @override
  Future<LocalCoverageVerdictPage> fetchLocalVerdictsPage(
    String snapshotId, {
    int cursor = 0,
    int limit = 5000,
  }) async {
    if (localVerdictFetcher == null) {
      return const LocalCoverageVerdictPage(verdicts: []);
    }
    final verdicts = localVerdictFetcher!(cursor);
    if (verdicts.isEmpty) {
      return const LocalCoverageVerdictPage(verdicts: []);
    }
    final nextCursor = verdicts.length >= limit
        ? cursor + verdicts.length
        : null;
    return LocalCoverageVerdictPage(verdicts: verdicts, nextCursor: nextCursor);
  }
}
