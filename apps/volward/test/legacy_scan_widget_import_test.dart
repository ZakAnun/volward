import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/widgets/scan_column_view.dart';
import 'package:volward/widgets/scan_filter_bar.dart';

void main() {
  test('legacy widget imports expose their public declarations', () {
    expect(ScanColumnView, isNotNull);
    expect(ScanColumnTap, isNotNull);
    expect(ScanColumnSelectCallback, isNotNull);
    expect(
      paintedRowRange(offset: 0, viewportHeight: 28, itemCount: 1).last,
      1,
    );
    expect(ScanFilterBar, isNotNull);
    expect(ScanSortMode.values, isNotEmpty);
  });

  testWidgets('legacy filter import exposes the sort label extension', (
    tester,
  ) async {
    String? label;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            label = ScanSortMode.nameAsc.label(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(label, isNotEmpty);
  });
}
