import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_analysis_gateway.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/ai_settings_store.dart';
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
import 'package:volward/widgets/scan_filter_bar.dart';
import 'package:volward/widgets/home/largest_items_panel.dart';
import 'package:volward/widgets/ai_analysis_workspace.dart';
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
        id: 'desktop',
        name: 'Desktop',
        path: '/home/Desktop',
        kind: StorageLocationKind.desktop,
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

class _HomeAiGateway implements AiAnalysisGateway {
  _HomeAiGateway({Future<String?>? candidates})
    : _candidates = candidates ?? Future<String?>.value(_emptyCandidates);

  static const _emptyCandidates = '''
{
  "pre_classified": [],
  "unknown_candidates": [],
  "estimated_input_tokens": 0,
  "has_existing_result": false,
  "truncated": false,
  "candidates_total_before_cap": 0,
  "result_cache_key": "cache-key",
  "root_path": "/"
}
''';

  final Future<String?> _candidates;
  AiMode mode = AiMode.off;
  AiProvider? provider;
  final deleteCalls =
      <({List<String> targets, bool dryRun, bool rescanAfterDelete})>[];
  final deleteResponses = <Future<Map<String, dynamic>>>[];
  final snapshotIds = <String?>[];
  int saveCalls = 0;

  @override
  Future<AiMode> getMode() async => mode;

  @override
  Future<AiProvider?> resolveProvider() async => provider;

  @override
  Future<bool> isPrivacyAccepted() async => true;

  @override
  Future<void> setPrivacyAccepted(bool value) async {}

  @override
  Future<String?> buildCandidates(String snapshotId) => _candidates;

  @override
  String? loadResult(String key) => null;

  @override
  bool saveResult(String snapshotId, String resultJson) {
    saveCalls++;
    return true;
  }

  @override
  Future<Map<String, dynamic>> deleteEntries(
    List<String> targets, {
    String? snapshotId,
    bool dryRun = false,
    bool rescanAfterDelete = false,
  }) async {
    snapshotIds.add(snapshotId);
    deleteCalls.add((
      targets: List.of(targets),
      dryRun: dryRun,
      rescanAfterDelete: rescanAfterDelete,
    ));
    if (deleteResponses.isEmpty) return const {};
    return deleteResponses.removeAt(0);
  }
}

class _HomeResultProvider implements AiProvider {
  _HomeResultProvider(this.analysis);

  final Future<List<AiVerdict>> analysis;

  @override
  Future<List<AiVerdict>> analyze(List<AiCandidate> candidates) => analysis;

  @override
  Future<AiQuotaInfo?> queryQuota() async => null;
}

const _homeDeleteCandidates = '''
{
  "pre_classified": [],
  "unknown_candidates": [
    {"path": "/tmp/home-cache", "size_bytes": 100, "is_dir": false}
  ],
  "estimated_input_tokens": 8,
  "has_existing_result": false,
  "truncated": false,
  "candidates_total_before_cap": 1,
  "result_cache_key": "home-cache-key",
  "root_path": "/"
}
''';

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
    this.aiSessionApi = false,
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
  final bool aiSessionApi;
  final Completer<String>? scanGate;
  bool previewLoading = false;
  bool postDeleteRefreshPendingForTest = false;
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

  ScanSnapshotState? snapshotForTest;

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
      snapshotForTest ?? (exposePreview ? _previewSnapshot : null);

  @override
  bool get restoringSnapshot => exposePreview;

  @override
  bool get hasSnapshotFileApi => snapshotFileApi;

  @override
  bool get hasAiSessionApi => aiSessionApi;

  @override
  bool get targetPreviewLoading => previewLoading;

  @override
  bool get postDeleteRefreshPending => postDeleteRefreshPendingForTest;

  void setPreviewLoading(bool value) {
    previewLoading = value;
    notifyListeners();
  }

  void setPostDeleteRefreshPending(bool value) {
    postDeleteRefreshPendingForTest = value;
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

ScanSnapshotState _completedSnapshot({
  String snapshotId = 'cached-scan',
  String rootPath = '/',
  int scannedAtMs = 1723766400000,
}) {
  return ScanSnapshotState(
    snapshotId: snapshotId,
    scannedAtMs: scannedAtMs,
    stats: const {'scan_state': 'Done', 'files_seen': 3},
    reclaimableEstimateBytes: 256,
    tree: ScanTreeNode(
      name: rootPath == '/' ? '/' : rootPath.split('/').last,
      path: rootPath,
      isDirectory: true,
      sizeBytes: 4096,
    ),
    entryCount: 3,
    categoryCounts: const {'Cache': 1, 'Temp': 1},
    deletableCategoryCounts: const {},
    deletableCount: 0,
    extraFields: const {},
  );
}

class _RestoringSession extends _Session {
  _RestoringSession() : super(exposePreview: true);

  @override
  Future<void> restoreCachedSnapshotIfNeeded() async {
    restoreCalls++;
    await Future<void>.delayed(Duration.zero);
    snapshotForTest = _completedSnapshot();
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
  AiAnalysisGateway aiAnalysisGateway = const ProductionAiAnalysisGateway(),
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
      aiAnalysisGateway: aiAnalysisGateway,
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

Future<void> _openLastScan(WidgetTester tester) async {
  await tester.tap(find.byKey(StorageStewardHome.browseKey));
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

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for the expected widget');
}

void main() {
  testWidgets('completed supported scan exposes home AI action', (
    tester,
  ) async {
    final themeSettings = VolwardThemeSettings();
    await tester.runAsync(themeSettings.load);
    final updater = AppUpdater.test();
    final session = _Session(aiSessionApi: true)
      ..snapshotForTest = _completedSnapshot();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(tester, _shell(session, themeSettings, updater));

    expect(find.byKey(StorageStewardHome.aiActionKey), findsOneWidget);
  });

  testWidgets('unsupported completed scan hides home AI action', (
    tester,
  ) async {
    final themeSettings = VolwardThemeSettings();
    await tester.runAsync(themeSettings.load);
    final updater = AppUpdater.test();
    final session = _Session()..snapshotForTest = _completedSnapshot();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(tester, _shell(session, themeSettings, updater));

    expect(find.byKey(StorageStewardHome.aiActionKey), findsNothing);
  });

  testWidgets('preview snapshot hides home AI action', (tester) async {
    final themeSettings = VolwardThemeSettings();
    await tester.runAsync(themeSettings.load);
    final updater = AppUpdater.test();
    final session = _Session(aiSessionApi: true)
      ..snapshotForTest = _completedSnapshot(snapshotId: 'preview-home');
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(tester, _shell(session, themeSettings, updater));

    expect(find.byKey(StorageStewardHome.aiActionKey), findsNothing);
  });

  testWidgets('mismatched completed scan hides home AI action', (tester) async {
    final themeSettings = VolwardThemeSettings();
    await tester.runAsync(themeSettings.load);
    final updater = AppUpdater.test();
    final session = _Session(aiSessionApi: true)
      ..snapshotForTest = _completedSnapshot(rootPath: '/Users/test/Documents');
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(tester, _shell(session, themeSettings, updater));

    expect(find.byKey(StorageStewardHome.aiActionKey), findsNothing);
  });

  testWidgets('home AI action opens inline workspace and returns to overview', (
    tester,
  ) async {
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final session = _Session(aiSessionApi: true)
      ..snapshotForTest = _completedSnapshot();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        aiAnalysisGateway: _HomeAiGateway(),
      ),
    );
    await tester.tap(find.byKey(StorageStewardHome.aiActionKey));
    await tester.pump();

    expect(find.byKey(AiAnalysisWorkspace.workspaceKey), findsOneWidget);
    expect(find.byKey(StorageStewardHome.targetsKey), findsOneWidget);
    expect(find.byKey(StorageStewardHome.capacityKey), findsNothing);

    await _pumpUntilFound(tester, find.byKey(AiAnalysisWorkspace.backKey));
    await tester.tap(find.byKey(AiAnalysisWorkspace.backKey));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(StorageStewardHome.capacityKey), findsOneWidget);
    expect(find.byKey(LargestItemsPanel.panelKey), findsOneWidget);
    expect(find.byKey(StorageStewardHome.browseCardKey), findsOneWidget);
    expect(
      Focus.of(
        tester.element(find.byKey(StorageStewardHome.aiActionKey)),
      ).hasFocus,
      isTrue,
    );
  });

  testWidgets('home deletion locks overview controls until success', (
    tester,
  ) async {
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final deleteGate = Completer<Map<String, dynamic>>();
    final gateway =
        _HomeAiGateway(candidates: Future<String?>.value(_homeDeleteCandidates))
          ..mode = AiMode.byok
          ..provider = _HomeResultProvider(
            Future.value(const [
              AiVerdict(
                path: '/tmp/home-cache',
                verdict: 'safe_to_remove',
                confidence: 'high',
                reason: 'Build cache',
              ),
            ]),
          )
          ..deleteResponses.add(
            Future.value({
              'deleted_count': 1,
              'freed_bytes': 100,
              'failed_paths': const [],
            }),
          )
          ..deleteResponses.add(deleteGate.future);
    final session = _Session(aiSessionApi: true)
      ..snapshotForTest = _completedSnapshot();
    var pickerCalls = 0;
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        storageOverviewProvider: _OverviewProvider(),
        aiAnalysisGateway: gateway,
        directoryPicker: ({required confirmButtonText}) async {
          pickerCalls++;
          return '/picked';
        },
      ),
    );
    await tester.tap(find.byKey(StorageStewardHome.aiActionKey));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('Start AI Analysis'));
    await tester.tap(find.text('Start AI Analysis'));
    await tester.pumpAndSettle();
    expect(find.byKey(AiAnalysisWorkspace.deleteKey), findsOneWidget);

    await tester.tap(find.byKey(AiAnalysisWorkspace.deleteKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(gateway.deleteCalls.last.dryRun, isFalse);

    await tester.tap(find.byKey(const ValueKey('storage-target-downloads')));
    await tester.tap(find.byKey(StorageStewardHome.chooseFolderKey));
    await tester.tap(find.byKey(AiAnalysisWorkspace.backKey));
    await tester.pump();
    expect(session.switchedRoot, isNull);
    expect(pickerCalls, 0);
    expect(find.byKey(AiAnalysisWorkspace.workspaceKey), findsOneWidget);
    expect(gateway.snapshotIds, ['cached-scan', 'cached-scan']);

    session.setPostDeleteRefreshPending(true);
    deleteGate.complete({
      'deleted_count': 1,
      'freed_bytes': 100,
      'failed_paths': const [],
    });
    await tester.pumpAndSettle();
    expect(find.byKey(AiAnalysisWorkspace.workspaceKey), findsNothing);
    expect(find.byKey(StorageStewardHome.aiActionKey), findsNothing);
    session.setPostDeleteRefreshPending(false);
    await tester.pump();
    expect(find.byKey(StorageStewardHome.aiActionKey), findsOneWidget);
    expect(find.byKey(StorageStewardHome.capacityKey), findsOneWidget);
    expect(find.byKey(StorageStewardHome.browseCardKey), findsOneWidget);
  });

  testWidgets('late analysis completion cannot restore exited workspace', (
    tester,
  ) async {
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final analysisGate = Completer<List<AiVerdict>>();
    final gateway =
        _HomeAiGateway(candidates: Future<String?>.value(_homeDeleteCandidates))
          ..mode = AiMode.byok
          ..provider = _HomeResultProvider(analysisGate.future);
    final session = _Session(aiSessionApi: true)
      ..snapshotForTest = _completedSnapshot()
      ..rootExistsForTest = ((_) => true);
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
        aiAnalysisGateway: gateway,
      ),
    );
    await tester.tap(find.byKey(StorageStewardHome.aiActionKey));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('Start AI Analysis'));
    await tester.tap(find.text('Start AI Analysis'));
    await tester.pump();
    expect(find.text('Analyzing'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('storage-target-downloads')));
    await tester.pumpAndSettle();
    expect(session.switchedRoot, '/home/Downloads');
    expect(find.byKey(AiAnalysisWorkspace.workspaceKey), findsNothing);

    analysisGate.complete(const [
      AiVerdict(
        path: '/tmp/home-cache',
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: 'Build cache',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.byKey(AiAnalysisWorkspace.workspaceKey), findsNothing);
    expect(gateway.saveCalls, 0);
    expect(
      tester
          .widget<StorageStewardHome>(find.byType(StorageStewardHome))
          .summary
          .selectedLocation
          ?.path,
      '/home/Downloads',
    );
  });

  testWidgets('target switch exits home AI without confirmation', (
    tester,
  ) async {
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final candidateGate = Completer<String?>();
    final session = _Session(aiSessionApi: true)
      ..snapshotForTest = _completedSnapshot()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-ai-target-switch.json',
      )
      ..rootExistsForTest = ((_) => true);
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(
      tester,
      _shell(
        session,
        themeSettings,
        updater,
        storageOverviewProvider: _OverviewProvider(),
        aiAnalysisGateway: _HomeAiGateway(candidates: candidateGate.future),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(StorageStewardHome.aiActionKey));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('storage-target-downloads')));
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(AiAnalysisWorkspace.workspaceKey), findsNothing);
    expect(session.switchedRoot, '/home/Downloads');
    expect(session.switchStartedScan, isFalse);

    candidateGate.complete(_HomeAiGateway._emptyCandidates);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(AiAnalysisWorkspace.workspaceKey), findsNothing);
  });

  testWidgets('column browser has no AI entry', (tester) async {
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final session = _Session(exposePreview: true, aiSessionApi: true)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-ai-browser.json',
      )
      ..rootExistsForTest = ((_) => true);
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(tester, _shell(session, themeSettings, updater));
    await tester.pump();
    await tester.ensureVisible(find.byKey(StorageStewardHome.browseKey));
    await _openLastScan(tester);
    await tester.pump();
    session.snapshotForTest = _completedSnapshot();
    session.setPreviewLoading(false);
    await tester.pump();

    expect(find.byType(StorageStewardHome), findsNothing);
    expect(find.byKey(StorageStewardHome.aiActionKey), findsNothing);
    expect(find.text('AI Analysis'), findsNothing);
  });

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

  testWidgets('home last scan updates after cached snapshot restore', (
    tester,
  ) async {
    final session = _RestoringSession()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-restore-summary.json',
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

    await tester.pumpAndSettle();

    expect(session.restoreCalls, 1);
    expect(find.text('256 B reclaimable'), findsOneWidget);
    expect(find.text('4 KB total'), findsOneWidget);
    expect(find.textContaining('Last scan'), findsOneWidget);
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
    await _openLastScan(tester);
    await tester.pump();

    expect(find.byType(ScanColumnView), findsOneWidget);
    expect(find.byType(StorageStewardHome), findsNothing);
  });

  testWidgets('column browser shares its outer edges with the chrome above', (
    tester,
  ) async {
    final session = _Session(exposePreview: true)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-mode-browser-edges.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await _pumpHome(tester, _shell(session, themeSettings, updater));
    await _openLastScan(tester);
    await tester.pump();

    // Pin the desktop width this alignment test depends on rather than
    // trusting _pumpHome to keep it.
    expect(tester.view.physicalSize.width / tester.view.devicePixelRatio, 1280);

    final chrome = tester.getRect(find.byType(ScanFilterBar));
    final browser = tester.getRect(find.byType(ScanColumnView));

    expect(browser.left, chrome.left);
    expect(browser.right, chrome.right);

    // With the outer edges shared, the first column's icon lines up with the
    // `All` chip's outer edge because both carry the same AppleSpacing.sm
    // container inset.
    final chip = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_FilterChip',
    );
    // Scoped to the browser: the preview card below also draws Icons.folder,
    // and at this width its icon lands on the same x, so an unscoped finder
    // would still pass with an empty browser.
    final icon = find.descendant(
      of: find.byType(ScanColumnView),
      matching: find.byIcon(Icons.folder),
    );
    expect(tester.any(chip), isTrue);
    expect(tester.any(icon), isTrue);
    expect(tester.getRect(icon.first).left, tester.getRect(chip.first).left);
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
    await _openLastScan(tester);
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
    await _openLastScan(tester);
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

    await _openLastScan(tester);
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
    await _openLastScan(tester);
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
    await _openLastScan(tester);
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
    await _openLastScan(tester);
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

  testWidgets('recent custom folders stay reachable from the sidebar menu', (
    tester,
  ) async {
    final picked = ['/work/archive', '/work/photos'];
    final session = _Session(setInitialRoot: false)
      ..setScanRoots(['/home'])
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-pin-custom.json',
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
        directoryPicker: ({required confirmButtonText}) async =>
            picked.removeAt(0),
        storageOverviewProvider: _OverviewProvider(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(StorageStewardHome.chooseFolderKey));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('storage-target-custom:/work/archive')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(StorageStewardHome.chooseFolderKey));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('storage-target-custom:/work/photos')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('storage-target-custom:/work/archive')),
      findsNothing,
    );
    expect(find.byKey(StorageStewardHome.recentFoldersKey), findsNothing);
    expect(
      find.byKey(const ValueKey('storage-target-menu-custom:/work/photos')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('storage-target-home')));
    await tester.pump();
    await tester.pump();

    expect(
      tester
          .widget<StorageStewardHome>(find.byType(StorageStewardHome))
          .summary
          .selectedLocation
          ?.path,
      '/home',
    );
    expect(
      find.byKey(const ValueKey('storage-target-custom:/work/archive')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('storage-target-custom:/work/photos')),
      findsNothing,
    );
    expect(find.byKey(StorageStewardHome.recentFoldersKey), findsOneWidget);

    await tester.tap(find.byKey(StorageStewardHome.recentFoldersKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('storage-recent-folder-option-custom:/work/archive'),
      ),
    );
    await tester.pumpAndSettle();

    expect(session.switchedRoot, '/work/archive');
    expect(
      tester
          .widget<StorageStewardHome>(find.byType(StorageStewardHome))
          .summary
          .selectedLocation
          ?.path,
      '/work/archive',
    );
    expect(session.recentCustomRoots, ['/work/archive', '/work/photos']);
    expect(find.byKey(StorageStewardHome.recentFoldersKey), findsNothing);
    expect(
      find.byKey(const ValueKey('storage-target-menu-custom:/work/archive')),
      findsOneWidget,
    );
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
    await _pumpUntil(
      tester,
      () =>
          tester
              .widget<StorageStewardHome>(find.byType(StorageStewardHome))
              .summary
              .selectedVolume
              ?.name ==
          'New Disk',
    );
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

    await _openLastScan(tester);
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

    await tester.tap(find.byKey(const ValueKey('storage-target-downloads')));
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

    session.updateScanProgressForTest(const {
      'phase': 'SavingResults',
      'paths_seen': 20,
    });
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
    final newSession =
        _Session(setInitialRoot: false, restoredRootOnLoad: '/persisted-root')
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
    await _openLastScan(tester);
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

  testWidgets('cancelling an in-flight scan re-enables start scan', (
    tester,
  ) async {
    final scanGate = Completer<String>();
    final session = _Session(scanGate: scanGate)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-cancel-rescan.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);
    addTearDown(() {
      if (!scanGate.isCompleted) {
        scanGate.completeError(ScanCancelledException());
      }
    });

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
    expect(
      tester.widget<StorageStewardHome>(find.byType(StorageStewardHome)).onScan,
      isNull,
    );

    session.primeTransientScanStateForTest(
      scanning: true,
      openScanPorts: false,
    );
    session.notifyListeners();
    await tester.pump();
    await tester.tap(find.byKey(StorageStewardHome.scanActionKey));
    await tester.pump();
    expect(session.cancelCalls, 1);

    final home = tester.widget<StorageStewardHome>(
      find.byType(StorageStewardHome),
    );
    expect(home.onScan, isNotNull);
    expect(home.onCancelScan, isNull);

    await tester.tap(find.byKey(StorageStewardHome.scanActionKey));
    await tester.pump();
    expect(session.runScanCalls, 2);
  });

  testWidgets('home category row opens browse with that type selected', (
    tester,
  ) async {
    final session = _Session()
      ..snapshotForTest = ScanSnapshotState.fromIndexSummary({
        'snapshot_id': 'done-cache',
        'root_path': '/',
        'root_size_bytes': 80,
        'scanned_at_ms': 1,
        'reclaimable_estimate_bytes': 8,
        'entry_count': 4,
        'category_counts': {'Cache': 4},
        'deletable_count': 0,
        'scan_state': 'Done',
      })
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-category-browse.json',
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
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('storage-category-Cache')));
    await tester.pump();

    expect(find.byType(StorageStewardHome), findsNothing);
    expect(find.byType(ScanFilterBar), findsOneWidget);
    expect(
      tester.widget<ScanFilterBar>(find.byType(ScanFilterBar)).categoryFilter,
      'Cache',
    );
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Cache'), findsOneWidget);
    expect(find.text('Temp'), findsNothing);
    expect(find.text('Media'), findsNothing);
    expect(find.text('System'), findsNothing);
  });

  testWidgets('tapping a largest-items row opens browse at the item', (
    tester,
  ) async {
    final session = _Session()
      ..snapshotForTest = ScanSnapshotState(
        snapshotId: 'scan-with-children',
        scannedAtMs: 1723766400000,
        stats: const {'scan_state': 'Done', 'files_seen': 5},
        reclaimableEstimateBytes: 512,
        tree: ScanTreeNode(
          name: '/',
          path: '/',
          isDirectory: true,
          sizeBytes: 10240,
          children: [
            ScanTreeNode(
              name: 'big',
              path: '/big',
              isDirectory: true,
              sizeBytes: 8192,
            ),
          ],
        ),
        entryCount: 5,
        categoryCounts: const {'Cache': 2, 'Temp': 1},
        deletableCategoryCounts: const {},
        deletableCount: 0,
        extraFields: const {},
      )
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-largest-items-tap.json',
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

    await tester.tap(find.byKey(LargestItemsPanel.rowKey('/big')));
    await tester.pumpAndSettle();

    expect(find.byKey(StorageStewardHome.panelKey), findsNothing);
  });
}
