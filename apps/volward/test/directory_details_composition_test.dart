import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/features/browse/widgets/scan_column_view.dart';
import 'package:volward/features/browse/widgets/browse_body.dart';
import 'package:volward/features/browse/widgets/directory_page_scaffold.dart';
import 'package:volward/features/browse/widgets/item_preview.dart';
import 'package:volward/features/browse/widgets/sticky_action_bar.dart';
import 'package:volward/home_page.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/storage_overview.dart';
import 'package:volward/storage_overview_provider.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/theme/volward_theme_settings.dart';
import 'package:volward/updater/app_updater.dart';
import 'package:volward/volward_session.dart';
import 'package:volward/widgets/storage_steward_home.dart';

void main() {
  testWidgets('browse body selects the production results branch', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DirectoryPageScaffold(
          backgroundColor: Colors.white,
          body: BrowseBody(
            restoring: false,
            loadingTarget: false,
            hasResults: true,
            scanSection: Text('scan-section'),
            restoreLoading: Text('restore-loading'),
            emptyBody: Text('empty-body'),
            resultsBody: Text('results-body'),
          ),
        ),
      ),
    );

    expect(find.text('results-body'), findsOneWidget);
    expect(find.text('scan-section'), findsNothing);
    expect(find.text('empty-body'), findsNothing);
  });

  testWidgets('item preview renders focused item metadata and selection', (
    tester,
  ) async {
    final node = ScanTreeNode(
      name: 'cache.bin',
      path: '/root/cache.bin',
      isDirectory: false,
      sizeBytes: 2048,
      entryId: 'entry',
      category: 'Cache',
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildVolwardTheme(brightness: Brightness.light),
        home: Scaffold(
          body: ItemPreview(
            focus: node,
            selected: (_) => true,
            busy: false,
            onToggleSelection: (_) {},
            formatBytes: (bytes) => '${bytes}B',
          ),
        ),
      ),
    );

    expect(find.text('cache.bin'), findsOneWidget);
    expect(find.textContaining('2048B'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });

  testWidgets('sticky action bar preserves leading and action slots', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DirectoryPageScaffold(
          backgroundColor: Colors.white,
          body: StickyActionBar(
            leading: Text('leading'),
            action: Text('action'),
          ),
        ),
      ),
    );

    expect(find.text('leading'), findsOneWidget);
    expect(find.text('action'), findsOneWidget);
  });

  testWidgets('real page keeps operation titles and three-column order', (
    tester,
  ) async {
    final session = _ColumnSession();
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildVolwardTheme(brightness: Brightness.light),
        home: HomePage(
          session: session,
          themeSettings: themeSettings,
          updater: updater,
          storageOverviewProvider: _ColumnOverviewProvider(),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.byType(StorageStewardHome));
    expect(find.text('Largest items'), findsOneWidget);

    await tester.tap(find.byKey(StorageStewardHome.browseKey));
    await _pumpUntilFound(tester, find.byType(ScanColumnView));
    await tester.tap(find.text('Documents'));
    await tester.pump();
    await tester.tap(find.text('Reports'));
    await tester.pump();

    // One browser widget renders root plus one column per selected chain
    // entry — the requested three-column order.
    final browser = tester.widget<ScanColumnView>(find.byType(ScanColumnView));
    expect(browser.selectionChain.map((node) => node.path), [
      '/Documents',
      '/Documents/Reports',
    ]);
    expect(find.text('Notes'), findsOneWidget);
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for the expected widget');
}

/// Session whose snapshot tree nests three directories so the column browser
/// can build a three-column chain without a native engine.
class _ColumnSession extends VolwardSession {
  _ColumnSession() : super.test();

  late final ScanSnapshotState _snapshot = ScanSnapshotState.fromWire({
    'snapshot_id': 'columns',
    'scanned_at_ms': 1,
    'reclaimable_estimate_bytes': 0,
    'stats': const {'files_seen': 1, 'scan_state': 'Done'},
    'entries': const <Map<String, dynamic>>[],
    'tree': {
      'name': '/',
      'path': '/',
      'is_dir': true,
      'size_bytes': 0,
      'entry_id': null,
      'scanned': false,
      'children': [
        {
          'name': 'Documents',
          'path': '/Documents',
          'is_dir': true,
          'size_bytes': 1024,
          'entry_id': null,
          'scanned': false,
          'children': [
            {
              'name': 'Reports',
              'path': '/Documents/Reports',
              'is_dir': true,
              'size_bytes': 512,
              'entry_id': null,
              'scanned': false,
              'children': [
                {
                  'name': 'Notes',
                  'path': '/Documents/Reports/Notes',
                  'is_dir': true,
                  'size_bytes': 256,
                  'entry_id': null,
                  'scanned': false,
                  'children': const <Map<String, dynamic>>[],
                },
              ],
            },
          ],
        },
      ],
    },
  });

  @override
  ScanSnapshotState? get lastSnapshot => _snapshot;

  @override
  bool get hasAuthoritativeSnapshotForCurrentRoot => true;

  @override
  Future<void> loadSessionStateIfNeeded() async {}

  @override
  Future<String> resolveStartupRoot() async => '/';

  @override
  Future<void> previewTarget({int? expectedGeneration}) async {}

  @override
  Future<void> restoreCachedSnapshotIfNeeded() async {}
}

class _ColumnOverviewProvider implements StorageOverviewProvider {
  @override
  Future<StorageOverviewData> load({String? selectedPath}) async {
    return StorageOverviewData(
      selectedVolumeId: '/',
      volumes: [
        const StorageVolumeInfo(
          id: '/',
          name: 'Disk',
          rootPath: '/',
          totalBytes: 1000,
          availableBytes: 400,
          freshness: StorageDataFreshness.live,
        ),
      ],
      locations: const [
        StorageLocationInfo(
          id: 'home',
          name: 'home',
          path: '/',
          kind: StorageLocationKind.home,
          volumeId: '/',
        ),
      ],
    );
  }
}
