import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/storage_home_summary.dart';
import 'package:volward/storage_overview.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/theme/volward_tokens.dart';
import 'package:volward/widgets/home/largest_items_panel.dart';
import 'package:volward/widgets/storage_steward_home.dart';
import 'package:volward/widgets/volward_logo.dart';

const downloads = StorageLocationInfo(
  id: 'downloads',
  name: 'Downloads',
  path: '/Users/me/Downloads',
  kind: StorageLocationKind.downloads,
  volumeId: '/',
);

const applications = StorageLocationInfo(
  id: 'applications',
  name: 'Applications',
  path: '/Applications',
  kind: StorageLocationKind.applications,
  volumeId: '/',
);

const desktop = StorageLocationInfo(
  id: 'desktop',
  name: 'Desktop',
  path: '/Users/me/Desktop',
  kind: StorageLocationKind.desktop,
  volumeId: '/',
);

const documents = StorageLocationInfo(
  id: 'documents',
  name: 'Documents',
  path: '/Users/me/Documents',
  kind: StorageLocationKind.documents,
  volumeId: '/',
);

const home = StorageLocationInfo(
  id: 'home',
  name: 'me',
  path: '/Users/me',
  kind: StorageLocationKind.home,
  volumeId: '/',
);

const volume = StorageVolumeInfo(
  id: '/',
  name: 'Macintosh HD',
  rootPath: '/',
  totalBytes: 1000,
  availableBytes: 400,
  freshness: StorageDataFreshness.live,
);

final readySummary = StorageHomeSummary(
  overview: StorageOverviewData(
    selectedVolumeId: '/',
    volumes: const [volume],
    locations: const [home, applications, desktop, downloads, documents],
  ),
  selectedLocation: home,
  selectedVolume: volume,
  scanning: false,
  hasCompletedScan: false,
);

final scanningSummary = StorageHomeSummary(
  overview: readySummary.overview,
  selectedLocation: readySummary.selectedLocation,
  selectedVolume: readySummary.selectedVolume,
  scanning: true,
  hasCompletedScan: false,
  scanProgress: 0.4,
);

final completedSummary = StorageHomeSummary(
  overview: readySummary.overview,
  selectedLocation: readySummary.selectedLocation,
  selectedVolume: readySummary.selectedVolume,
  scanning: false,
  hasCompletedScan: true,
  reclaimableBytes: 256,
  lastScannedAtMs: 1723766400000,
);

final categorizedSummary = StorageHomeSummary(
  overview: readySummary.overview,
  selectedLocation: readySummary.selectedLocation,
  selectedVolume: readySummary.selectedVolume,
  scanning: false,
  hasCompletedScan: true,
  categories: const [StorageHomeCategorySummary(name: 'Cache', count: 4)],
);

const loadingSummary = StorageHomeSummary(
  overview: StorageOverviewData.loading(),
  selectedLocation: home,
  selectedVolume: null,
  scanning: false,
  hasCompletedScan: false,
);

const unavailableSummary = StorageHomeSummary(
  overview: StorageOverviewData.unavailable('unavailable'),
  selectedLocation: home,
  selectedVolume: null,
  scanning: false,
  hasCompletedScan: false,
);

const neutralUnavailableSummary = StorageHomeSummary(
  overview: StorageOverviewData.unavailable('missing-root'),
  selectedLocation: null,
  selectedVolume: null,
  scanning: false,
  hasCompletedScan: false,
);

const customPath = '/Users/me/Projects/Deep Archive/2026/client-materials';

const customLocation = StorageLocationInfo(
  id: 'custom-deep-archive',
  name: 'Deep Archive',
  path: customPath,
  kind: StorageLocationKind.custom,
  volumeId: '/',
);

const secondCustomPath = '/Users/me/Projects/Photo Library';

const secondCustomLocation = StorageLocationInfo(
  id: 'custom-photo-library',
  name: 'Photo Library',
  path: secondCustomPath,
  kind: StorageLocationKind.custom,
  volumeId: '/',
);

final customSummary = StorageHomeSummary(
  overview: StorageOverviewData(
    selectedVolumeId: '/',
    volumes: const [volume],
    locations: const [home, applications, desktop, downloads, documents],
  ),
  selectedLocation: customLocation,
  selectedVolume: volume,
  scanning: false,
  hasCompletedScan: false,
);

const longPosixPath =
    '/Users/me/Projects/International Archive/2026/Client Deliverables/'
    'Extremely Long Nested Folder for Responsive Layout Coverage';

const longPosixLocation = StorageLocationInfo(
  id: 'custom-long-posix',
  name: 'Extremely Long POSIX Custom Folder for Responsive Layout Coverage',
  path: longPosixPath,
  kind: StorageLocationKind.custom,
  volumeId: '/',
);

final longPosixSummary = StorageHomeSummary(
  overview: StorageOverviewData(
    selectedVolumeId: '/',
    volumes: const [volume],
    locations: const [home, applications, desktop, downloads, documents],
  ),
  selectedLocation: longPosixLocation,
  selectedVolume: volume,
  scanning: false,
  hasCompletedScan: false,
);

const windowsVolume = StorageVolumeInfo(
  id: 'D:',
  name: 'Data',
  rootPath: 'D:/',
  totalBytes: 2048,
  availableBytes: 1024,
  freshness: StorageDataFreshness.live,
);

const windowsSystemVolume = StorageVolumeInfo(
  id: 'C:',
  name: 'Windows',
  rootPath: 'C:/',
  totalBytes: 4096,
  availableBytes: 1024,
  freshness: StorageDataFreshness.live,
);

const windowsHome = StorageLocationInfo(
  id: 'home',
  name: 'me',
  path: r'C:\Users\me',
  kind: StorageLocationKind.home,
  volumeId: 'C:',
);

const windowsDownloads = StorageLocationInfo(
  id: 'downloads',
  name: 'Downloads',
  path: r'C:\Users\me\Downloads',
  kind: StorageLocationKind.downloads,
  volumeId: 'C:',
);

const windowsDesktop = StorageLocationInfo(
  id: 'desktop',
  name: 'Desktop',
  path: r'C:\Users\me\Desktop',
  kind: StorageLocationKind.desktop,
  volumeId: 'C:',
);

const windowsDocuments = StorageLocationInfo(
  id: 'documents',
  name: 'Documents',
  path: r'C:\Users\me\Documents',
  kind: StorageLocationKind.documents,
  volumeId: 'C:',
);

final windowsUserFolderSummary = StorageHomeSummary(
  overview: StorageOverviewData(
    selectedVolumeId: 'C:',
    volumes: const [windowsSystemVolume, windowsVolume],
    locations: const [
      windowsHome,
      windowsDesktop,
      windowsDownloads,
      windowsDocuments,
    ],
  ),
  selectedLocation: windowsHome,
  selectedVolume: windowsSystemVolume,
  scanning: false,
  hasCompletedScan: false,
);

const windowsDrive = StorageLocationInfo(
  id: 'drive-d',
  name: 'Data',
  path: 'D:\\',
  kind: StorageLocationKind.volume,
  volumeId: 'D:',
);

const windowsSystemDrive = StorageLocationInfo(
  id: 'drive-c',
  name: 'Windows',
  path: 'C:\\',
  kind: StorageLocationKind.volume,
  volumeId: 'C:',
);

const equivalentWindowsSelection = StorageLocationInfo(
  id: 'selected-drive-d',
  name: 'Selected Data',
  path: 'd:/',
  kind: StorageLocationKind.custom,
  volumeId: 'D:',
);

final windowsSummary = StorageHomeSummary(
  overview: StorageOverviewData(
    selectedVolumeId: 'D:',
    volumes: const [windowsVolume],
    locations: const [windowsDrive],
  ),
  selectedLocation: equivalentWindowsSelection,
  selectedVolume: windowsVolume,
  scanning: false,
  hasCompletedScan: false,
);

final windowsMultiDriveSummary = StorageHomeSummary(
  overview: StorageOverviewData(
    selectedVolumeId: 'D:',
    volumes: const [windowsSystemVolume, windowsVolume],
    locations: const [
      windowsHome,
      windowsDesktop,
      windowsDownloads,
      windowsDocuments,
      windowsSystemDrive,
      windowsDrive,
    ],
  ),
  selectedLocation: windowsDrive,
  selectedVolume: windowsVolume,
  scanning: false,
  hasCompletedScan: false,
);

final windowsMultiDriveScanningSummary = StorageHomeSummary(
  overview: windowsMultiDriveSummary.overview,
  selectedLocation: windowsMultiDriveSummary.selectedLocation,
  selectedVolume: windowsMultiDriveSummary.selectedVolume,
  scanning: true,
  hasCompletedScan: false,
  scanProgress: 0.4,
);

const longWindowsVolume = StorageVolumeInfo(
  id: 'Z:',
  name: 'Long Windows Volume Name for Layout Stress Coverage',
  rootPath: 'Z:/',
  totalBytes: 8192,
  availableBytes: 2048,
  freshness: StorageDataFreshness.live,
);

const longWindowsDrive = StorageLocationInfo(
  id: 'drive-z-long',
  name: 'Long Windows Volume Name for Layout Stress Coverage',
  path: 'Z:\\',
  kind: StorageLocationKind.volume,
  volumeId: 'Z:',
);

final longWindowsLocations = <StorageLocationInfo>[
  longWindowsDrive,
  for (var index = 0; index < 10; index++)
    StorageLocationInfo(
      id: 'long-location-$index',
      name: 'Extended Windows Folder Name ${index + 1}',
      path: 'Z:\\Extended Windows Folder ${index + 1}',
      kind: StorageLocationKind.custom,
      volumeId: 'Z:',
    ),
];

final longWindowsSummary = StorageHomeSummary(
  overview: StorageOverviewData(
    selectedVolumeId: 'Z:',
    volumes: const [longWindowsVolume],
    locations: longWindowsLocations,
  ),
  selectedLocation: longWindowsDrive,
  selectedVolume: longWindowsVolume,
  scanning: false,
  hasCompletedScan: false,
);

const posixBackslashLocation = StorageLocationInfo(
  id: 'posix-backslash',
  name: r'a\b',
  path: r'/tmp/a\b',
  kind: StorageLocationKind.custom,
  volumeId: '/',
);

const posixSlashLocation = StorageLocationInfo(
  id: 'posix-slash',
  name: 'b',
  path: '/tmp/a/b',
  kind: StorageLocationKind.custom,
  volumeId: '/',
);

final posixDistinctSummary = StorageHomeSummary(
  overview: StorageOverviewData(
    selectedVolumeId: '/',
    volumes: const [volume],
    locations: const [posixBackslashLocation],
  ),
  selectedLocation: posixSlashLocation,
  selectedVolume: volume,
  scanning: false,
  hasCompletedScan: false,
);

const cachedVolume = StorageVolumeInfo(
  id: 'cached:/Users/me',
  name: 'Cached Home',
  rootPath: '/Users/me',
  totalBytes: 1024,
  availableBytes: 256,
  freshness: StorageDataFreshness.cached,
);

final cachedSummary = StorageHomeSummary(
  overview: StorageOverviewData(
    selectedVolumeId: cachedVolume.id,
    volumes: const [cachedVolume],
    locations: const [home],
  ),
  selectedLocation: home,
  selectedVolume: cachedVolume,
  scanning: false,
  hasCompletedScan: true,
);

const cachedWhileLoadingSummary = StorageHomeSummary(
  overview: StorageOverviewData.loading(),
  selectedLocation: home,
  selectedVolume: cachedVolume,
  scanning: false,
  hasCompletedScan: false,
);

const invalidLiveVolume = StorageVolumeInfo(
  id: '/',
  name: 'Invalid disk',
  rootPath: '/',
  totalBytes: 100,
  availableBytes: 140,
  freshness: StorageDataFreshness.live,
);

final invalidLiveSummary = StorageHomeSummary(
  overview: StorageOverviewData(
    selectedVolumeId: '/',
    volumes: const [invalidLiveVolume],
    locations: const [home],
  ),
  selectedLocation: home,
  selectedVolume: invalidLiveVolume,
  scanning: false,
  hasCompletedScan: false,
);

Finder targetTiles() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return widget is InkWell &&
      key is ValueKey<String> &&
      key.value.startsWith('storage-target-');
});

Finder capacityMeterFill() => find.descendant(
  of: find.byKey(StorageStewardHome.capacityMeterKey),
  matching: find.byType(FractionallySizedBox),
);

({Rect targets, Rect capacity, Rect scan}) homeGeometry(WidgetTester tester) {
  return (
    targets: tester.getRect(find.byKey(StorageStewardHome.targetsKey)),
    capacity: tester.getRect(find.byKey(StorageStewardHome.capacityKey)),
    scan: tester.getRect(find.byKey(StorageStewardHome.browseCardKey)),
  );
}

void expectButtonSemantics(SemanticsNode node, {required bool enabled}) {
  final data = node.getSemanticsData();
  expect(data.flagsCollection.isButton, isTrue);
  expect(
    data.flagsCollection.isEnabled,
    enabled ? Tristate.isTrue : Tristate.isFalse,
  );
  expect(data.hasAction(SemanticsAction.tap), enabled);
}

double contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void expectTextContrast(WidgetTester tester, Finder finder, Color background) {
  final text = tester.widget<Text>(finder);
  final renderedForeground = Color.alphaBlend(text.style!.color!, background);
  expect(
    contrastRatio(renderedForeground, background),
    greaterThanOrEqualTo(4.5),
  );
}

Finder statusChipFinder() => find.byKey(StorageStewardHome.statusChipKey);

BoxDecoration statusChipDecoration(WidgetTester tester) {
  final finder = statusChipFinder();
  expect(finder, findsOneWidget);
  final decoratedBox = find.descendant(
    of: finder,
    matching: find.byType(DecoratedBox),
  );
  return tester.widget<DecoratedBox>(decoratedBox).decoration as BoxDecoration;
}

Color scanSummarySurfaceColor(WidgetTester tester) {
  final scanSummary = find.byKey(StorageStewardHome.browseCardKey);
  final surface = tester.widget<DecoratedBox>(
    find.descendant(of: scanSummary, matching: find.byType(DecoratedBox)).first,
  );
  return (surface.decoration as BoxDecoration).color!;
}

void expectStatusChipContrast(WidgetTester tester, String label) {
  final decoration = statusChipDecoration(tester);
  final background = Color.alphaBlend(
    decoration.color!,
    scanSummarySurfaceColor(tester),
  );
  expectTextContrast(tester, find.text(label), background);
}

bool primaryFocusIsWithin(WidgetTester tester, Key key) {
  final focusedContext = FocusManager.instance.primaryFocus?.context;
  if (focusedContext == null) return false;
  final target = tester.element(find.byKey(key));
  if (identical(focusedContext, target)) return true;
  var found = false;
  (focusedContext as Element).visitAncestorElements((ancestor) {
    found = identical(ancestor, target);
    return !found;
  });
  return found;
}

Future<void> expectTabSequence(WidgetTester tester, List<Key> keys) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  for (final key in keys) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      primaryFocusIsWithin(tester, key),
      isTrue,
      reason: 'expected primary focus inside $key',
    );
  }
}

Future<void> pumpOverview(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  StorageHomeSummary? summary,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
  Color accent = VolwardTokens.defaultAccent,
  VoidCallback? onBrowse,
  VoidCallback? onChooseFolder,
  ValueChanged<StorageLocationInfo>? onSelectTarget,
  VoidCallback? onScan,
  VoidCallback? onCancelScan,
  VoidCallback? onOpenSettings,
  ValueChanged<String>? onSelectCategory,
  ValueChanged<StorageHomeItem>? onOpenItem,
  VoidCallback? onOpenAi,
  Widget? mainPaneOverride,
  bool interactionsLocked = false,
  FocusNode? aiActionFocusNode,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildVolwardTheme(brightness: brightness, accent: accent),
      home: Scaffold(
        body: StorageStewardHome(
          summary: summary ?? readySummary,
          onBrowse: onBrowse ?? () {},
          onChooseFolder: onChooseFolder ?? () {},
          onSelectTarget: onSelectTarget ?? (_) {},
          onScan: onScan,
          onCancelScan: onCancelScan,
          onOpenSettings: onOpenSettings,
          onSelectCategory: onSelectCategory,
          onOpenItem: onOpenItem,
          onOpenAi: onOpenAi,
          mainPaneOverride: mainPaneOverride,
          interactionsLocked: interactionsLocked,
          aiActionFocusNode: aiActionFocusNode,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('default overview keeps all original regions unchanged', (
    tester,
  ) async {
    await pumpOverview(tester, summary: completedSummary);

    expect(find.byKey(StorageStewardHome.capacityKey), findsOneWidget);
    expect(find.byKey(LargestItemsPanel.panelKey), findsOneWidget);
    expect(find.byKey(StorageStewardHome.browseCardKey), findsOneWidget);
    expect(find.byKey(StorageStewardHome.aiActionKey), findsNothing);
  });

  testWidgets('wide overview exposes the AI action without overflow', (
    tester,
  ) async {
    await pumpOverview(tester, onOpenAi: () {});

    expect(find.byKey(StorageStewardHome.aiActionKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(StorageStewardHome.aiActionKey)).width,
      lessThanOrEqualTo(140),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact overview exposes the AI action without overflow', (
    tester,
  ) async {
    await pumpOverview(tester, size: const Size(600, 1400), onOpenAi: () {});

    expect(find.byKey(StorageStewardHome.aiActionKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(StorageStewardHome.aiActionKey)).width,
      lessThanOrEqualTo(140),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('main pane override replaces the default overview pane', (
    tester,
  ) async {
    const replacement = Key('test-main-pane-replacement');
    await pumpOverview(
      tester,
      mainPaneOverride: const SizedBox(key: replacement),
    );

    expect(find.byKey(replacement), findsOneWidget);
    expect(find.byKey(StorageStewardHome.targetsKey), findsOneWidget);
    expect(find.byKey(StorageStewardHome.capacityKey), findsNothing);
  });

  testWidgets('locked interactions absorb target folder and AI taps', (
    tester,
  ) async {
    var targetSelections = 0;
    var folderSelections = 0;
    var aiOpens = 0;
    var browseOpens = 0;
    var scanStarts = 0;
    await pumpOverview(
      tester,
      onSelectTarget: (_) => targetSelections++,
      onChooseFolder: () => folderSelections++,
      onOpenAi: () => aiOpens++,
      onBrowse: () => browseOpens++,
      onScan: () => scanStarts++,
      interactionsLocked: true,
    );

    await tester.tap(find.byKey(const ValueKey('storage-target-home')));
    await tester.tap(find.byKey(StorageStewardHome.chooseFolderKey));
    await tester.tap(find.byKey(StorageStewardHome.aiActionKey));
    await tester.tap(find.byKey(StorageStewardHome.browseKey));
    await tester.tap(find.byKey(StorageStewardHome.scanActionKey));

    expect(targetSelections, 0);
    expect(folderSelections, 0);
    expect(aiOpens, 0);
    expect(browseOpens, 0);
    expect(scanStarts, 0);
  });

  testWidgets('locked semantics hide mutable controls but keep Settings', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpOverview(
        tester,
        interactionsLocked: true,
        onOpenAi: () {},
        onOpenSettings: () {},
      );

      expectButtonSemantics(
        tester.getSemantics(
          find.byKey(const ValueKey('storage-target-semantics-downloads')),
        ),
        enabled: false,
      );
      expectButtonSemantics(
        tester.getSemantics(find.bySemanticsLabel('Choose Folder')),
        enabled: false,
      );
      expectButtonSemantics(
        tester.getSemantics(find.bySemanticsLabel('AI Analysis')),
        enabled: false,
      );
      expectButtonSemantics(
        tester.getSemantics(find.bySemanticsLabel('Browse Files')),
        enabled: false,
      );
      expectButtonSemantics(
        tester.getSemantics(find.bySemanticsLabel('Start Scan')),
        enabled: false,
      );
      expectButtonSemantics(
        tester.getSemantics(find.byKey(StorageStewardHome.settingsKey)),
        enabled: true,
      );
      // Hover tooltip is disabled app-wide, but the icon-only settings
      // button must keep its accessible name (semantics-only Tooltip).
      expect(find.byTooltip('Settings'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('wide dashboard board is full width and top aligned', (
    tester,
  ) async {
    for (final size in [const Size(1280, 800), const Size(1600, 1000)]) {
      await pumpOverview(tester, size: size);

      final viewport = tester.getRect(
        find.byKey(StorageStewardHome.contentViewportKey),
      );
      final board = tester.getRect(find.byKey(StorageStewardHome.boardKey));
      final targets = tester.getRect(find.byKey(StorageStewardHome.targetsKey));
      final capacity = tester.getRect(
        find.byKey(StorageStewardHome.capacityKey),
      );

      expect(board.left, closeTo(viewport.left, 1));
      expect(board.width, closeTo(viewport.width, 1));
      expect(board.top, closeTo(viewport.top, 1));
      expect(board.height, greaterThanOrEqualTo(viewport.height));
      expect(targets.top, closeTo(viewport.top, 1));
      expect(capacity.top, closeTo(viewport.top, 1));
    }
  });

  testWidgets('default window shows full dashboard without overflow', (
    tester,
  ) async {
    await pumpOverview(
      tester,
      size: const Size(1000, 720),
      summary: completedSummary,
    );

    final viewport = tester.getRect(
      find.byKey(StorageStewardHome.contentViewportKey),
    );
    final board = tester.getRect(find.byKey(StorageStewardHome.boardKey));

    expect(board.height, closeTo(viewport.height, 1));
  });

  testWidgets('capacity meter sits at the bottom of the disk card', (
    tester,
  ) async {
    await pumpOverview(tester);

    expect(
      find.descendant(
        of: find.byKey(StorageStewardHome.capacityKey),
        matching: find.byKey(StorageStewardHome.capacityMeterKey),
      ),
      findsOneWidget,
    );
    final capacity = tester.getRect(find.byKey(StorageStewardHome.capacityKey));
    final meter = tester.getRect(
      find.byKey(StorageStewardHome.capacityMeterKey),
    );
    final largest = tester.getRect(find.byKey(LargestItemsPanel.panelKey));
    // Pinned, not merely "somewhere near the bottom": the panel is taller than
    // its content in wide mode, so a loose tolerance here hid up to 137px of
    // dead space below the meter at 1920x1080.
    expect(meter.bottom, closeTo(capacity.bottom, 1));
    expect(meter.left, closeTo(capacity.left, 1));
    expect(meter.right, closeTo(capacity.right, 1));
    expect(meter.height, closeTo(12, 1));
    expect(largest.top - capacity.bottom, closeTo(14, 1));
  });

  testWidgets('category pie sits in the last scan card', (tester) async {
    await pumpOverview(tester, summary: categorizedSummary);

    expect(
      find.descendant(
        of: find.byKey(StorageStewardHome.browseCardKey),
        matching: find.byKey(StorageStewardHome.categoryPieKey),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(StorageStewardHome.capacityKey),
        matching: find.byKey(StorageStewardHome.categoryPieKey),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(StorageStewardHome.browseCardKey),
        matching: find.byKey(const ValueKey('storage-category-Cache')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(StorageStewardHome.capacityKey),
        matching: find.byKey(const ValueKey('storage-category-Cache')),
      ),
      findsNothing,
    );
    final scan = tester.getRect(find.byKey(StorageStewardHome.browseCardKey));
    final pie = tester.getRect(find.byKey(StorageStewardHome.categoryPieKey));
    expect(pie.top, greaterThan(scan.top));
    expect(pie.bottom, lessThanOrEqualTo(scan.bottom));
  });

  testWidgets('category pie omits unscanned labels and shows other remainder', (
    tester,
  ) async {
    await pumpOverview(tester, summary: categorizedSummary);

    expect(
      find.byKey(const ValueKey('storage-category-Cache')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('storage-category-Temp')), findsNothing);
    expect(find.byKey(const ValueKey('storage-category-Media')), findsNothing);
    expect(find.byKey(const ValueKey('storage-category-System')), findsNothing);
    expect(find.byKey(const ValueKey('storage-category-Other')), findsNothing);
    expect(find.text('100%'), findsOneWidget);

    await pumpOverview(
      tester,
      summary: StorageHomeSummary(
        overview: categorizedSummary.overview,
        selectedLocation: categorizedSummary.selectedLocation,
        selectedVolume: categorizedSummary.selectedVolume,
        scanning: false,
        hasCompletedScan: true,
        categories: const [
          StorageHomeCategorySummary(name: 'Cache', count: 4),
          StorageHomeCategorySummary(name: 'Other', count: 9),
        ],
      ),
    );

    expect(
      find.byKey(const ValueKey('storage-category-Cache')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('storage-category-Other')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('storage-category-System')), findsNothing);
    expect(find.text('31%'), findsOneWidget);
    expect(find.text('69%'), findsOneWidget);

    await pumpOverview(
      tester,
      summary: StorageHomeSummary(
        overview: categorizedSummary.overview,
        selectedLocation: categorizedSummary.selectedLocation,
        selectedVolume: categorizedSummary.selectedVolume,
        scanning: false,
        hasCompletedScan: true,
        categories: const [
          StorageHomeCategorySummary(name: 'Cache', count: 1141),
          StorageHomeCategorySummary(name: 'Other', count: 316859),
        ],
      ),
    );

    expect(find.text('0%'), findsNothing);
    expect(find.text('0.4%'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('valid capacity meter fill matches used fraction', (
    tester,
  ) async {
    await pumpOverview(tester);

    expect(capacityMeterFill(), findsOneWidget);
    expect(
      tester.widget<FractionallySizedBox>(capacityMeterFill()).widthFactor,
      closeTo(0.6, 0.001),
    );
    final fillDecoration = tester.widget<DecoratedBox>(
      find.descendant(
        of: capacityMeterFill(),
        matching: find.byType(DecoratedBox),
      ),
    );
    final tokens = Theme.of(
      tester.element(find.byKey(StorageStewardHome.capacityMeterKey)),
    ).extension<VolwardTokens>()!;
    final gradient =
        (fillDecoration.decoration as BoxDecoration).gradient!
            as LinearGradient;
    expect(gradient.colors, [
      Color.lerp(tokens.primary, Colors.white, 0.46),
      Color.lerp(tokens.primary, Colors.black, 0.06),
    ]);
  });

  testWidgets('status, browse, and scan controls use one height and font', (
    tester,
  ) async {
    await pumpOverview(tester, onScan: () {});

    final statusHeight = tester.getSize(statusChipFinder()).height;
    final browseHeight = tester
        .getSize(find.byKey(StorageStewardHome.browseKey))
        .height;
    final scanHeight = tester
        .getSize(find.byKey(StorageStewardHome.scanActionKey))
        .height;

    expect(statusHeight, closeTo(32, 1));
    expect(browseHeight, closeTo(statusHeight, 1));
    expect(scanHeight, closeTo(statusHeight, 1));

    final statusFont = tester
        .widget<Text>(find.text('Live disk data'))
        .style!
        .fontSize;
    final browseFont = tester
        .widget<Text>(find.text('Browse Files'))
        .style!
        .fontSize;
    final scanFont = tester
        .widget<Text>(find.text('Start Scan'))
        .style!
        .fontSize;
    expect(browseFont, statusFont);
    expect(scanFont, statusFont);
  });

  testWidgets('tab traversal follows dashboard order without volume selector', (
    tester,
  ) async {
    await pumpOverview(tester, onScan: () {}, onOpenSettings: () {});

    await expectTabSequence(tester, [
      const ValueKey('storage-target-home'),
      const ValueKey('storage-target-applications'),
      const ValueKey('storage-target-desktop'),
      const ValueKey('storage-target-downloads'),
      const ValueKey('storage-target-documents'),
      StorageStewardHome.chooseFolderKey,
      StorageStewardHome.browseKey,
      StorageStewardHome.scanActionKey,
      StorageStewardHome.settingsKey,
    ]);
  });

  testWidgets('tab traversal starts with Windows volume selector', (
    tester,
  ) async {
    await pumpOverview(
      tester,
      summary: windowsMultiDriveSummary,
      onScan: () {},
      onOpenSettings: () {},
    );

    await expectTabSequence(tester, [
      StorageStewardHome.volumeSelectorKey,
      const ValueKey('storage-target-home'),
      const ValueKey('storage-target-desktop'),
      const ValueKey('storage-target-downloads'),
      const ValueKey('storage-target-documents'),
      StorageStewardHome.chooseFolderKey,
      StorageStewardHome.browseKey,
      StorageStewardHome.scanActionKey,
      StorageStewardHome.settingsKey,
    ]);
  });

  testWidgets('tab traversal skips disabled scanning controls', (tester) async {
    await pumpOverview(
      tester,
      summary: windowsMultiDriveScanningSummary,
      onCancelScan: () {},
      onOpenSettings: () {},
    );

    await expectTabSequence(tester, [
      StorageStewardHome.browseKey,
      StorageStewardHome.scanActionKey,
      StorageStewardHome.settingsKey,
    ]);
  });

  testWidgets('wide layout keeps a two-column dashboard board', (tester) async {
    await pumpOverview(tester, size: const Size(1280, 800));

    expect(find.byKey(StorageStewardHome.panelKey), findsOneWidget);
    expect(find.byKey(StorageStewardHome.capacityKey), findsOneWidget);
    expect(find.byKey(StorageStewardHome.targetsKey), findsOneWidget);
    expect(find.byKey(StorageStewardHome.browseCardKey), findsOneWidget);
    expect(find.byKey(StorageStewardHome.actionsKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(StorageStewardHome.targetsKey)).width,
      216,
    );
    expect(find.text('Desktop storage steward'), findsNothing);
    expect(find.text('See what is taking space.'), findsNothing);
    expect(find.text('Preview first'), findsNothing);
    expect(find.text('Browse like Finder'), findsNothing);
    expect(find.text('Progressive scan'), findsNothing);

    final panel = tester.getRect(find.byKey(StorageStewardHome.panelKey));
    final capacity = tester.getRect(find.byKey(StorageStewardHome.capacityKey));
    final targets = tester.getRect(find.byKey(StorageStewardHome.targetsKey));
    final largest = tester.getRect(find.byKey(LargestItemsPanel.panelKey));
    final scanSummary = tester.getRect(
      find.byKey(StorageStewardHome.browseCardKey),
    );
    final actions = tester.getRect(find.byKey(StorageStewardHome.actionsKey));

    expect(targets.right, lessThan(capacity.left));
    expect(capacity.width, greaterThan(targets.width));
    expect(largest.top - capacity.bottom, closeTo(14, 1));
    expect(scanSummary.top - largest.bottom, closeTo(14, 1));
    expect(actions.top, greaterThanOrEqualTo(scanSummary.top));
    expect(actions.left, greaterThan(scanSummary.left));
    expect(panel.width, greaterThan(1000));
  });

  testWidgets('wide workspace fills the main pane bounds', (tester) async {
    const workspace = Key('test-workspace-bounds');
    await pumpOverview(
      tester,
      size: const Size(1280, 800),
      mainPaneOverride: const SizedBox(key: workspace),
    );

    expect(
      tester.getRect(find.byKey(workspace)),
      tester.getRect(find.byKey(StorageStewardHome.mainPaneKey)),
    );
  });

  testWidgets('wide dashboard renders topbar and sidebar logos', (
    tester,
  ) async {
    await pumpOverview(tester, size: const Size(1280, 800));

    final logos = tester
        .widgetList<VolwardLogoMark>(find.byType(VolwardLogoMark))
        .toList();
    expect(logos, hasLength(2));
    expect(logos[0].size, 22);
    expect(logos[1].size, 72);
    expect(
      tester.getSize(find.byKey(StorageStewardHome.targetsKey)).width,
      closeTo(216, 1),
    );
  });

  testWidgets('Layout C surfaces keep their previous corner hierarchy', (
    tester,
  ) async {
    await pumpOverview(tester, summary: categorizedSummary, onScan: () {});

    final targetDecorations = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(StorageStewardHome.targetsKey),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .toList();
    expect(targetDecorations, hasLength(2));
    expect(targetDecorations[0].borderRadius, BorderRadius.circular(24));
    expect(targetDecorations[1].borderRadius, BorderRadius.circular(20));

    final capacitySurface = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(StorageStewardHome.capacityKey),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      (capacitySurface.decoration as BoxDecoration).borderRadius,
      BorderRadius.circular(24),
    );

    final scanSurface = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(StorageStewardHome.browseCardKey),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      (scanSurface.decoration as BoxDecoration).borderRadius,
      BorderRadius.circular(24),
    );

    expect(
      find.descendant(
        of: find.byKey(StorageStewardHome.browseCardKey),
        matching: find.byKey(const ValueKey('storage-category-Cache')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(StorageStewardHome.capacityKey),
        matching: find.byKey(const ValueKey('storage-category-Cache')),
      ),
      findsNothing,
    );
  });

  testWidgets('exact 720 uses rail and 719 stacks targets vertically', (
    tester,
  ) async {
    await pumpOverview(tester, size: const Size(720, 700));
    // Accept small overflow due to flex rounding at this viewport size
    expect(tester.takeException(), isNull);

    var targets = tester.getRect(find.byKey(StorageStewardHome.targetsKey));
    var capacity = tester.getRect(find.byKey(StorageStewardHome.capacityKey));
    expect(targets.right, lessThan(capacity.left));

    await pumpOverview(tester, size: const Size(719, 700));
    expect(tester.takeException(), isNull);

    targets = tester.getRect(find.byKey(StorageStewardHome.targetsKey));
    capacity = tester.getRect(find.byKey(StorageStewardHome.capacityKey));
    expect(targets.bottom, lessThanOrEqualTo(capacity.top));
    expect(
      tester.getCenter(find.byKey(const ValueKey('storage-target-home'))).dy,
      lessThan(
        tester
            .getCenter(
              find.byKey(const ValueKey('storage-target-applications')),
            )
            .dy,
      ),
      reason: 'Layout C keeps compact target tiles in one vertical list',
    );
  });

  testWidgets('platform data uses identical responsive geometry', (
    tester,
  ) async {
    for (final (summary, firstTargetKey, secondTargetKey) in [
      (
        readySummary,
        const ValueKey('storage-target-home'),
        const ValueKey('storage-target-applications'),
      ),
      (
        windowsMultiDriveSummary,
        const ValueKey('storage-target-home'),
        const ValueKey('storage-target-downloads'),
      ),
    ]) {
      for (final size in const [Size(1280, 800), Size(780, 700)]) {
        await pumpOverview(tester, size: size, summary: summary);
        // Accept small overflow due to flex rounding at 780x700
        expect(tester.takeException(), isNull);

        final geometry = homeGeometry(tester);
        expect(geometry.targets.right, lessThan(geometry.capacity.left));
        expect(geometry.scan.top, greaterThan(geometry.capacity.bottom));
      }

      await pumpOverview(tester, size: const Size(700, 700), summary: summary);
      expect(tester.takeException(), isNull);

      final geometry = homeGeometry(tester);
      expect(geometry.targets.bottom, lessThanOrEqualTo(geometry.capacity.top));
      expect(geometry.scan.top, greaterThan(geometry.capacity.bottom));
      expect(
        tester.getCenter(find.byKey(firstTargetKey)).dy,
        lessThan(tester.getCenter(find.byKey(secondTargetKey)).dy),
        reason: 'compact platform targets stay vertically stacked',
      );
    }
  });

  testWidgets('narrow layout vertically stacks dashboard regions', (
    tester,
  ) async {
    await pumpOverview(tester, size: const Size(620, 600));

    final capacity = tester.getRect(find.byKey(StorageStewardHome.capacityKey));
    final targets = tester.getRect(find.byKey(StorageStewardHome.targetsKey));
    final scanSummary = tester.getRect(
      find.byKey(StorageStewardHome.browseCardKey),
    );
    final actions = tester.getRect(find.byKey(StorageStewardHome.actionsKey));

    expect(capacity.top, greaterThanOrEqualTo(targets.bottom));
    expect(scanSummary.top, greaterThanOrEqualTo(capacity.bottom));
    expect(actions.top, greaterThanOrEqualTo(scanSummary.top));
    expect((capacity.left - targets.left).abs(), lessThan(8));
    expect((targets.left - scanSummary.left).abs(), lessThan(8));
  });

  testWidgets('narrow layout scroll keeps browse and scan independent', (
    tester,
  ) async {
    var browses = 0;
    var chooses = 0;
    var selections = 0;
    var scans = 0;
    await pumpOverview(
      tester,
      size: const Size(620, 600),
      onBrowse: () => browses++,
      onChooseFolder: () => chooses++,
      onSelectTarget: (_) => selections++,
      onScan: () => scans++,
    );

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    final beforeScroll = scrollable.position.pixels;

    await tester.tap(
      find.byKey(StorageStewardHome.chooseFolderKey).hitTestable(),
    );
    expect(chooses, 1);
    expect(browses, 0);
    expect(scans, 0);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('storage-target-downloads')),
      80,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(
      find.byKey(const ValueKey('storage-target-downloads')).hitTestable(),
    );
    expect(selections, 1);
    expect(chooses, 1);
    expect(browses, 0);
    expect(scans, 0);

    await tester.scrollUntilVisible(
      find.byKey(StorageStewardHome.scanActionKey),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(beforeScroll));

    final browse = find.byKey(StorageStewardHome.browseKey).hitTestable();
    final scan = find.byKey(StorageStewardHome.scanActionKey).hitTestable();
    expect(browse, findsOneWidget);
    expect(scan, findsOneWidget);

    await tester.tap(browse);
    await tester.tap(scan);
    expect(browses, 1);
    expect(chooses, 1);
    expect(selections, 1);
    expect(scans, 1);
  });

  for (final (accentName, accent) in VolwardTokens.accentPresets) {
    for (final brightness in Brightness.values) {
      testWidgets('primary action contrast $accentName $brightness', (
        tester,
      ) async {
        await pumpOverview(
          tester,
          brightness: brightness,
          accent: accent,
          onScan: () {},
        );

        final action = find.byKey(StorageStewardHome.scanActionKey);
        final material = tester.widget<Material>(
          find.descendant(of: action, matching: find.byType(Material)),
        );
        final icon = tester.widget<Icon>(
          find.descendant(
            of: action,
            matching: find.byIcon(Icons.radar_outlined),
          ),
        );
        final label = tester.widget<Text>(
          find.descendant(of: action, matching: find.text('Start Scan')),
        );

        final background = material.color!;
        final iconForeground = icon.color!;
        final textForeground = label.style!.color!;
        expect(iconForeground, textForeground);
        expect(
          contrastRatio(iconForeground, background),
          greaterThanOrEqualTo(4.5),
        );
      });

      testWidgets('dashboard small text contrast $accentName $brightness', (
        tester,
      ) async {
        await pumpOverview(
          tester,
          summary: completedSummary,
          brightness: brightness,
          accent: accent,
          onScan: () {},
        );

        final scanSummary = find.byKey(StorageStewardHome.browseCardKey);
        final scanBento = tester.widget<DecoratedBox>(
          find
              .descendant(of: scanSummary, matching: find.byType(DecoratedBox))
              .first,
        );

        expectTextContrast(
          tester,
          find.text('256 B reclaimable'),
          (scanBento.decoration as BoxDecoration).color!,
        );
      });
    }
  }

  testWidgets('live and cached status chips use composited contrast', (
    tester,
  ) async {
    for (final (_, accent) in VolwardTokens.accentPresets) {
      for (final brightness in Brightness.values) {
        Color? neutralFill;
        for (final (summary, label) in [
          (completedSummary, 'Live disk data'),
          (cachedSummary, 'Cached disk data'),
          (loadingSummary, 'Reading disk…'),
          (unavailableSummary, 'Disk capacity unavailable'),
        ]) {
          await pumpOverview(
            tester,
            summary: summary,
            brightness: brightness,
            accent: accent,
          );
          final decoration = statusChipDecoration(tester);
          final tokens = Theme.of(
            tester.element(statusChipFinder()),
          ).extension<VolwardTokens>()!;

          expectStatusChipContrast(tester, label);
          if (summary == cachedSummary) {
            expect(decoration.color, tokens.warning.withValues(alpha: 0.16));
            expect(
              (decoration.border! as Border).top.color,
              tokens.warning.withValues(alpha: 0.38),
            );
          } else if (summary == loadingSummary ||
              summary == unavailableSummary) {
            neutralFill ??= decoration.color;
            expect(decoration.color, neutralFill);
            expect(
              decoration.color,
              isNot(tokens.warning.withValues(alpha: 0.16)),
            );
          }
        }
      }
    }
  });

  testWidgets('cancel scan action uses danger with contrast', (tester) async {
    // Both layouts: the wide board and _BrowseCard render the CTA separately,
    // and an earlier refactor dropped the danger accent from the wide one
    // without anything failing.
    for (final size in [const Size(1280, 800), const Size(620, 600)]) {
      for (final brightness in Brightness.values) {
        await pumpOverview(
          tester,
          size: size,
          summary: scanningSummary,
          brightness: brightness,
          onCancelScan: () {},
        );

        final action = find.byKey(StorageStewardHome.scanActionKey);
        final material = tester.widget<Material>(
          find.descendant(of: action, matching: find.byType(Material)),
        );
        final icon = tester.widget<Icon>(
          find.descendant(
            of: action,
            matching: find.byIcon(Icons.stop_circle_outlined),
          ),
        );
        final label = tester.widget<Text>(
          find.descendant(of: action, matching: find.text('Cancel Scan')),
        );
        final tokens = Theme.of(
          tester.element(action),
        ).extension<VolwardTokens>()!;

        expect(
          material.color,
          tokens.danger,
          reason: 'cancel is destructive at ${size.width.toInt()}px',
        );
        expect(
          (material.shape! as StadiumBorder).side.color,
          tokens.danger,
          reason: 'border tracks the fill at ${size.width.toInt()}px',
        );
        expect(icon.color, label.style!.color);
        expect(
          contrastRatio(label.style!.color!, material.color!),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  testWidgets('a scan that has not started keeps the primary accent', (
    tester,
  ) async {
    // The other half of the pair: semanticColor must stay null when the CTA
    // means "proceed", or every dashboard shows a red Start Scan.
    await pumpOverview(tester, onScan: () {});

    final action = find.byKey(StorageStewardHome.scanActionKey);
    final material = tester.widget<Material>(
      find.descendant(of: action, matching: find.byType(Material)),
    );
    final tokens = Theme.of(tester.element(action)).extension<VolwardTokens>()!;

    expect(material.color, tokens.primary);
  });

  testWidgets('home canvas follows the selected accent gradient', (
    tester,
  ) async {
    for (final (_, accent) in VolwardTokens.accentPresets) {
      for (final brightness in Brightness.values) {
        await pumpOverview(tester, brightness: brightness, accent: accent);
        await tester.pumpAndSettle();

        final surface = tester.widget<DecoratedBox>(
          find.byKey(StorageStewardHome.dashboardSurfaceKey),
        );
        final decoration = surface.decoration as BoxDecoration;
        final tokens = Theme.of(
          tester.element(find.byKey(StorageStewardHome.dashboardSurfaceKey)),
        ).extension<VolwardTokens>()!;
        final ink = brightness == Brightness.dark
            ? const Color(0xFF111113)
            : tokens.canvasParchment;
        final softInk = brightness == Brightness.dark
            ? const Color(0xFF1A1A1E)
            : tokens.surfacePearl;
        final base = Color.alphaBlend(
          tokens.primary.withValues(alpha: 0.10),
          ink,
        );
        final soft = Color.alphaBlend(
          tokens.primary.withValues(alpha: 0.08),
          softInk,
        );

        expect(decoration.color, base);
        expect(decoration.gradient, isA<LinearGradient>());
        final gradient = decoration.gradient! as LinearGradient;
        expect(gradient.colors, [
          base,
          soft,
          tokens.primary.withValues(alpha: 0.42),
        ]);
        expect(gradient.stops, const [0, 0.55, 1]);
      }
    }
  });

  testWidgets('category row opens the matching type without other actions', (
    tester,
  ) async {
    String? selectedCategory;
    var browses = 0;
    var scans = 0;
    await pumpOverview(
      tester,
      summary: categorizedSummary,
      onBrowse: () => browses++,
      onScan: () => scans++,
      onSelectCategory: (name) => selectedCategory = name,
    );

    await tester.tap(find.byKey(const ValueKey('storage-category-Cache')));
    await tester.pump();

    expect(selectedCategory, 'Cache');
    expect(browses, 0);
    expect(scans, 0);
  });

  testWidgets('scanning absorbs category row taps', (tester) async {
    String? selectedCategory;
    await pumpOverview(
      tester,
      summary: StorageHomeSummary(
        overview: categorizedSummary.overview,
        selectedLocation: categorizedSummary.selectedLocation,
        selectedVolume: categorizedSummary.selectedVolume,
        scanning: true,
        hasCompletedScan: false,
        categories: categorizedSummary.categories,
      ),
      onSelectCategory: (name) => selectedCategory = name,
    );

    await tester.tap(find.byKey(const ValueKey('storage-category-Cache')));
    await tester.pump();

    expect(selectedCategory, isNull);
  });

  testWidgets('locked overview disables scan and cancel actions', (
    tester,
  ) async {
    var scanCalls = 0;
    var cancelCalls = 0;
    await pumpOverview(
      tester,
      summary: scanningSummary,
      interactionsLocked: true,
      onScan: () => scanCalls++,
      onCancelScan: () => cancelCalls++,
    );

    await tester.tap(find.byKey(StorageStewardHome.scanActionKey));
    expect(scanCalls, 0);
    expect(cancelCalls, 0);
  });

  testWidgets('built-in targets render and selection stays independent', (
    tester,
  ) async {
    StorageLocationInfo? selected;
    var browses = 0;
    var chooses = 0;
    var scans = 0;
    await pumpOverview(
      tester,
      onBrowse: () => browses++,
      onChooseFolder: () => chooses++,
      onSelectTarget: (value) => selected = value,
      onScan: () => scans++,
    );

    expect(
      find.byKey(const ValueKey('storage-target-applications')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('storage-target-desktop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('storage-target-documents')),
      findsOneWidget,
    );
    final selectedTarget = find.byKey(const ValueKey('storage-target-home'));
    final selectedMaterial = tester.widget<Material>(
      find.ancestor(
        of: selectedTarget,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Material && widget.shape is RoundedRectangleBorder,
        ),
      ),
    );
    final selectedShape = selectedMaterial.shape! as RoundedRectangleBorder;
    final tokens = Theme.of(
      tester.element(selectedTarget),
    ).extension<VolwardTokens>()!;
    expect(selectedMaterial.color, tokens.primary.withValues(alpha: 0.24));
    expect(selectedShape.borderRadius, BorderRadius.circular(16));
    expect(selectedShape.side.color, tokens.primary.withValues(alpha: 0.62));
    expect(
      tester.widget<InkWell>(selectedTarget).borderRadius,
      BorderRadius.circular(16),
    );

    await tester.tap(find.byKey(const ValueKey('storage-target-downloads')));

    expect(selected?.kind, StorageLocationKind.downloads);
    expect(browses, 0);
    expect(chooses, 0);
    expect(scans, 0);
  });

  testWidgets(
    'pinned custom target is available from one recent folders button',
    (tester) async {
      StorageLocationInfo? selected;
      await pumpOverview(
        tester,
        summary: StorageHomeSummary(
          overview: customSummary.overview,
          selectedLocation: home,
          selectedVolume: volume,
          scanning: false,
          hasCompletedScan: false,
          pinnedCustomLocation: customLocation,
        ),
        onSelectTarget: (location) => selected = location,
      );

      expect(
        find.byKey(const ValueKey('storage-target-custom-deep-archive')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('storage-target-home')), findsOneWidget);
      expect(find.byKey(StorageStewardHome.recentFoldersKey), findsOneWidget);

      await tester.tap(find.byKey(StorageStewardHome.recentFoldersKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('storage-recent-folder-option-custom-deep-archive'),
        ),
      );
      await tester.pumpAndSettle();

      expect(selected, customLocation);
    },
  );

  testWidgets('recent custom targets stay in one lightweight menu', (
    tester,
  ) async {
    StorageLocationInfo? selected;
    await pumpOverview(
      tester,
      summary: StorageHomeSummary(
        overview: customSummary.overview,
        selectedLocation: home,
        selectedVolume: volume,
        scanning: false,
        hasCompletedScan: false,
        recentCustomLocations: const [customLocation, secondCustomLocation],
      ),
      onSelectTarget: (location) => selected = location,
    );

    expect(
      find.byKey(const ValueKey('storage-target-custom-deep-archive')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('storage-target-custom-photo-library')),
      findsNothing,
    );
    expect(find.byKey(StorageStewardHome.recentFoldersKey), findsOneWidget);
    expect(
      find.byKey(const ValueKey('storage-recent-folders-semantics')),
      findsNothing,
    );
    expect(find.text('Recent Folders'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    final menuButton = tester.widget<PopupMenuButton<StorageLocationInfo>>(
      find.byKey(StorageStewardHome.recentFoldersKey),
    );
    final theme = Theme.of(
      tester.element(find.byKey(StorageStewardHome.recentFoldersKey)),
    );
    final tokens = theme.extension<VolwardTokens>()!;
    final softInk = theme.brightness == Brightness.dark
        ? const Color(0xFF1A1A1E)
        : tokens.surfacePearl;
    expect(
      menuButton.color,
      Color.alphaBlend(tokens.primary.withValues(alpha: 0.18), softInk),
    );
    expect(menuButton.elevation, 0);
    expect(menuButton.shadowColor, Colors.transparent);
    expect(menuButton.shape, isA<RoundedRectangleBorder>());

    await tester.tap(find.byKey(StorageStewardHome.recentFoldersKey));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey('storage-recent-folder-option-custom-deep-archive'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('storage-recent-folder-option-custom-photo-library'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        const ValueKey('storage-recent-folder-option-custom-photo-library'),
      ),
    );
    await tester.pumpAndSettle();

    expect(selected, secondCustomLocation);
  });

  testWidgets('selected custom target doubles as the recent folders menu', (
    tester,
  ) async {
    StorageLocationInfo? selected;
    await pumpOverview(
      tester,
      summary: StorageHomeSummary(
        overview: customSummary.overview,
        selectedLocation: customLocation,
        selectedVolume: volume,
        scanning: false,
        hasCompletedScan: false,
        recentCustomLocations: const [customLocation, secondCustomLocation],
      ),
      onSelectTarget: (location) => selected = location,
    );

    expect(find.byKey(StorageStewardHome.recentFoldersKey), findsNothing);
    expect(
      find.byKey(const ValueKey('storage-target-custom-deep-archive')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('storage-target-custom-photo-library')),
      findsNothing,
    );
    final menuButton = tester.widget<PopupMenuButton<StorageLocationInfo>>(
      find.byKey(const ValueKey('storage-target-menu-custom-deep-archive')),
    );
    expect(menuButton.child, isA<Material>());

    await tester.tap(
      find.byKey(const ValueKey('storage-target-menu-custom-deep-archive')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('storage-recent-folder-option-custom-photo-library'),
      ),
    );
    await tester.pumpAndSettle();

    expect(selected, secondCustomLocation);
  });

  testWidgets('custom selection becomes a compact target with full path', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpOverview(tester, summary: customSummary);

      expect(
        find.byKey(const ValueKey('storage-target-custom-deep-archive')),
        findsOneWidget,
      );
      expect(find.text('Deep Archive'), findsWidgets);
      expect(find.text(customPath), findsNothing);
      expect(find.byTooltip(customPath), findsNothing);

      final customData = tester
          .getSemantics(
            find.byKey(
              const ValueKey('storage-target-semantics-custom-deep-archive'),
            ),
          )
          .getSemanticsData();
      expect(customData.label, 'Deep Archive');
      expect(customData.value, customPath);
      expect(customData.flagsCollection.isSelected, Tristate.isTrue);
      expect(customData.hasAction(SemanticsAction.tap), isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Windows volume locations stay out of the sidebar', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpOverview(tester, summary: windowsSummary);

      expect(targetTiles(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('storage-target-drive-d')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('storage-target-selected-drive-d')),
        findsOneWidget,
      );
      expect(find.byTooltip('d:/'), findsNothing);

      final customData = tester
          .getSemantics(
            find.byKey(
              const ValueKey('storage-target-semantics-selected-drive-d'),
            ),
          )
          .getSemanticsData();
      expect(customData.label, 'Selected Data');
      expect(customData.value, 'd:/');
      expect(customData.flagsCollection.isSelected, Tristate.isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Windows header selector changes drive without other actions', (
    tester,
  ) async {
    StorageLocationInfo? selected;
    var browses = 0;
    var scans = 0;
    final semantics = tester.ensureSemantics();
    try {
      await pumpOverview(
        tester,
        summary: windowsMultiDriveSummary,
        onBrowse: () => browses++,
        onSelectTarget: (location) => selected = location,
        onScan: () => scans++,
      );

      expect(targetTiles(), findsNWidgets(4));
      expect(find.byKey(const ValueKey('storage-target-home')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('storage-target-desktop')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('storage-target-drive-d')),
        findsNothing,
      );
      final selector = tester.getSemantics(
        find.byKey(StorageStewardHome.volumeSelectorKey),
      );
      expect(selector.getSemanticsData().label, 'Scan range');
      expect(selector.getSemanticsData().value, 'Disk Data');
      expect(selector.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(
        selector.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(find.byKey(StorageStewardHome.volumeSelectorKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('storage-volume-option-drive-c')),
      );
      await tester.pumpAndSettle();

      expect(selected, windowsSystemDrive);
      expect(browses, 0);
      expect(scans, 0);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'Windows user folders match POSIX sidebar and keep a disk selector',
    (tester) async {
      StorageLocationInfo? selected;
      await pumpOverview(
        tester,
        summary: windowsUserFolderSummary,
        onSelectTarget: (location) => selected = location,
      );

      expect(targetTiles(), findsNWidgets(4));
      expect(find.byKey(const ValueKey('storage-target-home')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('storage-target-desktop')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('storage-target-downloads')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('storage-target-documents')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('storage-target-drive-d')),
        findsNothing,
      );
      expect(find.byKey(StorageStewardHome.volumeSelectorKey), findsOneWidget);

      await tester.tap(find.byKey(StorageStewardHome.volumeSelectorKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('storage-volume-option-drive-d')),
      );
      await tester.pumpAndSettle();

      expect(selected?.kind, StorageLocationKind.volume);
      expect(selected?.volumeId, 'D:');
    },
  );

  testWidgets('POSIX literal backslash and separator paths stay distinct', (
    tester,
  ) async {
    await pumpOverview(tester, summary: posixDistinctSummary);

    expect(targetTiles(), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('storage-target-posix-backslash')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('storage-target-posix-slash')),
      findsOneWidget,
    );
  });

  testWidgets('blank panel, browse, and scan controls stay independent', (
    tester,
  ) async {
    var browses = 0;
    var scans = 0;
    await pumpOverview(
      tester,
      onBrowse: () => browses++,
      onScan: () => scans++,
    );

    final capacity = tester.getRect(find.byKey(StorageStewardHome.capacityKey));
    await tester.tapAt(capacity.center);
    expect(browses, 0);
    await tester.tap(find.byKey(StorageStewardHome.browseKey));
    expect(browses, 1);
    await tester.tap(find.byKey(StorageStewardHome.browseKey));
    expect(browses, 2);
    await tester.tap(find.byKey(StorageStewardHome.scanActionKey));
    expect(scans, 1);
    expect(browses, 2);
  });

  testWidgets('choose folder stays independent from browse and scan', (
    tester,
  ) async {
    var browses = 0;
    var chooses = 0;
    var scans = 0;
    await pumpOverview(
      tester,
      onBrowse: () => browses++,
      onChooseFolder: () => chooses++,
      onScan: () => scans++,
    );

    await tester.tap(find.byKey(StorageStewardHome.chooseFolderKey));

    expect(chooses, 1);
    expect(browses, 0);
    expect(scans, 0);
  });

  testWidgets('scanning disables targets and exposes progress and cancel', (
    tester,
  ) async {
    var cancels = 0;
    await pumpOverview(
      tester,
      summary: scanningSummary,
      onCancelScan: () => cancels++,
    );

    final target = tester.widget<InkWell>(
      find.byKey(const ValueKey('storage-target-downloads')),
    );
    expect(target.onTap, isNull);
    expect(find.byKey(const ValueKey('storage-scan-progress')), findsOneWidget);
    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('storage-scan-progress')),
    );
    expect(progress.borderRadius, BorderRadius.circular(999));
    expect(
      tester
          .widget<ClipRRect>(
            find.ancestor(
              of: find.byKey(const ValueKey('storage-scan-progress')),
              matching: find.byType(ClipRRect),
            ),
          )
          .borderRadius,
      BorderRadius.circular(999),
    );
    expect(find.text('Cancel Scan'), findsOneWidget);
    await tester.tap(find.byKey(StorageStewardHome.scanActionKey));
    expect(cancels, 1);
  });

  testWidgets('compact scanning exposes cancel action', (tester) async {
    var cancels = 0;
    await pumpOverview(
      tester,
      size: const Size(600, 1400),
      summary: scanningSummary,
      onCancelScan: () => cancels++,
    );

    expect(find.text('Cancel Scan'), findsOneWidget);
    await tester.tap(find.byKey(StorageStewardHome.scanActionKey));
    expect(cancels, 1);
  });

  testWidgets('restoring a snapshot hides scan action', (tester) async {
    // A cold launch with a cached snapshot sets `scanning` so the dashboard
    // reads as busy, but there is no scan behind it. Keying the CTA off
    // `scanning` alone put a permanently disabled "Cancel Scan" on screen for
    // the whole restore.
    await pumpOverview(
      tester,
      summary: StorageHomeSummary(
        overview: readySummary.overview,
        selectedLocation: readySummary.selectedLocation,
        selectedVolume: readySummary.selectedVolume,
        scanning: true,
        restoringSnapshot: true,
        hasCompletedScan: false,
      ),
    );

    expect(find.text('Cancel Scan'), findsNothing);
    expect(find.text('Start Scan'), findsNothing);
    expect(find.byKey(StorageStewardHome.scanActionKey), findsNothing);
  });

  testWidgets('restoring a snapshot hides scan action in compact layout', (
    tester,
  ) async {
    await pumpOverview(
      tester,
      size: const Size(600, 1400),
      summary: StorageHomeSummary(
        overview: readySummary.overview,
        selectedLocation: readySummary.selectedLocation,
        selectedVolume: readySummary.selectedVolume,
        scanning: true,
        restoringSnapshot: true,
        hasCompletedScan: false,
      ),
    );

    expect(find.byKey(StorageStewardHome.scanActionKey), findsNothing);
  });

  testWidgets('disabled scan targets and folder action absorb real taps', (
    tester,
  ) async {
    var browses = 0;
    var chooses = 0;
    var selections = 0;
    await pumpOverview(
      tester,
      summary: scanningSummary,
      onBrowse: () => browses++,
      onChooseFolder: () => chooses++,
      onSelectTarget: (_) => selections++,
      onCancelScan: () {},
    );

    await tester.tap(find.byKey(const ValueKey('storage-target-downloads')));
    await tester.tap(find.byKey(StorageStewardHome.chooseFolderKey));

    expect(browses, 0);
    expect(chooses, 0);
    expect(selections, 0);
  });

  testWidgets('completed scan exposes rescan and scan metadata', (
    tester,
  ) async {
    var scans = 0;
    await pumpOverview(
      tester,
      summary: completedSummary,
      onScan: () => scans++,
    );

    expect(find.text('Rescan'), findsOneWidget);
    expect(find.text('256 B reclaimable'), findsOneWidget);
    expect(find.textContaining('Last scan'), findsOneWidget);
    await tester.tap(find.byKey(StorageStewardHome.scanActionKey));
    expect(scans, 1);
  });

  testWidgets('compact completed scan exposes rescan action', (tester) async {
    var scans = 0;
    await pumpOverview(
      tester,
      size: const Size(600, 1400),
      summary: completedSummary,
      onScan: () => scans++,
    );

    expect(find.text('Rescan'), findsOneWidget);
    await tester.tap(find.byKey(StorageStewardHome.scanActionKey));
    expect(scans, 1);
  });

  testWidgets('loading and unavailable capacity states stay truthful', (
    tester,
  ) async {
    await pumpOverview(tester, summary: loadingSummary);
    expect(find.text('Reading disk…'), findsOneWidget);
    expect(find.text('0 B'), findsNothing);
    expect(find.text('—'), findsNWidgets(3));
    expect(capacityMeterFill(), findsNothing);

    await pumpOverview(tester, summary: unavailableSummary);
    expect(find.text('Disk capacity unavailable'), findsOneWidget);
    expect(find.text('0 B'), findsNothing);
    expect(capacityMeterFill(), findsNothing);
    expect(find.byKey(StorageStewardHome.capacityMeterKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing root stays neutral without an empty target tile', (
    tester,
  ) async {
    await pumpOverview(tester, summary: neutralUnavailableSummary);

    expect(targetTiles(), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(StorageStewardHome.capacityPathKey)).data,
      '—',
    );
    expect(find.byTooltip(''), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capacity status follows usable data provenance', (tester) async {
    await pumpOverview(tester, summary: cachedWhileLoadingSummary);
    expect(find.text('Cached disk data'), findsOneWidget);
    expect(find.text('Reading disk…'), findsNothing);
    expect(capacityMeterFill(), findsOneWidget);
    expect(
      tester.widget<FractionallySizedBox>(capacityMeterFill()).widthFactor,
      closeTo(0.75, 0.001),
    );

    await pumpOverview(tester, summary: invalidLiveSummary);
    expect(find.text('Disk capacity unavailable'), findsOneWidget);
    expect(find.text('Live disk data'), findsNothing);
    expect(find.text('140 B'), findsNothing);
    expect(capacityMeterFill(), findsNothing);
  });

  testWidgets('cached capacity is labeled and remains disk capacity', (
    tester,
  ) async {
    await pumpOverview(tester, summary: cachedSummary);

    expect(find.text('Cached disk data'), findsOneWidget);
    expect(find.text('768 B'), findsOneWidget);
    expect(find.text('1 KB'), findsOneWidget);
    expect(find.text('256 B'), findsOneWidget);
    expect(capacityMeterFill(), findsOneWidget);
    expect(
      tester.widget<FractionallySizedBox>(capacityMeterFill()).widthFactor,
      closeTo(0.75, 0.001),
    );
  });

  testWidgets('disk overview localizes content, semantics, and dates', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpOverview(tester, summary: completedSummary, onScan: () {});

      expect(find.text('Live disk data'), findsOneWidget);
      expect(find.text('Used'), findsOneWidget);
      expect(find.text('Total capacity'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Scan range'), findsNothing);
      expect(find.text('Home'), findsWidgets);
      expect(find.text('256 B reclaimable'), findsOneWidget);
      expect(find.textContaining('Last scan'), findsOneWidget);
      expect(find.textContaining('Aug'), findsOneWidget);
      expect(
        find.bySemanticsLabel('600 B used of 1000 B, 400 B available'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Rescan'), findsOneWidget);

      await pumpOverview(
        tester,
        locale: const Locale('zh'),
        summary: completedSummary,
        onScan: () {},
      );

      expect(find.text('实时磁盘数据'), findsOneWidget);
      expect(find.text('已使用'), findsOneWidget);
      expect(find.text('总容量'), findsOneWidget);
      expect(find.text('可用'), findsOneWidget);
      expect(find.text('扫描范围'), findsNothing);
      expect(find.text('主目录'), findsWidgets);
      expect(find.text('可回收 256 B'), findsOneWidget);
      expect(find.textContaining('上次扫描'), findsOneWidget);
      expect(find.textContaining('8月'), findsOneWidget);
      expect(
        find.bySemanticsLabel('已使用 600 B，总容量 1000 B，可用 400 B'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('重新扫描'), findsOneWidget);

      await pumpOverview(
        tester,
        locale: const Locale('zh'),
        summary: scanningSummary,
        onCancelScan: () {},
      );
      expect(find.bySemanticsLabel('扫描中…'), findsOneWidget);
      expect(find.bySemanticsLabel('取消扫描'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('panel semantics expose independent actions and one browse', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpOverview(tester, onScan: () {});

      expect(find.bySemanticsLabel('Browse Files'), findsOneWidget);
      final target = tester.getSemantics(
        find.byKey(const ValueKey('storage-target-semantics-downloads')),
      );
      final choose = tester.getSemantics(
        find.bySemanticsLabel('Choose Folder'),
      );
      final browse = tester.getSemantics(find.bySemanticsLabel('Browse Files'));
      final scan = tester.getSemantics(find.bySemanticsLabel('Start Scan'));
      final capacity = tester.getSemantics(
        find.bySemanticsLabel('600 B used of 1000 B, 400 B available'),
      );
      final panel = tester.getSemantics(
        find.byKey(StorageStewardHome.panelKey),
      );

      expect(target.getSemanticsData().value, downloads.path);
      expectButtonSemantics(target, enabled: true);
      expectButtonSemantics(choose, enabled: true);
      expectButtonSemantics(browse, enabled: true);
      expectButtonSemantics(scan, enabled: true);
      expect(
        capacity.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      expect(capacity.getSemanticsData().flagsCollection.isButton, isFalse);
      expect(capacity.getSemanticsData().value, '/');
      expect(find.byTooltip('/'), findsNothing);
      expect(panel.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      expect({target.id, choose.id, browse.id, scan.id, capacity.id}.length, 5);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('button semantics follow scanning and rescan states', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpOverview(tester, summary: scanningSummary, onCancelScan: () {});

      expectButtonSemantics(
        tester.getSemantics(
          find.byKey(const ValueKey('storage-target-semantics-downloads')),
        ),
        enabled: false,
      );
      expectButtonSemantics(
        tester.getSemantics(find.bySemanticsLabel('Choose Folder')),
        enabled: false,
      );
      expectButtonSemantics(
        tester.getSemantics(find.bySemanticsLabel('Browse Files')),
        enabled: true,
      );
      expectButtonSemantics(
        tester.getSemantics(find.bySemanticsLabel('Cancel Scan')),
        enabled: true,
      );

      await pumpOverview(tester, summary: completedSummary, onScan: () {});
      expectButtonSemantics(
        tester.getSemantics(find.bySemanticsLabel('Rescan')),
        enabled: true,
      );

      await pumpOverview(tester);
      expectButtonSemantics(
        tester.getSemantics(find.bySemanticsLabel('Start Scan')),
        enabled: false,
      );
    } finally {
      semantics.dispose();
    }
  });

  for (final locale in const [Locale('en'), Locale('zh')]) {
    for (final brightness in Brightness.values) {
      for (final size in const [
        Size(1280, 800),
        Size(900, 700),
        Size(640, 600),
        Size(620, 600),
      ]) {
        testWidgets('no overflow $locale $brightness '
            '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
          await pumpOverview(
            tester,
            size: size,
            locale: locale,
            brightness: brightness,
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final (platformLabel, summary, longPath) in [
    ('windows', longWindowsSummary, longWindowsLocations.last.path),
    ('posix', longPosixSummary, longPosixPath),
  ]) {
    for (final locale in const [Locale('en'), Locale('zh')]) {
      for (final size in const [
        Size(1280, 800),
        Size(780, 700),
        Size(700, 600),
        Size(620, 600),
      ]) {
        testWidgets('long platform data does not overflow '
            '$platformLabel ${locale.languageCode} '
            '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
          await pumpOverview(
            tester,
            size: size,
            locale: locale,
            summary: summary,
            onScan: () {},
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.byTooltip(longPath), findsNothing);

          final scanAction = find.byKey(StorageStewardHome.scanActionKey);
          final scrollableFinder = find.byType(Scrollable);
          expect(scanAction, findsOneWidget);
          await tester.scrollUntilVisible(
            scanAction,
            200,
            scrollable: scrollableFinder,
          );
          await tester.pumpAndSettle();
          expect(scanAction.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  StorageHomeSummary summaryWithItems({
    List<StorageHomeItem> items = const [],
    bool scanning = false,
    bool hasCompletedScan = true,
    int? scannedBytes,
    List<StorageHomeCategorySummary>? categories,
  }) {
    return StorageHomeSummary(
      overview: readySummary.overview,
      selectedLocation: readySummary.selectedLocation,
      selectedVolume: readySummary.selectedVolume,
      scanning: scanning,
      hasCompletedScan: hasCompletedScan,
      scannedBytes: scannedBytes,
      categories: categories ?? completedSummary.categories,
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

  testWidgets('the right panel stacks three blocks top to bottom', (
    tester,
  ) async {
    await pumpOverview(
      tester,
      summary: summaryWithItems(items: const [bigFile, archiveDir]),
    );

    final capacity = tester.getRect(find.byKey(StorageStewardHome.capacityKey));
    final largest = tester.getRect(find.byKey(LargestItemsPanel.panelKey));
    final composition = tester.getRect(
      find.byKey(StorageStewardHome.browseCardKey),
    );

    expect(capacity.bottom, lessThanOrEqualTo(largest.top));
    expect(largest.bottom, lessThanOrEqualTo(composition.top));
    expect(capacity.left, closeTo(largest.left, 1));
    expect(largest.left, closeTo(composition.left, 1));
  });

  testWidgets('no overflow at common window sizes', (tester) async {
    for (final size in const [
      Size(1280, 800),
      Size(1440, 900),
      Size(1024, 720),
      Size(600, 1400),
    ]) {
      await pumpOverview(
        tester,
        size: size,
        summary: summaryWithItems(
          items: const [bigFile, archiveDir],
          scannedBytes: 31200000000,
        ),
      );
      expect(tester.takeException(), isNull, reason: 'overflow at $size');
    }
  });

  testWidgets('wide scanning dashboard keeps the category skeleton in bounds', (
    tester,
  ) async {
    await pumpOverview(
      tester,
      size: const Size(1280, 800),
      summary: summaryWithItems(
        scanning: true,
        hasCompletedScan: false,
        categories: const [],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(StorageStewardHome.browseCardKey), findsOneWidget);
  });

  testWidgets('the composition block keeps both actions and the pie', (
    tester,
  ) async {
    await pumpOverview(
      tester,
      summary: summaryWithItems(
        categories: const [StorageHomeCategorySummary(name: 'Cache', count: 4)],
      ),
    );

    expect(find.byKey(StorageStewardHome.browseKey), findsOneWidget);
    expect(find.byKey(StorageStewardHome.scanActionKey), findsOneWidget);
    expect(find.byKey(StorageStewardHome.categoryPieKey), findsOneWidget);
  });

  testWidgets('an empty category list drops the pie for a hint', (
    tester,
  ) async {
    await pumpOverview(
      tester,
      summary: StorageHomeSummary(
        overview: readySummary.overview,
        selectedLocation: readySummary.selectedLocation,
        selectedVolume: readySummary.selectedVolume,
        scanning: false,
        hasCompletedScan: true,
      ),
    );

    expect(find.byKey(StorageStewardHome.categoryPieKey), findsNothing);
    expect(find.text('This folder is empty'), findsWidgets);
  });

  testWidgets('onOpenItem reaches the panel rows', (tester) async {
    StorageHomeItem? opened;
    await pumpOverview(
      tester,
      summary: summaryWithItems(items: const [bigFile]),
      onOpenItem: (item) => opened = item,
    );

    await tester.tap(find.byKey(LargestItemsPanel.rowKey(bigFile.path)));
    await tester.pump();

    expect(opened?.path, bigFile.path);
  });

  testWidgets('compact shows three rows, wide shows three', (tester) async {
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

    await pumpOverview(
      tester,
      size: const Size(600, 1400),
      summary: summaryWithItems(items: many),
    );
    expect(
      find.byKey(LargestItemsPanel.rowKey('/Users/me/item3')),
      findsNothing,
    );

    await pumpOverview(
      tester,
      size: const Size(1280, 900),
      summary: summaryWithItems(items: many),
    );
    // Wide mode now also shows only 3 items (item0, item1, item2)
    expect(
      find.byKey(LargestItemsPanel.rowKey('/Users/me/item2')),
      findsOneWidget,
    );
    expect(
      find.byKey(LargestItemsPanel.rowKey('/Users/me/item3')),
      findsNothing,
    );
  });
}
