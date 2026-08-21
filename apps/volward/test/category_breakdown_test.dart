import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/storage_home_summary.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/theme/volward_tokens.dart';
import 'package:volward/widgets/home/category_breakdown.dart';

void main() {
  Future<void> pumpBreakdown(
    WidgetTester tester, {
    required double width,
    required List<StorageHomeCategorySummary> categories,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildVolwardTheme(
          brightness: Brightness.dark,
          accent: VolwardTokens.defaultAccent,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: CategoryBreakdown(
                categories: categories,
                enabled: true,
                onSelectCategory: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Seven-digit counts are what a full-disk scan actually produces, and every
  // named category plus Other is five rows — enough to trip the two-column
  // legend.
  const crowded = [
    StorageHomeCategorySummary(name: 'Cache', count: 1234567),
    StorageHomeCategorySummary(name: 'Temp', count: 2345678),
    StorageHomeCategorySummary(name: 'Media', count: 3456789),
    StorageHomeCategorySummary(name: 'System', count: 4567890),
    StorageHomeCategorySummary(name: 'Other', count: 5678901),
  ];

  for (final width in <double>[240, 300, 360, 420, 520]) {
    testWidgets('the legend fits at ${width.toInt()}px', (tester) async {
      await pumpBreakdown(tester, width: width, categories: crowded);

      expect(
        tester.takeException(),
        isNull,
        reason: 'legend overflowed at ${width}px',
      );
    });
  }

  testWidgets('a narrow legend falls back to one column', (tester) async {
    await pumpBreakdown(tester, width: 240, categories: crowded);

    // One column means the five rows stack: each row's top is distinct and the
    // rows all share a left edge.
    final rows = tester
        .widgetList<InkWell>(find.byType(InkWell))
        .map((w) => tester.getRect(find.byWidget(w)))
        .toList();
    expect(rows, hasLength(5));
    for (var i = 1; i < rows.length; i++) {
      expect(rows[i].left, closeTo(rows.first.left, 0.5));
      expect(rows[i].top, greaterThan(rows[i - 1].top));
    }
  });

  testWidgets('a wide legend still splits into two columns', (tester) async {
    await pumpBreakdown(tester, width: 520, categories: crowded);

    final rows = tester
        .widgetList<InkWell>(find.byType(InkWell))
        .map((w) => tester.getRect(find.byWidget(w)))
        .toList();
    expect(rows, hasLength(5));
    // Rows 0-2 in the left column, 3-4 in the right: the fourth row starts a
    // new column, so it sits back at the top and further right.
    expect(rows[3].top, closeTo(rows[0].top, 0.5));
    expect(rows[3].left, greaterThan(rows[0].right));
  });
}
