import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/widgets/ai_result_entry_tile.dart';

Widget _tileShell(Widget child) {
  return MaterialApp(
    theme: buildVolwardTheme(brightness: Brightness.light),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

void main() {
  testWidgets('shows basename as title and parent path as secondary', (
    tester,
  ) async {
    const item = AiVerdict(
      path: '/Users/x/Library/Caches/safe.cache',
      verdict: 'safe_to_remove',
      confidence: 'high',
      reason: 'Rebuildable cache',
    );

    await tester.pumpWidget(
      _tileShell(
        const AiResultEntryTile(
          item: item,
          sizeLabel: '100 B',
          variant: AiResultEntryTileVariant.previewSafe,
        ),
      ),
    );

    expect(find.text('safe.cache'), findsOneWidget);
    expect(find.text('/Users/x/Library/Caches'), findsOneWidget);
    expect(find.text('Rebuildable cache'), findsOneWidget);
  });

  testWidgets('review preview variant still foregrounds reason text', (
    tester,
  ) async {
    const item = AiVerdict(
      path: '/tmp/review.log',
      verdict: 'review_needed',
      confidence: 'medium',
      reason: 'uncertain ownership',
    );

    await tester.pumpWidget(
      _tileShell(
        const AiResultEntryTile(
          item: item,
          sizeLabel: '200 B',
          variant: AiResultEntryTileVariant.previewReview,
          reviewStatusLabel: 'Pending your decision',
        ),
      ),
    );

    expect(find.text('review.log'), findsOneWidget);
    expect(find.text('/tmp'), findsOneWidget);
    expect(find.text('uncertain ownership'), findsOneWidget);
    expect(find.text('Pending your decision'), findsOneWidget);
  });

  test('entryPathParts splits basename and parent directory', () {
    expect(entryPathParts('/Users/x/Library/Caches/safe.cache'), (
      'safe.cache',
      '/Users/x/Library/Caches',
    ));
    expect(entryPathParts('relative.file'), ('relative.file', null));
  });
}
