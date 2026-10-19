import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/widgets/ai_analysis_scope_panel.dart';
import 'package:volward/widgets/ai_results_hub.dart';

Widget _panelShell(Widget child) {
  return MaterialApp(
    theme: buildVolwardTheme(brightness: Brightness.light),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('scope panel expands for awaitingAnalysis by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panelShell(
        AiAnalysisScopePanel(
          hubMode: ResultsHubMode.awaitingAnalysis,
          summaryLine: 'summary',
          expandedBodyBuilder: (_) => const Text('scope-body'),
        ),
      ),
    );

    expect(find.text('scope-body'), findsOneWidget);
  });

  testWidgets('scope panel collapses for ready until toggled', (tester) async {
    await tester.pumpWidget(
      _panelShell(
        AiAnalysisScopePanel(
          hubMode: ResultsHubMode.ready,
          summaryLine: 'summary',
          expandedBodyBuilder: (_) => const Text('scope-body'),
        ),
      ),
    );

    expect(find.text('scope-body'), findsNothing);
    expect(find.text('summary'), findsOneWidget);

    await tester.tap(find.byKey(AiAnalysisScopePanel.toggleKey));
    await tester.pumpAndSettle();

    expect(find.text('scope-body'), findsOneWidget);
  });

  testWidgets('scope panel collapses when hub mode leaves awaitingAnalysis', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panelShell(
        AiAnalysisScopePanel(
          hubMode: ResultsHubMode.awaitingAnalysis,
          summaryLine: 'summary',
          expandedBodyBuilder: (_) => const Text('scope-body'),
        ),
      ),
    );
    expect(find.text('scope-body'), findsOneWidget);

    await tester.pumpWidget(
      _panelShell(
        AiAnalysisScopePanel(
          hubMode: ResultsHubMode.ready,
          summaryLine: 'summary',
          expandedBodyBuilder: (_) => const Text('scope-body'),
        ),
      ),
    );
    expect(find.text('scope-body'), findsNothing);
  });
}
