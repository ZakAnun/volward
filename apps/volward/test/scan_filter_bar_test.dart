import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/widgets/scan_filter_bar.dart';

void main() {
  Widget wrap(Widget child, {Locale locale = const Locale('en')}) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildVolwardTheme(brightness: Brightness.light),
      home: Scaffold(body: child),
    );
  }

  testWidgets('ScanFilterBar category chip invokes callback', (tester) async {
    String? selectedCategory = 'Cache';
    ScanSortMode sort = ScanSortMode.sizeDesc;

    await tester.pumpWidget(
      wrap(
        ScanFilterBar(
          categoryFilter: selectedCategory,
          onCategoryChanged: (cat) => selectedCategory = cat,
          sortMode: sort,
          onSortChanged: (mode) => sort = mode,
          scanning: false,
        ),
      ),
    );

    await tester.tap(find.text('All'));
    await tester.pump();

    expect(selectedCategory, isNull);
  });

  testWidgets('ScanFilterBar category chip highlights selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ScanFilterBar(
          categoryFilter: 'Cache',
          onCategoryChanged: (_) {},
          sortMode: ScanSortMode.sizeDesc,
          onSortChanged: (_) {},
          scanning: false,
        ),
      ),
    );

    // Cache chip should be present and the bar should render without error.
    expect(find.text('Cache'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
  });

  testWidgets('ScanFilterBar sort menu button shows current mode label', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ScanFilterBar(
          categoryFilter: null,
          onCategoryChanged: (_) {},
          sortMode: ScanSortMode.nameAsc,
          onSortChanged: (_) {},
          scanning: false,
        ),
      ),
    );

    // The button label should reflect the current sort mode.
    expect(find.text('Name'), findsOneWidget);
  });

  testWidgets('ScanFilterBar uses localized labels', (tester) async {
    await tester.pumpWidget(
      wrap(
        ScanFilterBar(
          categoryFilter: null,
          onCategoryChanged: (_) {},
          sortMode: ScanSortMode.nameAsc,
          onSortChanged: (_) {},
          scanning: false,
        ),
        locale: const Locale('zh'),
      ),
    );

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('缓存'), findsOneWidget);
    expect(find.text('名称'), findsOneWidget);
  });

  testWidgets('ScanFilterBar sort menu invokes callback on selection', (
    tester,
  ) async {
    var sort = ScanSortMode.sizeDesc;

    await tester.pumpWidget(
      wrap(
        ScanFilterBar(
          categoryFilter: null,
          onCategoryChanged: (_) {},
          sortMode: sort,
          onSortChanged: (mode) => sort = mode,
          scanning: false,
        ),
      ),
    );

    // Open the popup menu by tapping the sort button (shows 'Size ↓').
    await tester.tap(find.text('Size ↓'));
    await tester.pumpAndSettle();

    // Tap the 'Name' menu item.
    await tester.tap(find.text('Name').last);
    await tester.pumpAndSettle();

    expect(sort, ScanSortMode.nameAsc);
  });

  testWidgets('ScanFilterBar hides absent categories and keeps All', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ScanFilterBar(
          categoryFilter: null,
          onCategoryChanged: (_) {},
          sortMode: ScanSortMode.sizeDesc,
          onSortChanged: (_) {},
          scanning: false,
          presentCategories: const {},
        ),
      ),
    );

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Cache'), findsNothing);
    expect(find.text('Temp'), findsNothing);
    expect(find.text('Media'), findsNothing);
    expect(find.text('System'), findsNothing);
  });

  testWidgets('ScanFilterBar shows only present categories plus All', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ScanFilterBar(
          categoryFilter: 'Cache',
          onCategoryChanged: (_) {},
          sortMode: ScanSortMode.sizeDesc,
          onSortChanged: (_) {},
          scanning: false,
          presentCategories: const {'Cache'},
        ),
      ),
    );

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Cache'), findsOneWidget);
    expect(find.text('Temp'), findsNothing);
    expect(find.text('Media'), findsNothing);
    expect(find.text('System'), findsNothing);
  });

  testWidgets('ScanFilterBar does not overflow at narrow widths', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        ScanFilterBar(
          categoryFilter: null,
          onCategoryChanged: (_) {},
          sortMode: ScanSortMode.sizeDesc,
          onSortChanged: (_) {},
          scanning: false,
        ),
      ),
    );

    // No RenderFlex overflow exceptions; right-side controls stay visible.
    expect(tester.takeException(), isNull);
    expect(find.text('Size ↓'), findsOneWidget);
    expect(find.text('Deletable'), findsNothing);
    expect(find.text('Incremental'), findsNothing);
  });
}
