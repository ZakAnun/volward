import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_verdict_store.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/widgets/coverage_job_banner.dart';

Future<void> pumpBanner(WidgetTester tester, CoverageJobState state) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: CoverageJobBanner(
          state: state,
          verdictRows: const [],
          onResume: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

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

  testWidgets('CoverageJobBanner shows credits usage while running', (
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
      usedCredits: 3,
      budgetTokens: 0,
      budgetCredits: 50,
      updatedAtMs: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CoverageJobBanner(
            state: state,
            verdictRows: const [],
            onPause: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('3'), findsWidgets);
    expect(find.textContaining('50'), findsWidgets);
    expect(find.textContaining('Credits this run'), findsOneWidget);
  });

  testWidgets('paused banner shows remaining credit estimate', (tester) async {
    const state = CoverageJobState(
      snapshotId: 's1',
      rootPath: '/',
      planVersion: 1,
      cursor: 80,
      totalUnclassified: 200,
      analyzedFiles: 80,
      preClassifiedCount: 0,
      status: CoverageJobStatus.paused,
      pauseReason: CoveragePauseReason.manual,
      usedTokens: 0,
      usedCredits: 2,
      budgetTokens: 0,
      budgetCredits: 50,
      updatedAtMs: 1,
    );
    // 120 files left -> ceil(120/40)=3 credits
    await pumpBanner(tester, state);
    expect(find.textContaining('3'), findsWidgets);
  });

  testWidgets('budget pause hides resume and shows raise budget only', (
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
      usedTokens: 0,
      usedCredits: 20,
      budgetTokens: 0,
      budgetCredits: 20,
      updatedAtMs: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CoverageJobBanner(
            state: state,
            verdictRows: const [],
            onResume: () {},
            onRaiseBudget: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Resume coverage'), findsNothing);
    expect(find.text('Raise limit & resume'), findsOneWidget);
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
