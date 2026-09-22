import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_banner_copy.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_models.dart';
import 'package:volward/l10n/generated/app_localizations_en.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('v3 plan shows funnel subtitle and API line', () {
    const state = CoverageJobState(
      snapshotId: 's',
      rootPath: '/Applications',
      planVersion: 3,
      cursor: 0,
      totalUnclassified: 372166,
      analyzedFiles: 0,
      preClassifiedCount: 0,
      status: CoverageJobStatus.paused,
      usedTokens: 0,
      usedCredits: 0,
      budgetTokens: 0,
      budgetCredits: 50,
      updatedAtMs: 1,
      estimatedTreeCredits: 1,
      estimatedTailCredits: 0,
    );
    const plan = CoveragePlanSummary(
      snapshotId: 's',
      planVersion: 3,
      rootPath: '/Applications',
      totalUnclassified: 372166,
      preClassifiedCount: 0,
      groupRows: 0,
      fileRows: 0,
      estimatedPages: 0,
      localSafeFiles: 5000,
      localKeepFiles: 360000,
      treePendingFiles: 7000,
      tailFiles: 166,
      estimatedTreeCredits: 1,
      estimatedTailCredits: 0,
    );
    final copy = buildCoverageBannerCopy(
      state: state,
      plan: plan,
      l10n: l10n,
      showPausedBeforeProgressNotice: true,
    );
    expect(copy.progressLine, contains('372166'));
    expect(copy.funnelLine, isNotNull);
    expect(copy.apiCallsLine, isNotNull);
    expect(copy.showCreditRemaining, isFalse);
    expect(copy.pausedNoticeLine, isNotNull);
  });

  test('BYOK token budget hides credit remaining line', () {
    const state = CoverageJobState(
      snapshotId: 's',
      rootPath: '/',
      planVersion: 3,
      cursor: 0,
      totalUnclassified: 10,
      analyzedFiles: 0,
      preClassifiedCount: 0,
      status: CoverageJobStatus.paused,
      usedTokens: 0,
      usedCredits: 0,
      budgetTokens: 500000,
      budgetCredits: 0,
      updatedAtMs: 1,
      estimatedTreeCredits: 1,
      estimatedTailCredits: 0,
    );
    final copy = buildCoverageBannerCopy(
      state: state,
      plan: null,
      l10n: l10n,
      showPausedBeforeProgressNotice: false,
    );
    expect(copy.showCreditRemaining, isFalse);
  });
}
