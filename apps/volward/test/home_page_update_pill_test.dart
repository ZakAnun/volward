import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/home_page.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
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
import 'package:volward/widgets/update_ready_pill.dart';

class _Local implements LocalVersionReader {
  _Local(this.version);
  final String version;
  @override
  Future<String> currentVersion() async => version;
}

class _Source implements VersionSource {
  _Source(this.release);
  final ReleaseInfo release;
  @override
  Future<ReleaseInfo> fetchLatest() async => release;
}

class _Downloader implements Downloader {
  @override
  Future<String?> resolveExpectedSha256(ReleaseAsset asset) async =>
      asset.sha256;

  @override
  Future<bool> isDownloadReachable(ReleaseAsset asset) async => true;

  @override
  Future<File> download(
    ReleaseAsset asset, {
    required Directory directory,
    DownloadProgress? onProgress,
  }) async {
    await directory.create(recursive: true);
    final file = File('${directory.path}/${asset.name}');
    // Write synchronously to avoid event loop delays in tests.
    file.writeAsBytesSync(const [1, 2, 3]);
    // Call progress callback after write completes.
    onProgress?.call(1.0);
    return file;
  }
}

class _Installer implements PlatformInstaller {
  int calls = 0;

  @override
  bool get canAutoInstall => true;

  @override
  Future<void> installAndRelaunch({
    required File downloaded,
    required ReleaseInfo release,
  }) async {
    calls++;
  }
}

class _Urls implements UrlOpener {
  @override
  Future<bool> open(String url) async => true;
}

class _Overview implements StorageOverviewProvider {
  @override
  Future<StorageOverviewData> load({String? selectedPath}) async {
    return StorageOverviewData(
      selectedVolumeId: '/',
      volumes: const [
        StorageVolumeInfo(
          id: '/',
          name: 'Test Disk',
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

/// A session that never touches the native library and never resolves its
/// snapshot restore, so `pumpAndSettle` has no pending timers to trip over.
/// Mirrors `_HangingRestoreSession` in `home_page_startup_test.dart`.
class _QuietSession extends VolwardSession {
  _QuietSession() : super.test() {
    setScanRoots(['/']);
  }

  final Completer<void> restoreGate = Completer<void>();

  @override
  bool get restoringSnapshot => false;

  @override
  Future<void> previewTarget({int? expectedGeneration}) async {}

  @override
  Future<void> restoreCachedSnapshotIfNeeded() => restoreGate.future;
}

class _ThrowingRestoreSession extends _QuietSession {
  @override
  Future<void> restoreCachedSnapshotIfNeeded() async {
    throw StateError('restore failed');
  }
}

class _ThrowingPreviewSession extends _QuietSession {
  @override
  Future<void> previewTarget({int? expectedGeneration}) async {
    throw StateError('preview failed');
  }
}

/// Same constructor args as [AppUpdater.test] — that factory cannot be
/// forwarded via `super.test()`.
class _CountingPrefetchUpdater extends AppUpdater {
  _CountingPrefetchUpdater({required this.onPrefetch})
    : super(
        localVersionReader: _Local('0.0.0'),
        versionSource: _Source(
          const ReleaseInfo(
            tagName: 'v0.0.0',
            version: '0.0.0',
            htmlUrl: 'https://example.invalid/releases/latest',
            body: '',
            assets: const [],
          ),
        ),
        downloader: _Downloader(),
        installer: _Installer(),
        urlOpener: _Urls(),
        os: 'test',
        abi: Abi.current(),
        tempDirectoryBuilder: () => Directory.systemTemp,
      );

  final VoidCallback onPrefetch;

  @override
  Future<void> checkAndPrefetch() async {
    onPrefetch();
    return super.checkAndPrefetch();
  }
}

ReleaseInfo _release({String? sha256}) {
  return ReleaseInfo(
    tagName: 'v0.0.2',
    version: '0.0.2',
    htmlUrl: 'https://example.invalid/releases/tag/v0.0.2',
    body: 'notes',
    assets: [
      ReleaseAsset(
        name: 'volward-v0.0.2-macos-arm64.zip',
        downloadUrl: 'https://example.invalid/a.zip',
        sizeBytes: 3,
        sha256: sha256,
      ),
    ],
  );
}

AppUpdater _updater({
  required ReleaseInfo release,
  required _Installer installer,
  required String tempPrefix,
}) {
  return AppUpdater(
    localVersionReader: _Local('0.0.1'),
    versionSource: _Source(release),
    downloader: _Downloader(),
    installer: installer,
    urlOpener: _Urls(),
    os: 'macos',
    abi: Abi.macosArm64,
    tempDirectoryBuilder: () => Directory.systemTemp.createTempSync(tempPrefix),
  );
}

_QuietSession _session(String stateFileName) {
  return _QuietSession()
    ..sessionStateFileForTest = File(
      '${Directory.systemTemp.path}/$stateFileName',
    )
    ..defaultRootForTest = (() => '/')
    ..rootExistsForTest = ((_) => true);
}

Widget _shell(
  VolwardSession session,
  VolwardThemeSettings themeSettings,
  AppUpdater updater,
) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: buildVolwardTheme(brightness: Brightness.light),
    home: HomePage(
      session: session,
      themeSettings: themeSettings,
      updater: updater,
      storageOverviewProvider: _Overview(),
    ),
  );
}

void main() {
  testWidgets('startup prefetch surfaces the pill instead of a dialog', (
    tester,
  ) async {
    final session = _session('volward-home-pill-ready.json');
    final themeSettings = VolwardThemeSettings();
    final installer = _Installer();
    final updater = _updater(
      release: _release(
        sha256:
            '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
      ),
      installer: installer,
      tempPrefix: 'volward_home_pill_ready_',
    );
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await tester.pumpWidget(_shell(session, themeSettings, updater));
    // Prefetch must wait for cached-snapshot restore, plus one extra frame.
    // Run the I/O-bearing checkAndPrefetch() inside runAsync so directory
    // writes are not trapped in the fake-async zone.
    await tester.runAsync(() async {
      await tester.pump();
      expect(updater.status.phase, UpdatePhase.idle);
      session.restoreGate.complete();
      await tester.pump();
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    expect(tester.takeException(), isNull);

    // Rebuild widgets with the new updater state.
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(updater.status.phase, UpdatePhase.readyToInstall);
    expect(find.byType(UpdateReadyPill), findsOneWidget);
    expect(find.text('Complete update'), findsOneWidget);
    expect(installer.calls, 0);
  });

  testWidgets('startup failures stay completely silent on the home page', (
    tester,
  ) async {
    final session = _session('volward-home-pill-integrity.json');
    final themeSettings = VolwardThemeSettings();
    // No checksum on the asset — `check()` lands on error(integrity), the exact
    // case that used to raise a startup dialog.
    final updater = _updater(
      release: _release(),
      installer: _Installer(),
      tempPrefix: 'volward_home_pill_integrity_',
    );
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await tester.pumpWidget(_shell(session, themeSettings, updater));
    session.restoreGate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(updater.status.failureKind, UpdateFailureKind.integrity);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Missing SHA-256 checksum'), findsNothing);
    expect(find.text('Complete update'), findsNothing);
  });

  testWidgets('prefetch waits until cached snapshot restore finishes', (
    tester,
  ) async {
    final session = _session('volward-home-pill-prefetch-wait.json');
    final themeSettings = VolwardThemeSettings();
    var prefetchCalls = 0;
    final updater = _CountingPrefetchUpdater(onPrefetch: () => prefetchCalls++);
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await tester.pumpWidget(_shell(session, themeSettings, updater));
    await tester.pump();
    expect(prefetchCalls, 0);
    session.restoreGate.complete();
    await tester.pump();
    await tester.pump();
    expect(prefetchCalls, 1);
  });

  testWidgets('restore throw still schedules prefetch once', (tester) async {
    final session = _ThrowingRestoreSession()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-pill-restore-throw.json',
      )
      ..defaultRootForTest = (() => '/')
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    var prefetchCalls = 0;
    final updater = _CountingPrefetchUpdater(onPrefetch: () => prefetchCalls++);
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await tester.pumpWidget(_shell(session, themeSettings, updater));
    await tester.pump();
    await tester.pump();
    expect(prefetchCalls, 1);
    await tester.pump();
    expect(prefetchCalls, 1);
  });

  testWidgets('preview throw still schedules prefetch once', (tester) async {
    final session = _ThrowingPreviewSession()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-home-pill-preview-throw.json',
      )
      ..defaultRootForTest = (() => '/')
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    var prefetchCalls = 0;
    final updater = _CountingPrefetchUpdater(onPrefetch: () => prefetchCalls++);
    addTearDown(themeSettings.dispose);
    addTearDown(updater.dispose);

    await tester.pumpWidget(_shell(session, themeSettings, updater));
    await tester.pump();
    await tester.pump();
    expect(prefetchCalls, 1);
    await tester.pump();
    expect(prefetchCalls, 1);
  });
}
