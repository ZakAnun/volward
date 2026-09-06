import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_engine.dart';
import 'package:volward/ai/coverage_models.dart';

void main() {
  test('FakeCoverageEngine pages rows by cursor', () async {
    final engine = FakeCoverageEngine(
      summary: const CoveragePlanSummary(
        snapshotId: 's1',
        planVersion: 1,
        rootPath: '/',
        totalUnclassified: 2,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 2,
        estimatedPages: 1,
      ),
      pages: [
        const CoveragePage(
          snapshotId: 's1',
          planVersion: 1,
          nextCursor: null,
          rows: [
            CoverageRow(
              rowIndex: 0,
              kind: CoverageRowKind.file,
              path: '/a',
              sizeBytes: 1,
            ),
            CoverageRow(
              rowIndex: 1,
              kind: CoverageRowKind.file,
              path: '/b',
              sizeBytes: 2,
            ),
          ],
        ),
      ],
    );
    final summary = await engine.buildPlan('s1');
    final page = await engine.nextPage('s1', summary.planVersion, 0);
    expect(page.rows, hasLength(2));
  });
}
