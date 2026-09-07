import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_verdict_store.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/widgets/coverage_job_banner.dart';

void main() {
  testWidgets('CoverageJobBanner is a single progress row while running', (
    tester,
  ) async {
    const state = CoverageJobState(
      snapshotId: 's1',
      rootPath: '/',
      planVersion: 1,
      cursor: 0,
      totalUnclassified: 100,
      analyzedFiles: 10,
      preClassifiedCount: 0,
      status: CoverageJobStatus.running,
      usedTokens: 0,
      usedCredits: 0,
      budgetTokens: 1000,
      budgetCredits: 0,
      updatedAtMs: 1,
    );
    var paused = false;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CoverageJobBanner(
            state: state,
            verdictRows: const [
              CoverageVerdict(
                path: '/a',
                verdict: 'keep',
                confidence: 'high',
                reason: 'x',
                coverageSource: 'file',
                sizeBytes: 1,
              ),
            ],
            onPause: () => paused = true,
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('10'), findsWidgets);
    expect(find.text('Pause coverage'), findsOneWidget);
    expect(find.textContaining('per-file'), findsNothing);
    expect(
      find.text('This scan is fully covered by AI analysis.'),
      findsNothing,
    );
    expect(find.text('Stop coverage'), findsNothing);
    await tester.tap(find.text('Pause coverage'));
    await tester.pumpAndSettle();
    expect(paused, isTrue);
  });

  testWidgets('CoverageJobBanner shows raise budget when budget paused', (
    tester,
  ) async {
    const state = CoverageJobState(
      snapshotId: 's1',
      rootPath: '/',
      planVersion: 1,
      cursor: 0,
      totalUnclassified: 100,
      analyzedFiles: 50,
      preClassifiedCount: 0,
      status: CoverageJobStatus.paused,
      pauseReason: CoveragePauseReason.budget,
      usedTokens: 1000,
      usedCredits: 0,
      budgetTokens: 1000,
      budgetCredits: 0,
      updatedAtMs: 1,
    );
    var raised = false;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CoverageJobBanner(
            state: state,
            verdictRows: const [
              CoverageVerdict(
                path: '/a',
                verdict: 'keep',
                confidence: 'high',
                reason: 'x',
                coverageSource: 'file',
                sizeBytes: 1,
              ),
            ],
            onResume: () {},
            onRaiseBudget: () => raised = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Raise limit & resume'), findsOneWidget);
    expect(find.textContaining('per-file'), findsNothing);
    await tester.tap(find.text('Raise limit & resume'));
    await tester.pumpAndSettle();
    expect(raised, isTrue);
  });
}
