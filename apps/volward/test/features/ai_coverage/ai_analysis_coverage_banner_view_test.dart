import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_coverage_banner_view.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_view_state.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/widgets/coverage_job_banner.dart';

void main() {
  testWidgets('coverage banner view renders a running job banner', (
    tester,
  ) async {
    final state = AiWorkspaceCoverageBannerState(
      job: const CoverageJobState(
        snapshotId: 'snapshot-a',
        rootPath: '/tmp/root',
        planVersion: 1,
        cursor: 0,
        totalUnclassified: 10,
        analyzedFiles: 3,
        preClassifiedCount: 2,
        status: CoverageJobStatus.running,
        usedTokens: 0,
        usedCredits: 0,
        budgetTokens: 0,
        budgetCredits: 100,
        updatedAtMs: 0,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AiAnalysisCoverageBannerView(
            state: state,
            onPause: () {},
            onResume: () {},
            onCancel: () {},
            onRaiseBudget: () {},
            onRestart: () {},
          ),
        ),
      ),
    );

    expect(find.byType(CoverageJobBanner), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
