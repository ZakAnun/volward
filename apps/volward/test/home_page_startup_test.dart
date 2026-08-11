import 'dart:ffi';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/home_page.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/scan_preview.dart';
import 'package:volward/scan_snapshot_state.dart';
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
  AppUpdater updater,
) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildVolwardTheme(brightness: Brightness.light),
    home: HomePage(
      session: session,
      themeSettings: themeSettings,
      updater: updater,
    ),
  );
}

void main() {
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
      addTearDown(themeSettings.dispose);
      addTearDown(updater.dispose);

      await tester.pumpWidget(_shell(session, themeSettings, updater));
      await tester.pump();

      expect(session.previewCalls, 1);
      // The folder action stays reachable during startup loading.
      expect(find.byIcon(Icons.folder_open_outlined), findsWidgets);
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
      addTearDown(themeSettings.dispose);
      addTearDown(updater.dispose);

      await tester.pumpWidget(_shell(session, themeSettings, updater));
      await tester.pump();

      // No valid root → preview is never started, picker stays available.
      expect(session.previewCalls, 0);
      expect(find.byIcon(Icons.folder_open_outlined), findsWidgets);
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
    expect(find.byType(ScanColumnView), findsOneWidget);
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
}
