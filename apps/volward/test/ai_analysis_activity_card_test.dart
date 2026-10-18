import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_analysis_activity_model.dart';
import 'package:volward/widgets/ai_analysis_activity_card.dart';

void main() {
  testWidgets('expanded shows active substage title', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
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
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
