import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/widgets/scan_filter_bar.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: buildVolwardTheme(brightness: Brightness.light),
      home: Scaffold(body: child),
    );
  }

  testWidgets('ScanFilterBar category pill invokes callback', (tester) async {
    String? selectedCategory = 'Cache';
    ScanSortMode sort = ScanSortMode.sizeDesc;

    await tester.pumpWidget(
      wrap(
        ScanFilterBar(
          categoryFilter: selectedCategory,
          onCategoryChanged: (cat) => selectedCategory = cat,
          sortMode: sort,
          onSortChanged: (mode) => sort = mode,
          deletableOnly: false,
          onDeletableOnlyChanged: (_) {},
          incrementalScan: false,
          onIncrementalScanChanged: (_) {},
          incrementalEnabled: true,
          scanning: false,
        ),
      ),
    );

    await tester.tap(find.text('All'));
    await tester.pump();

    expect(selectedCategory, isNull);
  });

  testWidgets('ScanFilterBar sort segment invokes callback', (tester) async {
    var sort = ScanSortMode.sizeDesc;

    await tester.pumpWidget(
      wrap(
        ScanFilterBar(
          categoryFilter: null,
          onCategoryChanged: (_) {},
          sortMode: sort,
          onSortChanged: (mode) => sort = mode,
          deletableOnly: false,
          onDeletableOnlyChanged: (_) {},
          incrementalScan: false,
          onIncrementalScanChanged: (_) {},
          incrementalEnabled: false,
          scanning: false,
        ),
      ),
    );

    await tester.tap(find.text('Name'));
    await tester.pump();

    expect(sort, ScanSortMode.nameAsc);
  });
}
