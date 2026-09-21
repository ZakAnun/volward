import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_client_logic.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_models.dart';

void main() {
  CoverageJobState job({
    CoverageJobStatus status = CoverageJobStatus.paused,
    int clientLogicVersion = 1,
    int planVersion = 1,
  }) => CoverageJobState(
    snapshotId: 's',
    rootPath: '/',
    planVersion: planVersion,
    cursor: 0,
    totalUnclassified: 10,
    analyzedFiles: 0,
    preClassifiedCount: 0,
    status: status,
    usedTokens: 0,
    usedCredits: 0,
    budgetTokens: 0,
    budgetCredits: 50,
    updatedAtMs: 0,
    clientLogicVersion: clientLogicVersion,
  );

  test('v2 plan active job needs upgrade at client logic v3', () {
    expect(
      coverageJobNeedsClientLogicUpgrade(
        job(planVersion: 2, clientLogicVersion: kCoverageClientLogicVersion),
      ),
      isTrue,
    );
    expect(
      coverageJobNeedsClientLogicUpgrade(
        job(planVersion: 3, clientLogicVersion: kCoverageClientLogicVersion),
      ),
      isFalse,
    );
  });

  test('legacy active job needs upgrade when version below current', () {
    expect(coverageJobNeedsClientLogicUpgrade(job()), isTrue);
    expect(
      coverageJobNeedsClientLogicUpgrade(
        job(
          clientLogicVersion: kCoverageClientLogicVersion,
          planVersion: kCoverageClientLogicVersion,
        ),
      ),
      isFalse,
    );
  });

  test('precheck credits prefer v3 tree and tail breakdown', () {
    const v3 = CoveragePlanSummary(
      snapshotId: 's',
      planVersion: 3,
      rootPath: '/',
      totalUnclassified: 10,
      preClassifiedCount: 0,
      groupRows: 0,
      fileRows: 10,
      estimatedPages: 99,
      localSafeFiles: 1,
      localKeepFiles: 2,
      estimatedTreeCredits: 4,
      estimatedTailCredits: 2,
      seedNodeCount: 1,
    );
    expect(coveragePrecheckEstimatedCredits(v3), 6);
    expect(
      coveragePrecheckEstimatedCredits(
        const CoveragePlanSummary(
          snapshotId: 's',
          planVersion: 1,
          rootPath: '/',
          totalUnclassified: 10,
          preClassifiedCount: 0,
          groupRows: 0,
          fileRows: 10,
          estimatedPages: 8,
        ),
      ),
      8,
    );
  });

  test('completed legacy job does not need upgrade', () {
    expect(
      coverageJobNeedsClientLogicUpgrade(
        job(status: CoverageJobStatus.completed),
      ),
      isFalse,
    );
  });
}
