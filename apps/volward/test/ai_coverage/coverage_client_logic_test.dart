import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_client_logic.dart';
import 'package:volward/ai/coverage_job_state.dart';

void main() {
  CoverageJobState job({
    CoverageJobStatus status = CoverageJobStatus.paused,
    int clientLogicVersion = 1,
  }) => CoverageJobState(
    snapshotId: 's',
    rootPath: '/',
    planVersion: 1,
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

  test('legacy active job needs upgrade when version below current', () {
    expect(coverageJobNeedsClientLogicUpgrade(job()), isTrue);
    expect(
      coverageJobNeedsClientLogicUpgrade(
        job(clientLogicVersion: kCoverageClientLogicVersion),
      ),
      isFalse,
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
