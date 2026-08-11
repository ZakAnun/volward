import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/settings_page.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/theme/volward_theme_settings.dart';
import 'package:volward/updater/app_updater.dart';
import 'package:volward/updater/downloader.dart';
import 'package:volward/updater/platform_installer.dart';
import 'package:volward/updater/update_models.dart';
import 'package:volward/updater/url_opener.dart';
import 'package:volward/updater/version_source.dart';
import 'package:volward/volward_session.dart';

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

class _NoopDownloader implements Downloader {
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

AppUpdater _updater({required String local, required String remoteTag}) {
  final version = remoteTag.replaceFirst(RegExp(r'^[vV]'), '');
  return AppUpdater(
    localVersionReader: _Local(local),
    versionSource: _Source(
      ReleaseInfo(
        tagName: remoteTag,
        version: version,
        htmlUrl: 'https://example.invalid/releases/tag/$remoteTag',
        body: 'notes',
        assets: [
          ReleaseAsset(
            name: 'volward-v$version-macos-arm64.zip',
            downloadUrl: 'https://example.invalid/a.zip',
            sizeBytes: 1,
          ),
        ],
      ),
    ),
    downloader: _NoopDownloader(),
    installer: const UnsupportedInstaller(),
    urlOpener: _NoopUrls(),
    os: 'macos',
    abi: Abi.macosArm64,
    tempDirectoryBuilder: () =>
        Directory.systemTemp.createTempSync('volward_settings_update_test_'),
  );
}

void main() {
  testWidgets('manual check shows up-to-date toast when no newer release', (
    tester,
  ) async {
    final themeSettings = VolwardThemeSettings();
    addTearDown(themeSettings.dispose);
    final updater = _updater(local: '0.0.1', remoteTag: 'v0.0.1');
    addTearDown(updater.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: buildVolwardTheme(brightness: Brightness.light),
        home: SettingsPage(
          themeSettings: themeSettings,
          session: VolwardSession.test(),
          deletableOnly: false,
          onDeletableOnlyChanged: (_) {},
          updater: updater,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // About section sits below the fold in the default test viewport.
    await tester.scrollUntilVisible(
      find.text('Check for updates'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Check for updates'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(updater.status.phase, UpdatePhase.upToDate);
    // Inline status + toast both use the same copy.
    expect(find.text("You're up to date."), findsWidgets);
  });
}
