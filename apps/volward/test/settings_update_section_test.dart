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

class _Downloader implements Downloader {
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
  }) async {
    await directory.create(recursive: true);
    final file = File('${directory.path}/${asset.name}');
    await file.writeAsBytes([1, 2, 3]);
    return file;
  }
}

class _NoopUrls implements UrlOpener {
  @override
  Future<bool> open(String url) async => true;
}

class _AutoInstaller implements PlatformInstaller {
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

AppUpdater _updater({
  required String local,
  required String remoteTag,
  PlatformInstaller installer = const UnsupportedInstaller(),
}) {
  final version = remoteTag.startsWith('v') || remoteTag.startsWith('V')
      ? remoteTag.substring(1)
      : remoteTag;
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
            sha256:
                '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
          ),
        ],
      ),
    ),
    downloader: _Downloader(),
    installer: installer,
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

  testWidgets('readyToInstall replaces the check button with complete update', (
    tester,
  ) async {
    final themeSettings = VolwardThemeSettings();
    addTearDown(themeSettings.dispose);
    final installer = _AutoInstaller();
    final updater = _updater(
      local: '0.0.1',
      remoteTag: 'v0.0.2',
      installer: installer,
    );
    addTearDown(updater.dispose);
    // The real flow is: startup prefetch finishes, then the user opens
    // settings — so land at `readyToInstall` before the first render.
    // `runAsync` is required because the prefetch does real file I/O, which
    // the fake-async test zone cannot drive.
    await tester.runAsync(() => updater.checkAndPrefetch());
    expect(updater.status.phase, UpdatePhase.readyToInstall);

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

    await tester.scrollUntilVisible(
      find.text('Complete update'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Complete update'), findsOneWidget);
    // Both buttons are visible when readyToInstall: "Complete update" triggers
    // the install; "Check for updates" lets the user look for a newer release.
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('A new version is downloaded and ready.'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Complete update'));
      await tester
          .pump(); // deliver the tap — starts unawaited installDownloaded()
      // sha256File does real I/O; yield to let it complete before the test ends.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(); // process notifyListeners from status change
    expect(installer.calls, 1);
  });

  testWidgets('other phases keep the check button and hide complete update', (
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

    await tester.scrollUntilVisible(
      find.text('Check for updates'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('Complete update'), findsNothing);
  });

  testWidgets('settings page does not repeat the privacy confirm copy', (
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

    expect(find.text('I understand'), findsNothing);
  });
}
