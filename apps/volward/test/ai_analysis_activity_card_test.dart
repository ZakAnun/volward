import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_analysis_activity_model.dart';
import 'package:volward/widgets/ai_analysis_activity_card.dart';

void main() {
  testWidgets('expanded shows active substage title', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiAnalysisActivityCard(
            variant: AiAnalysisActivityCardVariant.expanded,
            model: AiAnalysisActivityModel(
              visibleSubstages: [AiActivitySubstage.tail],
              activeSubstage: AiActivitySubstage.tail,
              completedSubstages: {},
              title: 'Analyzing files',
              subtitle: 'Please wait',
              progress: null,
              progressLabel: null,
              metrics: [],
              lastUpdated: null,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Analyzing files'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('compact shows stage, percent, and stays within 72dp', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiAnalysisActivityCard(
            variant: AiAnalysisActivityCardVariant.compact,
            model: AiAnalysisActivityModel(
              visibleSubstages: [AiActivitySubstage.tail],
              activeSubstage: AiActivitySubstage.tail,
              completedSubstages: {},
              title: 'Analyzing files',
              subtitle: 'Please wait',
              progress: 0.25,
              progressLabel: '25 / 100',
              metrics: [],
              lastUpdated: null,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(AiAnalysisActivityCard.compactKey), findsOneWidget);
    expect(find.text('tail'), findsOneWidget);
    expect(find.text('25 / 100'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    final height = tester
        .getSize(find.byKey(AiAnalysisActivityCard.compactKey))
        .height;
    expect(height, inInclusiveRange(56, 72));
  });

  testWidgets('active substage chip shows inline spinner in leading slot', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiAnalysisActivityCard(
            variant: AiAnalysisActivityCardVariant.expanded,
            freezeActiveMotion: true,
            model: AiAnalysisActivityModel(
              visibleSubstages: [AiActivitySubstage.candidates],
              activeSubstage: AiActivitySubstage.candidates,
              completedSubstages: {},
              title: 'Loading candidates',
              subtitle: 'Please wait',
              progress: null,
              progressLabel: null,
              metrics: [],
              lastUpdated: null,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(AiAnalysisActivityInlineSpinner), findsOneWidget);
  });

  testWidgets('substage chips share the same outer height', (tester) async {
    const chipOuterHeight = 34.0;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiAnalysisActivityCard(
            variant: AiAnalysisActivityCardVariant.expanded,
            model: AiAnalysisActivityModel(
              visibleSubstages: [
                AiActivitySubstage.tree,
                AiActivitySubstage.tail,
                AiActivitySubstage.finalize,
              ],
              activeSubstage: AiActivitySubstage.tail,
              completedSubstages: {AiActivitySubstage.tree},
              title: 'Analyzing files',
              subtitle: 'Please wait',
              progress: 0.5,
              progressLabel: null,
              metrics: [],
              lastUpdated: null,
            ),
          ),
        ),
      ),
    );

    final chips = find.byWidgetPredicate(
      (widget) => widget is SizedBox && widget.height == chipOuterHeight,
    );
    expect(chips, findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      expect(tester.getSize(chips.at(i)).height, chipOuterHeight);
    }
  });

  testWidgets('compact progress bar is determinate when motion frozen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiAnalysisActivityCard(
            variant: AiAnalysisActivityCardVariant.compact,
            freezeActiveMotion: true,
            model: AiAnalysisActivityModel(
              visibleSubstages: [AiActivitySubstage.tail],
              activeSubstage: AiActivitySubstage.tail,
              completedSubstages: {},
              title: 'Analyzing files',
              subtitle: 'Please wait',
              progress: null,
              progressLabel: null,
              metrics: [],
              lastUpdated: null,
            ),
          ),
        ),
      ),
    );

    final bar = tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byKey(AiAnalysisActivityCard.compactKey),
        matching: find.byType(LinearProgressIndicator),
      ),
    );
    expect(bar.value, 0);
  });

  testWidgets('expanded progress bar is determinate when motion frozen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiAnalysisActivityCard(
            variant: AiAnalysisActivityCardVariant.expanded,
            freezeActiveMotion: true,
            model: AiAnalysisActivityModel(
              visibleSubstages: [AiActivitySubstage.tail],
              activeSubstage: AiActivitySubstage.tail,
              completedSubstages: {},
              title: 'Analyzing files',
              subtitle: 'Pausing analysis…',
              progress: null,
              progressLabel: null,
              metrics: [],
              lastUpdated: null,
            ),
          ),
        ),
      ),
    );

    final bars = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .toList();
    // Main progress bar (5dp, frozen to 0) — substage track is frozen away.
    expect(bars, isNotEmpty);
    expect(bars.every((bar) => bar.value == 0), isTrue);
  });
}
