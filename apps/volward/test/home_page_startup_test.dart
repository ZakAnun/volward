import 'dart:ffi';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/home_page.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/scan_preview.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/storage_overview.dart';
import 'package:volward/storage_overview_provider.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/theme/volward_theme_settings.dart';
import 'package:volward/updater/app_updater.dart';
import 'package:volward/updater/downloader.dart';
import 'package:volward/updater/platform_installer.dart';
import 'package:volward/updater/update_models.dart';
import 'package:volward/updater/url_opener.dart';
import 'package:volward/updater/version_source.dart';
import 'package:volward/volward_session.dart';
import 'package:volward/widgets/scan_column_view.dart';
import 'package:volward/widgets/storage_steward_home.dart';

StorageOverviewData _overviewData(String volumeName) {
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
        path: '/',
        kind: StorageLocationKind.home,
        volumeId: '/',
      ),
    ],
  );
}

class _OverviewProvider implements StorageOverviewProvider {
  int calls = 0;
  final List<String?> selectedPaths = [];

  @override
  Future<StorageOverviewData> load({String? selectedPath}) async {
    calls++;
    selectedPaths.add(selectedPath);
    return _overviewData('Test Disk');
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

/// A session whose preview is observable and whose restore hangs forever, so
/// the startup test can prove the preview is not gated on full restore.
class _BlockingSession extends VolwardSession {
  _BlockingSession({this.exposePreview = false}) : super.test() {
    setScanRoots(['/']);
  }

  final bool exposePreview;
  int previewCalls = 0;
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
  Future<void> previewTarget({int? expectedGeneration}) async {
    previewCalls++;
  }

  @override
  Future<void> restoreCachedSnapshotIfNeeded() {
    // Hangs on an unresolved Completer — no Timer is scheduled, so the widget
    // test's teardown check for pending timers stays green.
    return _restoreGate.future;
  }
}

class _PendingPreviewSession extends VolwardSession {
  _PendingPreviewSession({
    required this.root,
    required this.previewGate,
    this.failPreview = false,
  }) : super.test() {
    setScanRoots([root]);
    defaultRootForTest = () => root;
    rootExistsForTest = (_) => true;
  }

  final String root;
  final Completer<void> previewGate;
  final bool failPreview;
  int previewCalls = 0;
  int restoreCalls = 0;
  int runScanCalls = 0;
  int? expectedPreviewGeneration;

  @override
  bool get hasSnapshotFileApi => true;

  @override
  Future<void> previewTarget({int? expectedGeneration}) async {
    previewCalls++;
    expectedPreviewGeneration = expectedGeneration;
    await previewGate.future;
    if (failPreview) throw StateError('preview failed');
  }

  @override
  Future<void> restoreCachedSnapshotIfNeeded() async {
    restoreCalls++;
  }

  @override
  Future<String> runScan() async {
    runScanCalls++;
    return 'scan-$runScanCalls';
  }
}

class _HangingRestoreSession extends _PendingPreviewSession {
  _HangingRestoreSession({required super.root, required super.previewGate});

  final Completer<void> restoreGate = Completer<void>();

  @override
  Future<void> restoreCachedSnapshotIfNeeded() {
    restoreCalls++;
    return restoreGate.future;
  }
}

class _LocalVersionReader implements LocalVersionReader {
  _LocalVersionReader(this.version);

  final String version;

  @override
  Future<String> currentVersion() async => version;
}

class _ReleaseSource implements VersionSource {
  _ReleaseSource(this.release);

  final ReleaseInfo release;

  @override
  Future<ReleaseInfo> fetchLatest() async => release;
}

class _NoopDownloader implements Downloader {
  @override
  Future<String?> resolveExpectedSha256(ReleaseAsset asset) async {
    final sha = asset.sha256;
    if (sha != null && sha.isNotEmpty) return sha;
    return null;
  }

  @override
  Future<bool> isDownloadReachable(ReleaseAsset asset) async => true;

  @override
  Future<File> download(
    ReleaseAsset asset, {
    required Directory directory,
    DownloadProgress? onProgress,
  }) {
    throw UnsupportedError('unused');
  }
}

class _NoopUrls implements UrlOpener {
  @override
  Future<bool> open(String url) async => true;
}

class _AutoInstallInstaller implements PlatformInstaller {
  @override
  bool get canAutoInstall => true;

  @override
  Future<void> installAndRelaunch({
    required File downloaded,
    required ReleaseInfo release,
  }) async {}
}

AppUpdater _integrityFailureUpdater() {
  return AppUpdater(
    localVersionReader: _LocalVersionReader('0.0.1'),
    versionSource: _ReleaseSource(
      const ReleaseInfo(
        tagName: 'v0.0.2',
        version: '0.0.2',
        htmlUrl: 'https://example.invalid/releases/tag/v0.0.2',
        body: '',
        assets: [
          ReleaseAsset(
            name: 'volward-v0.0.2-macos-arm64.zip',
            downloadUrl: 'https://example.invalid/a.zip',
            sizeBytes: 1,
          ),
        ],
      ),
    ),
    downloader: _NoopDownloader(),
    installer: _AutoInstallInstaller(),
    urlOpener: _NoopUrls(),
    os: 'macos',
    abi: Abi.macosArm64,
    tempDirectoryBuilder: () =>
        Directory.systemTemp.createTempSync('volward_home_integrity_test_'),
  );
}

Widget _shell(
  VolwardSession session,
  VolwardThemeSettings themeSettings,
  AppUpdater updater, {
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
      storageOverviewProvider: storageOverviewProvider,
    ),
  );
}

void main() {
  testWidgets('startup preview blocks scan until current preview completes', (
    tester,
  ) async {
    final previewGate = Completer<void>();
    final session = _PendingPreviewSession(
      root: '/',
      previewGate: previewGate,
    )..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-startup-preview-pending.json',
      );
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await tester.pumpWidget(_shell(session, themeSettings, updater));
    await tester.pump();

    expect(session.previewCalls, 1);
    expect(session.expectedPreviewGeneration, session.rootSwitchGeneration);
    expect(
      tester.widget<StorageStewardHome>(find.byType(StorageStewardHome)).onScan,
      isNull,
    );
    await tester.tap(
      find.byKey(StorageStewardHome.scanActionKey),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(session.runScanCalls, 0);

    previewGate.complete();
    await tester.pump();
    await tester.pump();

    final scanAction = tester
        .widget<StorageStewardHome>(find.byType(StorageStewardHome))
        .onScan;
    expect(session.restoreCalls, 1);
    expect(scanAction, isNotNull);
    scanAction!();
    await tester.pump();
    expect(session.runScanCalls, 1);
  });

  testWidgets('stale scan callback is rejected during replacement startup', (
    tester,
  ) async {
    final completedPreview = Completer<void>()..complete();
    final oldSession = _PendingPreviewSession(
      root: '/old',
      previewGate: completedPreview,
    )..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-startup-old-ready.json',
      );
    final newPreview = Completer<void>();
    final newSession = _PendingPreviewSession(
      root: '/new',
      previewGate: newPreview,
    )..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-startup-new-pending.json',
      );
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await tester.pumpWidget(_shell(oldSession, themeSettings, updater));
    await tester.pump();
    await tester.pump();
    final staleAction = tester
        .widget<StorageStewardHome>(find.byType(StorageStewardHome))
        .onScan!;

    await tester.pumpWidget(_shell(newSession, themeSettings, updater));
    await tester.pump();
    expect(
      tester.widget<StorageStewardHome>(find.byType(StorageStewardHome)).onScan,
      isNull,
    );

    staleAction();
    await tester.pump();
    expect(oldSession.runScanCalls, 0);
    expect(newSession.runScanCalls, 0);

    newPreview.complete();
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<StorageStewardHome>(find.byType(StorageStewardHome)).onScan,
      isNotNull,
    );
  });

  testWidgets('startup preview error clears scan pending state',
      (tester) async {
    final completedPreview = Completer<void>()..complete();
    final session = _PendingPreviewSession(
      root: '/',
      previewGate: completedPreview,
      failPreview: true,
    )..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-startup-preview-error.json',
      );
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await tester.pumpWidget(_shell(session, themeSettings, updater));
    await tester.pump();
    await tester.pump();

    expect(session.previewCalls, 1);
    expect(session.restoreCalls, 0);
    expect(
      tester.widget<StorageStewardHome>(find.byType(StorageStewardHome)).onScan,
      isNotNull,
    );
  });

  testWidgets('late old preview cannot clear replacement startup pending', (
    tester,
  ) async {
    final oldPreview = Completer<void>();
    final newPreview = Completer<void>();
    final oldSession = _PendingPreviewSession(
      root: '/old',
      previewGate: oldPreview,
    )..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-startup-old-blocked.json',
      );
    final newSession = _PendingPreviewSession(
      root: '/new',
      previewGate: newPreview,
    )..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-startup-new-blocked.json',
      );
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await tester.pumpWidget(_shell(oldSession, themeSettings, updater));
    await tester.pump();
    expect(oldSession.previewCalls, 1);

    await tester.pumpWidget(_shell(newSession, themeSettings, updater));
    await tester.pump();
    expect(newSession.previewCalls, 1);

    oldPreview.complete();
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<StorageStewardHome>(find.byType(StorageStewardHome)).onScan,
      isNull,
    );
    expect(oldSession.runScanCalls, 0);
    expect(newSession.runScanCalls, 0);

    newPreview.complete();
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<StorageStewardHome>(find.byType(StorageStewardHome)).onScan,
      isNotNull,
    );
  });

  testWidgets(
    'HomePage starts the preview before a hanging restore completes',
    (tester) async {
      final session = _BlockingSession()
        ..sessionStateFileForTest = File(
          '${Directory.systemTemp.path}/volward-startup-test-no-session.json',
        )
        ..defaultRootForTest = (() => '/')
        ..rootExistsForTest = ((_) => true);
      final themeSettings = VolwardThemeSettings();
      final updater = AppUpdater.test();
      final overviewProvider = _OverviewProvider();
      addTearDown(themeSettings.dispose);
      addTearDown(updater.dispose);

      await tester.pumpWidget(
        _shell(
          session,
          themeSettings,
          updater,
          storageOverviewProvider: overviewProvider,
        ),
      );
      await tester.pump();

      expect(session.previewCalls, 1);
      // The branded home stays reachable during startup loading.
      expect(find.byType(StorageStewardHome), findsOneWidget);
      expect(find.byIcon(Icons.folder_open_outlined), findsWidgets);
      expect(overviewProvider.calls, 1);
      expect(overviewProvider.selectedPaths, ['/']);
    },
  );

  testWidgets(
    'Start Scan stays enabled while cache restore is still loading',
    (tester) async {
      final previewGate = Completer<void>()..complete();
      final session = _HangingRestoreSession(
        root: '/',
        previewGate: previewGate,
      )..sessionStateFileForTest = File(
          '${Directory.systemTemp.path}/volward-startup-hanging-restore.json',
        );
      final themeSettings = VolwardThemeSettings();
      final updater = AppUpdater.test();
      addTearDown(themeSettings.dispose);
      addTearDown(updater.dispose);

      await tester.pumpWidget(
        _shell(
          session,
          themeSettings,
          updater,
          storageOverviewProvider: _OverviewProvider(),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(session.previewCalls, 1);
      expect(session.restoreCalls, 1);
      expect(
        tester
            .widget<StorageStewardHome>(find.byType(StorageStewardHome))
            .onScan,
        isNotNull,
      );
    },
  );

  testWidgets(
    'HomePage keeps the folder picker visible when no launch root exists',
    (tester) async {
      final session = _BlockingSession()
        ..sessionStateFileForTest = File(
          '${Directory.systemTemp.path}/volward-startup-test-no-session.json',
        )
        ..defaultRootForTest = (() => '')
        ..rootExistsForTest = ((_) => false);
      final themeSettings = VolwardThemeSettings();
      final updater = AppUpdater.test();
      final overviewProvider = _OverviewProvider();
      addTearDown(themeSettings.dispose);
      addTearDown(updater.dispose);

      await tester.pumpWidget(
        _shell(
          session,
          themeSettings,
          updater,
          storageOverviewProvider: overviewProvider,
        ),
      );
      await tester.pump();

      // No valid root → preview is never started, branded home stays available.
      expect(session.previewCalls, 0);
      expect(find.byType(StorageStewardHome), findsOneWidget);
      expect(find.byIcon(Icons.folder_open_outlined), findsWidgets);
      expect(overviewProvider.calls, 0);
      expect(overviewProvider.selectedPaths, isEmpty);
    },
  );

  testWidgets('HomePage shows the preview while cache restore is in flight', (
    tester,
  ) async {
    // Point the session-state loader at a path that does not exist so a real
    // on-disk session.json (from a previous app run on this machine) cannot
    // leak into the test and change _scanRoots mid-startup.
    final session = _BlockingSession(exposePreview: true)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-startup-test-no-session.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await tester.pumpWidget(_shell(session, themeSettings, updater));
    await tester.pump();

    expect(session.previewCalls, 1);
    expect(find.byType(StorageStewardHome), findsOneWidget);
    expect(find.byType(ScanColumnView), findsNothing);
  });

  testWidgets('HomePage surfaces integrity failures on startup', (
    tester,
  ) async {
    final session = _BlockingSession()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-startup-test-no-session.json',
      )
      ..defaultRootForTest = (() => '/')
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = _integrityFailureUpdater();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await tester.pumpWidget(_shell(session, themeSettings, updater));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Missing SHA-256 checksum'), findsOneWidget);
  });

  testWidgets('newest overview load wins after app resume', (tester) async {
    final session = _BlockingSession()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-startup-stale-overview.json',
      )
      ..defaultRootForTest = (() => '/')
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final overviewProvider = _QueuedOverviewProvider();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await tester.pumpWidget(
      _shell(
        session,
        themeSettings,
        updater,
        storageOverviewProvider: overviewProvider,
      ),
    );
    await tester.pump();
    expect(overviewProvider.selectedPaths, ['/']);
    expect(
      tester
          .widget<StorageStewardHome>(find.byType(StorageStewardHome))
          .summary
          .overview
          .loading,
      isTrue,
    );

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    expect(overviewProvider.selectedPaths, ['/', '/']);

    overviewProvider.requests[1].complete(_overviewData('Fresh Disk'));
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<StorageStewardHome>(find.byType(StorageStewardHome))
          .summary
          .selectedVolume
          ?.name,
      'Fresh Disk',
    );

    overviewProvider.requests[0].complete(_overviewData('Stale Disk'));
    await tester.pump();
    expect(
      tester
          .widget<StorageStewardHome>(find.byType(StorageStewardHome))
          .summary
          .selectedVolume
          ?.name,
      'Fresh Disk',
    );
  });

  testWidgets('overview completion after disposal is ignored', (tester) async {
    final session = _BlockingSession()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-startup-disposed-overview.json',
      )
      ..defaultRootForTest = (() => '/')
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    final updater = AppUpdater.test();
    final overviewProvider = _QueuedOverviewProvider();
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await tester.pumpWidget(
      _shell(
        session,
        themeSettings,
        updater,
        storageOverviewProvider: overviewProvider,
      ),
    );
    await tester.pump();
    expect(overviewProvider.requests, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    overviewProvider.requests.single.complete(_overviewData('Late Disk'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
