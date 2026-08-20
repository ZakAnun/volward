import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/storage_home_summary.dart';
import 'package:volward/storage_overview.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/theme/volward_tokens.dart';
import 'package:volward/widgets/home/largest_items_panel.dart';

void main() {
  const volume = StorageVolumeInfo(
    id: '/',
    name: 'Macintosh HD',
    rootPath: '/',
    totalBytes: 1000,
    availableBytes: 400,
    freshness: StorageDataFreshness.live,
  );
  const home = StorageLocationInfo(
    id: 'home',
    name: 'me',
    path: '/Users/me',
    kind: StorageLocationKind.home,
    volumeId: '/',
  );
  final overview = StorageOverviewData(
    volumes: const [volume],
    locations: const [home],
  );

  Future<void> pumpPanel(
    WidgetTester tester, {
    required StorageHomeSummary summary,
    int maxItems = 5,
    ValueChanged<StorageHomeItem>? onOpenItem,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildVolwardTheme(
          brightness: Brightness.light,
          accent: VolwardTokens.defaultAccent,
        ),
        home: Scaffold(
          body: LargestItemsPanel(
            summary: summary,
            maxItems: maxItems,
            onOpenItem: onOpenItem,
          ),
        ),
      ),
    );
  }

  StorageHomeSummary summaryWithItems({
    List<StorageHomeItem> items = const [],
    bool scanning = false,
    bool hasCompletedScan = true,
    int? scannedBytes,
  }) {
    return StorageHomeSummary(
      overview: overview,
      selectedLocation: home,
      selectedVolume: volume,
      scanning: scanning,
      hasCompletedScan: hasCompletedScan,
      scannedBytes: scannedBytes,
      largestItems: items,
    );
  }

  const bigFile = StorageHomeItem(
    name: 'Xcode.dmg',
    path: '/Users/me/Xcode.dmg',
    sizeBytes: 12000000000,
    isDirectory: false,
    scanned: true,
  );
  const archiveDir = StorageHomeItem(
    name: 'archive',
    path: '/Users/me/archive',
    sizeBytes: 8000000000,
    isDirectory: true,
    scanned: false,
  );

  testWidgets('rows render in the order given', (tester) async {
    await pumpPanel(
      tester,
      summary: summaryWithItems(items: const [bigFile, archiveDir]),
    );

    expect(find.byKey(LargestItemsPanel.panelKey), findsOneWidget);
    expect(find.byKey(LargestItemsPanel.rowKey(bigFile.path)), findsOneWidget);
    expect(
      find.byKey(LargestItemsPanel.rowKey(archiveDir.path)),
      findsOneWidget,
    );
    expect(find.byKey(LargestItemsPanel.emptyKey), findsNothing);

    final first = tester.getRect(
      find.byKey(LargestItemsPanel.rowKey(bigFile.path)),
    );
    final second = tester.getRect(
      find.byKey(LargestItemsPanel.rowKey(archiveDir.path)),
    );
    expect(first.top, lessThan(second.top));
  });

  testWidgets('a partial size is marked approximate', (tester) async {
    await pumpPanel(
      tester,
      summary: summaryWithItems(items: const [archiveDir]),
    );

    expect(find.textContaining('+'), findsOneWidget);
  });

  testWidgets('never scanned shows the empty hint', (tester) async {
    await pumpPanel(tester, summary: summaryWithItems(hasCompletedScan: false));

    expect(find.byKey(LargestItemsPanel.emptyKey), findsOneWidget);
    expect(find.text('Shown after scanning'), findsOneWidget);
  });

  testWidgets('a scanned but empty folder says so', (tester) async {
    await pumpPanel(tester, summary: summaryWithItems());

    expect(find.byKey(LargestItemsPanel.emptyKey), findsOneWidget);
    expect(find.text('This folder is empty'), findsOneWidget);
    expect(find.text('Shown after scanning'), findsNothing);
  });

  testWidgets('scanning shows progress instead of rows', (tester) async {
    await pumpPanel(
      tester,
      summary: summaryWithItems(
        items: const [bigFile],
        scanning: true,
        hasCompletedScan: false,
      ).copyWith(scanProgress: 0.5),
    );

    expect(find.byKey(LargestItemsPanel.progressKey), findsOneWidget);
    expect(find.byKey(LargestItemsPanel.rowKey(bigFile.path)), findsNothing);
  });

  testWidgets('the scanned total appears in the title row', (tester) async {
    await pumpPanel(
      tester,
      summary: summaryWithItems(
        items: const [bigFile],
        scannedBytes: 31200000000,
      ),
    );

    expect(find.textContaining('total'), findsOneWidget);
  });

  testWidgets('the total is omitted when scannedBytes is null', (tester) async {
    await pumpPanel(tester, summary: summaryWithItems(items: const [bigFile]));

    expect(find.textContaining('total'), findsNothing);
  });

  testWidgets('tapping a row reports the item', (tester) async {
    StorageHomeItem? opened;
    await pumpPanel(
      tester,
      summary: summaryWithItems(items: const [bigFile]),
      onOpenItem: (item) => opened = item,
    );

    await tester.tap(find.byKey(LargestItemsPanel.rowKey(bigFile.path)));
    await tester.pump();

    expect(opened?.path, bigFile.path);
  });

  testWidgets('a null onOpenItem leaves rows untappable', (tester) async {
    await pumpPanel(tester, summary: summaryWithItems(items: const [bigFile]));

    await tester.tap(find.byKey(LargestItemsPanel.rowKey(bigFile.path)));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('maxItems caps the rendered rows', (tester) async {
    final many = [
      for (var i = 0; i < 5; i++)
        StorageHomeItem(
          name: 'item$i',
          path: '/Users/me/item$i',
          sizeBytes: 1000 - i,
          isDirectory: false,
          scanned: true,
        ),
    ];

    await pumpPanel(
      tester,
      summary: summaryWithItems(items: many),
      maxItems: 3,
    );
    expect(
      find.byKey(LargestItemsPanel.rowKey('/Users/me/item2')),
      findsOneWidget,
    );
    expect(
      find.byKey(LargestItemsPanel.rowKey('/Users/me/item3')),
      findsNothing,
    );

    await pumpPanel(
      tester,
      summary: summaryWithItems(items: many),
      maxItems: 5,
    );
    expect(
      find.byKey(LargestItemsPanel.rowKey('/Users/me/item4')),
      findsOneWidget,
    );
  });

  testWidgets('all-zero sizes render without dividing by zero', (tester) async {
    await pumpPanel(
      tester,
      summary: summaryWithItems(
        items: const [
          StorageHomeItem(
            name: 'a',
            path: '/Users/me/a',
            sizeBytes: 0,
            isDirectory: false,
            scanned: true,
          ),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(LargestItemsPanel.rowKey('/Users/me/a')), findsOneWidget);
  });
}
