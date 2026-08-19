import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/updater/app_updater.dart';
import 'package:volward/updater/downloader.dart';
import 'package:volward/updater/platform_installer.dart';
import 'package:volward/updater/update_models.dart';
import 'package:volward/updater/url_opener.dart';
import 'package:volward/updater/version_source.dart';
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
    await file.writeAsBytes([1, 2, 3]);
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

AppUpdater _updater({required _Installer installer}) {
  return AppUpdater(
    localVersionReader: _Local('0.0.1'),
    versionSource: _Source(
      const ReleaseInfo(
        tagName: 'v0.0.2',
        version: '0.0.2',
        htmlUrl: 'https://example.invalid/releases/tag/v0.0.2',
        body: 'notes',
        assets: [
          ReleaseAsset(
            name: 'volward-v0.0.2-macos-arm64.zip',
            downloadUrl: 'https://example.invalid/a.zip',
            sizeBytes: 3,
            sha256:
                '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
          ),
        ],
      ),
    ),
    downloader: _Downloader(),
    installer: installer,
    urlOpener: _Urls(),
    os: 'macos',
    abi: Abi.macosArm64,
    tempDirectoryBuilder: () =>
        Directory.systemTemp.createTempSync('volward_pill_test_'),
  );
}

Widget _host(AppUpdater updater) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: buildVolwardTheme(brightness: Brightness.light),
    home: Scaffold(
      body: Center(child: UpdateReadyPill(updater: updater)),
    ),
  );
}

void main() {
  testWidgets('stays hidden until a package is ready', (tester) async {
    final installer = _Installer();
    final updater = _updater(installer: installer);
    addTearDown(updater.dispose);

    await tester.pumpWidget(_host(updater));
    await tester.pumpAndSettle();

    expect(find.text('Complete update'), findsNothing);
  });

  testWidgets('appears once the download parks at readyToInstall', (
    tester,
  ) async {
    final installer = _Installer();
    final updater = _updater(installer: installer);
    addTearDown(updater.dispose);

    await tester.pumpWidget(_host(updater));
    // `checkAndPrefetch` does real file I/O, which the fake-async test zone
    // cannot drive — `runAsync` hands it the real event loop.
    await tester.runAsync(() => updater.checkAndPrefetch());
    await tester.pump();

    expect(updater.status.phase, UpdatePhase.readyToInstall);
    expect(find.text('Complete update'), findsOneWidget);
  });

  testWidgets('tapping the body installs without a confirmation dialog', (
    tester,
  ) async {
    final installer = _Installer();
    final updater = _updater(installer: installer);
    addTearDown(updater.dispose);

    await tester.pumpWidget(_host(updater));
    await tester.runAsync(() => updater.checkAndPrefetch());
    await tester.pump();

    await tester.tap(find.byKey(UpdateReadyPill.actionKey));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(installer.calls, 1);
  });

  testWidgets('the close affordance hides the pill but keeps the package', (
    tester,
  ) async {
    final installer = _Installer();
    final updater = _updater(installer: installer);
    addTearDown(updater.dispose);

    await tester.pumpWidget(_host(updater));
    await tester.runAsync(() => updater.checkAndPrefetch());
    await tester.pump();

    await tester.tap(find.byKey(UpdateReadyPill.dismissKey));
    await tester.pumpAndSettle();

    expect(find.text('Complete update'), findsNothing);
    expect(updater.status.phase, UpdatePhase.readyToInstall);
    expect(updater.status.downloadedFile, isNotNull);
    expect(installer.calls, 0);
  });
}
