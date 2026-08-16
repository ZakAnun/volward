import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/home_page.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/scan_preview.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/storage_overview.dart';
import 'package:volward/storage_overview_provider.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/theme/volward_theme_settings.dart';
import 'package:volward/updater/app_updater.dart';
import 'package:volward/volward_session.dart';
import 'package:volward/widgets/scan_column_view.dart';
import 'package:volward/widgets/storage_steward_home.dart';

StorageOverviewData _overviewData([String volumeName = 'Test Disk']) {
  return StorageOverviewData(
    selectedVolumeId: '/',
    volumes: [
      StorageVolumeInfo(
        id: '/',
        name: volumeName,
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
        path: '/home',
        kind: StorageLocationKind.home,
        volumeId: '/',
      ),
      StorageLocationInfo(
        id: 'downloads',
        name: 'Downloads',
        path: '/home/Downloads',
        kind: StorageLocationKind.downloads,
        volumeId: '/',
      ),
    ],
  );
}

String _defaultHomeRoot() {
  return defaultScanRootPath(
    environment: Platform.environment,
    isWindows: () => Platform.isWindows,
  );
}

class _OverviewProvider implements StorageOverviewProvider {
  _OverviewProvider({this.volumeName = 'Test Disk'});

  final String volumeName;
  int calls = 0;
  final List<String?> selectedPaths = [];

  @override
  Future<StorageOverviewData> load({String? selectedPath}) async {
    calls++;
    selectedPaths.add(selectedPath);
    return _overviewData(volumeName);
  }
}

class _QueuedOverviewProvider implements StorageOverviewProvider {
  final List<String?> selectedPaths = [];
  final List<Completer<StorageOverviewData>> requests = [];

  @override
  Future<StorageOverviewData> load({String? selectedPath}) {
    selectedPaths.add(selectedPath);
    final request = Completer<StorageOverviewData>();
    requests.add(request);
    return request.future;
  }
}

class _Session extends VolwardSession {
  _Session({
    this.exposePreview = false,
    this.startupRootGate,
    this.restoredRootOnLoad,
    this.snapshotFileApi = true,
    this.scanGate,
    bool hangRestore = false,
    bool setInitialRoot = true,
  }) : super.test() {
    if (setInitialRoot) setScanRoots(['/']);
    if (!hangRestore) _restoreGate.complete();
  }

  final bool exposePreview;
  final Completer<String>? startupRootGate;
  final String? restoredRootOnLoad;
  final bool snapshotFileApi;
  final Completer<String>? scanGate;
  bool previewLoading = false;
  int previewCalls = 0;
  String? switchedRoot;
  bool? switchStartedScan;
  int runScanCalls = 0;
  int cancelCalls = 0;
  int listenerAdds = 0;
  int listenerRemoves = 0;
  int loadSessionCalls = 0;
  int resolveStartupCalls = 0;
  int restoreCalls = 0;
  final Completer<void> _restoreGate = Completer<void>();

  late final ScanSnapshotState _previewSnapshot = ScanSnapshotState.fromWire(
    buildPreviewSnapshot(
      rootPath: '/',
      quickListEntries: const [
        {'path': '/Documents', 'is_dir': true},
      ],
    ),
  );

  @override
  ScanSnapshotState? get lastSnapshot =>
      exposePreview ? _previewSnapshot : null;

  @override
  bool get restoringSnapshot => exposePreview;

  @override
  bool get hasSnapshotFileApi => snapshotFileApi;

  @override
  bool get targetPreviewLoading => previewLoading;

  void setPreviewLoading(bool value) {
    previewLoading = value;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    listenerAdds++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerRemoves++;
    super.removeListener(listener);
  }

  @override
  Future<void> previewTarget({int? expectedGeneration}) async {
    previewCalls++;
  }

  @override
  Future<void> loadSessionStateIfNeeded() async {
    loadSessionCalls++;
    final restoredRoot = restoredRootOnLoad;
    if (restoredRoot != null) setScanRoots([restoredRoot]);
  }

  @override
  Future<String> resolveStartupRoot() {
    resolveStartupCalls++;
    return startupRootGate?.future ?? super.resolveStartupRoot();
  }

  @override
  Future<void> switchScanRoot(
    String? path, {
    bool startFullScan = true,
    bool validateBeforeSwitch = false,
  }) async {
    if (validateBeforeSwitch && path != null) {
      await validateScanRoot(path);
    }
    switchedRoot = path;
    switchStartedScan = startFullScan;
    if (path == null) {
      clearScanRoots();
    } else {
      setScanRoots([path]);
    }
  }

  @override
  Future<String> runScan() {
    runScanCalls++;
    return scanGate?.future ?? Future<String>.value('scan-id');
  }

  @override
  void cancelScan() {
    cancelCalls++;
    super.cancelScan();
  }

  @override
  Future<void> restoreCachedSnapshotIfNeeded() {
    restoreCalls++;
    return _restoreGate.future;
  }
}

Widget _shell(
  VolwardSession session,
  VolwardThemeSettings themeSettings,
  AppUpdater updater, {
  Future<String?> Function({required String confirmButtonText})?
      directoryPicker,
  StorageOverviewProvider storageOverviewProvider =
      const MethodChannelStorageOverviewProvider(),
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildVolwardTheme(brightness: Brightness.light),
    home: HomePage(
      session: session,
      themeSettings: themeSettings,
      updater: updater,
      directoryPicker: directoryPicker,
      storageOverviewProvider: storageOverviewProvider,
    ),
  );
}

Future<void> _pumpHome(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
  await tester.pump();
}

Future<void> _tapPanelBackground(WidgetTester tester) async {
  final rect = tester.getRect(find.byKey(StorageStewardHome.capacityKey));
  await tester.tapAt(rect.center);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int maxPumps = 10,
}) async {
  for (var i = 0; i < maxPumps && !done(); i++) {
    await tester.pump();
  }
}

void main() {
  testWidgets('launch starts on StorageStewardHome while restore hangs', (
    tester,
  ) async {
    final session = _Session(hangRestore: true)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-mode-no-session.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    final overviewProvider = _OverviewProvider();
    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        storageOverviewProvider: overviewProvider,
      ),
    );
    await tester.pump();

    expect(find.byType(StorageStewardHome), findsOneWidget);
    expect(find.byType(ScanColumnView), findsNothing);
    expect(overviewProvider.calls, 1);
    expect(overviewProvider.selectedPaths, ['/']);
  });

  testWidgets('panel with a valid root enters the column browser', (
    tester,
  ) async {
    final session = _Session(exposePreview: true)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-mode-no-session.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(tester, _shell(session, themeSettings, updater));
    await _tapPanelBackground(tester);
    await tester.pump();

    expect(find.byType(ScanColumnView), findsOneWidget);
    expect(find.byType(StorageStewardHome), findsNothing);
  });

  testWidgets('panel waits for startup root resolution before folder pick', (
    tester,
  ) async {
    final startupRoot = Completer<String>();
    var pickerCalls = 0;
    final session = _Session(exposePreview: true, startupRootGate: startupRoot)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-mode-no-session.json',
      );
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        directoryPicker: ({required confirmButtonText}) async {
          pickerCalls++;
          return null;
        },
      ),
    );
    await _tapPanelBackground(tester);
    await tester.pump();

    expect(pickerCalls, 0);
    expect(find.byType(StorageStewardHome), findsOneWidget);

    startupRoot.complete('/');
    await tester.pump();
    await tester.pump();

    expect(pickerCalls, 0);
    expect(find.byType(ScanColumnView), findsOneWidget);
    expect(find.byType(StorageStewardHome), findsNothing);
  });

  testWidgets('logo returns home and preserves the column chain', (
    tester,
  ) async {
    final session = _Session(exposePreview: true)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-mode-no-session.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(tester, _shell(session, themeSettings, updater));
    await _tapPanelBackground(tester);
    await tester.pump();

    await tester.tap(find.text('Documents'));
    await tester.pump();
    final selected = tester
        .widget<ScanColumnView>(find.byType(ScanColumnView))
        .selectionChain;
    expect(selected, isNotEmpty);

    await tester.tap(find.byKey(HomePage.logoKey));
    await tester.pump();
    expect(find.byType(StorageStewardHome), findsOneWidget);

    await _tapPanelBackground(tester);
    await tester.pump();
    final restored = tester
        .widget<ScanColumnView>(find.byType(ScanColumnView))
        .selectionChain;
    expect(
      restored.map((node) => node.path),
      selected.map((node) => node.path),
    );
  });

  testWidgets('home scan lifecycle preserves the column chain', (tester) async {
    final session = _Session(exposePreview: true)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-scan-preserves-chain.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(tester, _shell(session, themeSettings, updater));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(StorageStewardHome.browseKey));
    await _pumpUntil(
      tester,
      () => find.byType(ScanColumnView).evaluate().isNotEmpty,
    );

    await tester.tap(find.text('Documents'));
    await tester.pump();
    final selected = tester
        .widget<ScanColumnView>(find.byType(ScanColumnView))
        .selectionChain;
    expect(selected, isNotEmpty);

    await tester.tap(find.byKey(HomePage.logoKey));
    await tester.pump();
    expect(find.byType(StorageStewardHome), findsOneWidget);

    session.primeTransientScanStateForTest(
      scanning: true,
      openScanPorts: false,
    );
    session.notifyListeners();
    await tester.pump();

    session.primeTransientScanStateForTest(
      scanning: false,
      openScanPorts: false,
    );
    session.notifyListeners();
    await tester.pump();

    await tester.tap(find.byKey(StorageStewardHome.browseKey));
    await _pumpUntil(
      tester,
      () => find.byType(ScanColumnView).evaluate().isNotEmpty,
    );
    final restored = tester
        .widget<ScanColumnView>(find.byType(ScanColumnView))
        .selectionChain;
    expect(
      restored.map((node) => node.path),
      selected.map((node) => node.path),
    );
  });

  testWidgets('browse folder switch updates the home overview target', (
    tester,
  ) async {
    final session = _Session(exposePreview: true)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-browse-folder.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final overviewProvider = _OverviewProvider();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        directoryPicker: ({required confirmButtonText}) async => '/picked/',
        storageOverviewProvider: overviewProvider,
      ),
    );
    await tester.pump();
    await _tapPanelBackground(tester);
    await tester.pump();

    await tester.tap(find.byKey(HomePage.browseFolderActionKey));
    await tester.pump();

    expect(session.switchedRoot, '/picked/');
    expect(session.switchStartedScan, isTrue);
    expect(find.byType(StorageStewardHome), findsNothing);
    expect(overviewProvider.selectedPaths, ['/', '/picked']);

    await tester.tap(find.byKey(HomePage.logoKey));
    await tester.pump();
    final summary = tester
        .widget<StorageStewardHome>(find.byType(StorageStewardHome))
        .summary;
    expect(summary.selectedLocation!.path, '/picked');
  });

  testWidgets('results Home action updates the home overview target', (
    tester,
  ) async {
    final session = _Session(exposePreview: true)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-results-root.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final overviewProvider = _OverviewProvider();
    final homeRoot = _defaultHomeRoot();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        storageOverviewProvider: overviewProvider,
      ),
    );
    await tester.pump();
    await _tapPanelBackground(tester);
    await tester.pump();
    expect(find.byKey(HomePage.browseHomeActionKey), findsOneWidget);

    await tester.tap(find.byKey(HomePage.browseHomeActionKey));
    await tester.pump();

    expect(session.switchStartedScan, isTrue);
    expect(session.scanRoots, isEmpty);
    expect(find.byType(StorageStewardHome), findsNothing);
    expect(overviewProvider.selectedPaths, ['/', homeRoot]);

    await tester.tap(find.byKey(HomePage.logoKey));
    await tester.pump();
    final summary = tester
        .widget<StorageStewardHome>(find.byType(StorageStewardHome))
        .summary;
    expect(summary.selectedLocation!.path, homeRoot);
  });

  testWidgets('empty browse Home action updates the home overview target', (
    tester,
  ) async {
    final session = _Session()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-empty-root.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final overviewProvider = _OverviewProvider();
    final homeRoot = _defaultHomeRoot();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        storageOverviewProvider: overviewProvider,
      ),
    );
    await tester.pump();
    await _tapPanelBackground(tester);
    await tester.pump();
    expect(find.byKey(HomePage.browseHomeActionKey), findsOneWidget);

    await tester.tap(find.byKey(HomePage.browseHomeActionKey));
    await tester.pump();

    expect(session.switchStartedScan, isTrue);
    expect(session.scanRoots, isEmpty);
    expect(find.byType(StorageStewardHome), findsNothing);
    expect(overviewProvider.selectedPaths, ['/', homeRoot]);

    await tester.tap(find.byKey(HomePage.logoKey));
    await tester.pump();
    final summary = tester
        .widget<StorageStewardHome>(find.byType(StorageStewardHome))
        .summary;
    expect(summary.selectedLocation!.path, homeRoot);
  });

  testWidgets('successful home folder pick prepares root without scanning', (
    tester,
  ) async {
    final session = _Session()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-mode-no-session.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    final overviewProvider = _OverviewProvider();
    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        directoryPicker: ({required confirmButtonText}) async => '/picked',
        storageOverviewProvider: overviewProvider,
      ),
    );
    await tester.tap(find.byKey(StorageStewardHome.chooseFolderKey));
    await tester.pump();

    expect(session.switchedRoot, '/picked');
    expect(session.switchStartedScan, isFalse);
    expect(session.runScanCalls, 0);
    expect(overviewProvider.selectedPaths, ['/', '/picked']);
    expect(find.byType(StorageStewardHome), findsOneWidget);
  });

  testWidgets('custom target hides prior capacity while overview reloads', (
    tester,
  ) async {
    final session = _Session()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-overview-transition.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final overviewProvider = _QueuedOverviewProvider();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        directoryPicker: ({required confirmButtonText}) async => '/work/link',
        storageOverviewProvider: overviewProvider,
      ),
    );
    expect(overviewProvider.requests, hasLength(1));

    overviewProvider.requests.single.complete(_overviewData('Old Disk'));
    await tester.pump();
    expect(
      tester
          .widget<StorageStewardHome>(find.byType(StorageStewardHome))
          .summary
          .selectedVolume
          ?.name,
      'Old Disk',
    );

    await tester.tap(find.byKey(StorageStewardHome.chooseFolderKey));
    await tester.pump();
    await _pumpUntil(tester, () => overviewProvider.requests.length == 2);

    expect(session.switchedRoot, '/work/link');
    final loadingSummary = tester
        .widget<StorageStewardHome>(find.byType(StorageStewardHome))
        .summary;
    expect(loadingSummary.selectedLocation!.path, '/work/link');
    expect(loadingSummary.overview.loading, isTrue);
    expect(loadingSummary.selectedVolume, isNull);
    expect(overviewProvider.selectedPaths, ['/', '/work/link']);
    expect(find.text('600 B'), findsNothing);

    overviewProvider.requests.last.complete(_overviewData('New Disk'));
    await tester.pump();
    expect(
      tester
          .widget<StorageStewardHome>(find.byType(StorageStewardHome))
          .summary
          .selectedVolume
          ?.name,
      'New Disk',
    );
  });

  testWidgets('failed home folder validation preserves the current overview', (
    tester,
  ) async {
    final session = _Session()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-invalid-folder.json',
      )
      ..rootExistsForTest = ((path) => path != '/bad');
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final overviewProvider = _OverviewProvider();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        directoryPicker: ({required confirmButtonText}) async => '/bad',
        storageOverviewProvider: overviewProvider,
      ),
    );

    await tester.tap(find.byKey(StorageStewardHome.chooseFolderKey));
    await _pumpUntil(
      tester,
      () => find.textContaining('Scan failed').evaluate().isNotEmpty,
    );

    final summary = tester
        .widget<StorageStewardHome>(find.byType(StorageStewardHome))
        .summary;
    expect(session.scanRoots, ['/']);
    expect(session.switchedRoot, isNull);
    expect(summary.selectedLocation!.path, '/');
    expect(overviewProvider.selectedPaths, ['/']);
    expect(find.textContaining('/bad'), findsOneWidget);
  });

  testWidgets('cancelled folder pick leaves home visible', (tester) async {
    var calls = 0;
    final session = _Session()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-mode-no-session.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        directoryPicker: ({required confirmButtonText}) async {
          calls++;
          return null;
        },
      ),
    );
    await tester.tap(find.byKey(StorageStewardHome.chooseFolderKey));
    await tester.pump();

    expect(calls, 1);
    expect(session.switchedRoot, isNull);
    expect(find.byType(StorageStewardHome), findsOneWidget);
  });

  testWidgets('invalid startup root routes panel activation to folder pick', (
    tester,
  ) async {
    final startupRoot = Completer<String>();
    var calls = 0;
    final session =
        _Session(setInitialRoot: false, startupRootGate: startupRoot)
          ..sessionStateFileForTest = File(
            '${Directory.systemTemp.path}/volward-home-mode-no-session.json',
          )
          ..defaultRootForTest = (() => '')
          ..rootExistsForTest = ((_) => false);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final overviewProvider = _OverviewProvider();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        directoryPicker: ({required confirmButtonText}) async {
          calls++;
          return null;
        },
        storageOverviewProvider: overviewProvider,
      ),
    );
    startupRoot.complete('');
    await tester.pump();
    await tester.pump();

    final home = tester.widget<StorageStewardHome>(
      find.byType(StorageStewardHome),
    );
    expect(overviewProvider.calls, 0);
    expect(home.summary.selectedLocation, isNull);
    expect(
      tester.widget<Text>(find.byKey(StorageStewardHome.capacityPathKey)).data,
      '—',
    );
    expect(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('storage-target-');
      }),
      findsNothing,
    );
    expect(find.byTooltip(''), findsNothing);

    await _tapPanelBackground(tester);
    await _pumpUntil(tester, () => calls > 0);

    expect(calls, 1);
    expect(find.byType(StorageStewardHome), findsOneWidget);
  });

  testWidgets('target selection prepares preview without full scan', (
    tester,
  ) async {
    final session = _Session()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-overview.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final overviewProvider = _OverviewProvider();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        storageOverviewProvider: overviewProvider,
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('storage-target-downloads')),
    );
    await tester.pump();

    expect(session.switchedRoot, '/home/Downloads');
    expect(session.switchStartedScan, isFalse);
    expect(session.runScanCalls, 0);
    expect(overviewProvider.selectedPaths, ['/', '/home/Downloads']);
  });

  testWidgets('home scan stays disabled without snapshot file capability', (
    tester,
  ) async {
    final session = _Session(snapshotFileApi: false)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-no-snapshot-api.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        storageOverviewProvider: _OverviewProvider(),
      ),
    );
    await tester.pump();

    final home = tester.widget<StorageStewardHome>(
      find.byType(StorageStewardHome),
    );
    expect(home.onScan, isNull);
    await tester.tap(
      find.byKey(StorageStewardHome.scanActionKey),
      warnIfMissed: false,
    );
    expect(session.runScanCalls, 0);
  });

  testWidgets('home scan stays disabled until startup root resolves', (
    tester,
  ) async {
    final startupRoot = Completer<String>();
    final session = _Session(startupRootGate: startupRoot)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-unresolved-root.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        storageOverviewProvider: _OverviewProvider(),
      ),
    );

    expect(
      tester.widget<StorageStewardHome>(find.byType(StorageStewardHome)).onScan,
      isNull,
    );
    await tester.tap(
      find.byKey(StorageStewardHome.scanActionKey),
      warnIfMissed: false,
    );
    expect(session.runScanCalls, 0);

    startupRoot.complete('/');
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<StorageStewardHome>(find.byType(StorageStewardHome)).onScan,
      isNotNull,
    );
  });

  testWidgets('preview preparation disables scan and stale callback', (
    tester,
  ) async {
    final session = _Session()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-preview-pending.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        storageOverviewProvider: _OverviewProvider(),
      ),
    );
    final staleCallback = tester
        .widget<StorageStewardHome>(find.byType(StorageStewardHome))
        .onScan!;

    session.setPreviewLoading(true);
    await tester.pump();
    expect(
      tester.widget<StorageStewardHome>(find.byType(StorageStewardHome)).onScan,
      isNull,
    );
    staleCallback();
    await tester.pump();
    expect(session.runScanCalls, 0);

    session.setPreviewLoading(false);
    await tester.pump();
    expect(
      tester.widget<StorageStewardHome>(find.byType(StorageStewardHome)).onScan,
      isNotNull,
    );
  });

  testWidgets('home scan progress follows the localized session phase', (
    tester,
  ) async {
    final session = _Session()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-live-progress.json',
      )
      ..rootExistsForTest = ((_) => true)
      ..primeTransientScanStateForTest(
        progress: const {'phase': 'Walking', 'paths_seen': 10},
        scanning: true,
        openScanPorts: false,
      );
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        storageOverviewProvider: _OverviewProvider(),
      ),
    );

    expect(find.text('Scanning files…'), findsOneWidget);
    final initialProgress = tester
        .widget<LinearProgressIndicator>(
          find.byKey(const ValueKey('storage-scan-progress')),
        )
        .value!;

    session.updateScanProgressForTest(
      const {'phase': 'SavingResults', 'paths_seen': 20},
    );
    await tester.pump();

    expect(find.text('Scanning files…'), findsNothing);
    expect(find.text('Saving results…'), findsOneWidget);
    final updatedProgress = tester
        .widget<LinearProgressIndicator>(
          find.byKey(const ValueKey('storage-scan-progress')),
        )
        .value!;
    expect(updatedProgress, greaterThan(initialProgress));
  });

  testWidgets('overview provider replacement rejects late old response', (
    tester,
  ) async {
    final session = _Session()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-provider-replace.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final oldProvider = _QueuedOverviewProvider();
    final newProvider = _OverviewProvider(volumeName: 'New Disk');
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        storageOverviewProvider: oldProvider,
      ),
    );
    await tester.pump();
    expect(oldProvider.requests, hasLength(1));

    await tester.pumpWidget(
      _shell(
        session,
        themeSettings,
        updater,
        storageOverviewProvider: newProvider,
      ),
    );
    await tester.pump();
    expect(newProvider.selectedPaths, ['/']);
    expect(
      tester
          .widget<StorageStewardHome>(find.byType(StorageStewardHome))
          .summary
          .selectedVolume
          ?.name,
      'New Disk',
    );

    oldProvider.requests.single.complete(_overviewData('Old Disk'));
    await tester.pump();
    expect(
      tester
          .widget<StorageStewardHome>(find.byType(StorageStewardHome))
          .summary
          .selectedVolume
          ?.name,
      'New Disk',
    );
  });

  testWidgets('blank replacement session restores persisted startup root', (
    tester,
  ) async {
    final oldSession = _Session()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-before-persisted.json',
      )
      ..rootExistsForTest = ((_) => true);
    final newSession = _Session(
      setInitialRoot: false,
      restoredRootOnLoad: '/persisted-root',
    )
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-persisted-replacement.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final overviewProvider = _OverviewProvider();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        oldSession,
        themeSettings,
        updater,
        storageOverviewProvider: overviewProvider,
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      _shell(
        newSession,
        themeSettings,
        updater,
        storageOverviewProvider: overviewProvider,
      ),
    );
    await _pumpUntil(
      tester,
      () =>
          tester
              .widget<StorageStewardHome>(find.byType(StorageStewardHome))
              .summary
              .selectedLocation!
              .path ==
          '/persisted-root',
    );

    expect(newSession.loadSessionCalls, 1);
    expect(newSession.resolveStartupCalls, 1);
    expect(newSession.previewCalls, 1);
    expect(newSession.restoreCalls, 1);
    expect(newSession.scanRoots, ['/persisted-root']);
    expect(overviewProvider.selectedPaths, ['/', '/persisted-root']);
    expect(
      tester
          .widget<StorageStewardHome>(find.byType(StorageStewardHome))
          .summary
          .selectedLocation!
          .path,
      '/persisted-root',
    );
  });

  testWidgets('replacement invalidates pending old startup lifecycle', (
    tester,
  ) async {
    final oldRoot = Completer<String>();
    final oldSession = _Session(startupRootGate: oldRoot)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-pending-old-startup.json',
      )
      ..rootExistsForTest = ((_) => true);
    final newSession = _Session(setInitialRoot: false)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-default-replacement.json',
      )
      ..defaultRootForTest = (() => '/new-default-root')
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final overviewProvider = _OverviewProvider();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        oldSession,
        themeSettings,
        updater,
        storageOverviewProvider: overviewProvider,
      ),
    );
    await _pumpUntil(tester, () => oldSession.resolveStartupCalls == 1);
    expect(overviewProvider.selectedPaths, isEmpty);

    await tester.pumpWidget(
      _shell(
        newSession,
        themeSettings,
        updater,
        storageOverviewProvider: overviewProvider,
      ),
    );
    await _pumpUntil(tester, () => newSession.restoreCalls == 1);

    expect(newSession.loadSessionCalls, 1);
    expect(newSession.resolveStartupCalls, 1);
    expect(newSession.previewCalls, 1);
    expect(newSession.restoreCalls, 1);
    expect(overviewProvider.selectedPaths, ['/new-default-root']);

    oldRoot.complete('/old-late-root');
    await tester.pump();
    await tester.pump();

    expect(oldSession.previewCalls, 0);
    expect(oldSession.restoreCalls, 0);
    expect(overviewProvider.selectedPaths, ['/new-default-root']);
    expect(
      tester
          .widget<StorageStewardHome>(find.byType(StorageStewardHome))
          .summary
          .selectedLocation!
          .path,
      '/new-default-root',
    );
  });

  testWidgets('session replacement migrates listener and ignores old scan', (
    tester,
  ) async {
    final oldScan = Completer<String>();
    final oldSession = _Session(scanGate: oldScan)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-old-session.json',
      )
      ..rootExistsForTest = ((_) => true);
    final newSession = _Session()
      ..setScanRoots(['/replacement'])
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-new-session.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final overviewProvider = _OverviewProvider();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        oldSession,
        themeSettings,
        updater,
        storageOverviewProvider: overviewProvider,
      ),
    );
    await tester.pump();
    final oldCallback = tester
        .widget<StorageStewardHome>(find.byType(StorageStewardHome))
        .onScan!;
    oldCallback();
    await tester.pump();
    expect(oldSession.runScanCalls, 1);

    await tester.pumpWidget(
      _shell(
        newSession,
        themeSettings,
        updater,
        storageOverviewProvider: overviewProvider,
      ),
    );
    await _pumpUntil(
      tester,
      () => overviewProvider.selectedPaths.contains('/replacement'),
    );

    expect(oldSession.listenerAdds, 1);
    expect(oldSession.listenerRemoves, 1);
    expect(newSession.listenerAdds, 1);
    expect(overviewProvider.selectedPaths, ['/', '/replacement']);
    expect(
      tester
          .widget<StorageStewardHome>(find.byType(StorageStewardHome))
          .summary
          .selectedLocation!
          .path,
      '/replacement',
    );
    oldCallback();
    expect(newSession.runScanCalls, 0);

    oldScan.complete('old-scan-id');
    await tester.pump();
    await _tapPanelBackground(tester);
    await tester.pump();
    expect(find.textContaining('old-scan-id'), findsNothing);
    expect(newSession.runScanCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(newSession.listenerRemoves, 1);
  });

  testWidgets('pending scan start ignores repeated callbacks', (tester) async {
    final scanGate = Completer<String>();
    final session = _Session(scanGate: scanGate)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-pending-scan.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        storageOverviewProvider: _OverviewProvider(),
      ),
    );
    await tester.pump();

    final oldCallback = tester
        .widget<StorageStewardHome>(find.byType(StorageStewardHome))
        .onScan!;
    oldCallback();
    oldCallback();
    await tester.pump();

    expect(session.runScanCalls, 1);
    expect(
      tester.widget<StorageStewardHome>(find.byType(StorageStewardHome)).onScan,
      isNull,
    );
    oldCallback();
    expect(session.runScanCalls, 1);

    scanGate.complete('delayed-scan-id');
    await tester.pump();
    expect(
      tester.widget<StorageStewardHome>(find.byType(StorageStewardHome)).onScan,
      isNotNull,
    );
    oldCallback();
    expect(session.runScanCalls, 1);
  });

  testWidgets('scan and cancel controls use existing session lifecycle', (
    tester,
  ) async {
    final session = _Session()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-overview.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        storageOverviewProvider: _OverviewProvider(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(StorageStewardHome.scanActionKey));
    await tester.pump();
    expect(session.runScanCalls, 1);

    session.primeTransientScanStateForTest(
      scanning: true,
      openScanPorts: false,
    );
    session.notifyListeners();
    await tester.pump();
    await tester.tap(find.byKey(StorageStewardHome.scanActionKey));
    expect(session.cancelCalls, 1);
  });
}
