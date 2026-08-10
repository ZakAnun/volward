import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/updater/app_updater.dart';
import 'package:volward/updater/downloader.dart';
import 'package:volward/updater/platform_installer.dart';
import 'package:volward/updater/update_models.dart';
import 'package:volward/updater/url_opener.dart';
import 'package:volward/updater/version_source.dart';

class _FakeLocal implements LocalVersionReader {
  _FakeLocal(this.version);

  final String version;

  @override
  Future<String> currentVersion() async => version;
}

class _FakeSource implements VersionSource {
  _FakeSource(this.release, {this.error});

  final ReleaseInfo? release;
  final Object? error;

  @override
  Future<ReleaseInfo> fetchLatest() async {
    if (error != null) throw error!;
    return release!;
  }
}

class _FakeDownloader implements Downloader {
  File? lastFile;

  @override
  Future<File> download(
    ReleaseAsset asset, {
    required Directory directory,
    DownloadProgress? onProgress,
  }) async {
    onProgress?.call(0.5);
    await directory.create(recursive: true);
    final file = File('${directory.path}/${asset.name}');
    await file.writeAsBytes([1, 2, 3]);
    onProgress?.call(1.0);
    lastFile = file;
    return file;
  }
}

class _FakeInstaller implements PlatformInstaller {
  bool installed = false;

  @override
  bool get canAutoInstall => true;

  @override
  Future<void> installAndRelaunch({
    required File downloaded,
    required ReleaseInfo release,
  }) async {
    installed = true;
  }
}

class _FakeUrls implements UrlOpener {
  final opened = <String>[];

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return true;
  }
}

ReleaseInfo _release({String tag = 'v0.0.2', List<ReleaseAsset>? assets}) {
  return ReleaseInfo(
    tagName: tag,
    version: '0.0.2',
    htmlUrl: 'https://github.com/ZakAnun/volward/releases/tag/$tag',
    body: 'Release notes line 1\nline 2',
    assets:
        assets ??
        const [
          ReleaseAsset(
            name: 'volward-v0.0.2-macos-arm64.zip',
            downloadUrl: 'https://example.com/a.zip',
            sizeBytes: 3,
          ),
        ],
  );
}

AppUpdater buildUpdater({
  String local = '0.0.1',
  VersionSource? source,
  PlatformInstaller? installer,
  UrlOpener? urls,
  Downloader? downloader,
}) {
  return AppUpdater(
    localVersionReader: _FakeLocal(local),
    versionSource: source ?? _FakeSource(_release()),
    downloader: downloader ?? _FakeDownloader(),
    installer: installer ?? _FakeInstaller(),
    urlOpener: urls ?? _FakeUrls(),
    os: 'macos',
    abi: Abi.macosArm64,
    tempDirectoryBuilder: () =>
        Directory.systemTemp.createTempSync('volward_updater_test_'),
  );
}

void main() {
  test('check moves to available when remote newer', () async {
    final updater = buildUpdater();
    await updater.check(userInitiated: false);
    expect(updater.status.phase, UpdatePhase.available);
    expect(updater.status.matchedAsset?.name, contains('macos-arm64'));
  });

  test('check moves to upToDate when same version', () async {
    final updater = buildUpdater(local: '0.0.2');
    await updater.check(userInitiated: true);
    expect(updater.status.phase, UpdatePhase.upToDate);
  });

  test('silent check swallows network errors', () async {
    final updater = buildUpdater(
      source: _FakeSource(null, error: Exception('offline')),
    );
    await updater.check(userInitiated: false);
    expect(updater.status.phase, UpdatePhase.idle);
  });

  test('manual check surfaces network errors', () async {
    final updater = buildUpdater(
      source: _FakeSource(null, error: Exception('offline')),
    );
    await updater.check(userInitiated: true);
    expect(updater.status.phase, UpdatePhase.error);
    expect(updater.status.failureKind, UpdateFailureKind.network);
  });

  test('downloadAndInstall reaches installer', () async {
    final installer = _FakeInstaller();
    final updater = buildUpdater(installer: installer);
    await updater.check(userInitiated: true);
    await updater.downloadAndInstall();
    expect(installer.installed, isTrue);
  });

  test('downloadAndInstall rejects non-available phase', () async {
    final installer = _FakeInstaller();
    final updater = buildUpdater(installer: installer);
    await updater.check(userInitiated: true);
    await updater.downloadAndInstall();

    expect(updater.status.phase, UpdatePhase.installing);
    expect(updater.downloadAndInstall(), throwsStateError);
  });

  test('dismissAvailable suppresses startup prompt flag', () async {
    final updater = buildUpdater();
    await updater.check(userInitiated: false);
    expect(updater.shouldPromptOnStartup, isTrue);
    updater.dismissAvailable();
    expect(updater.shouldPromptOnStartup, isFalse);
    expect(updater.status.phase, UpdatePhase.idle);
  });

  test('dismissAvailable does not wipe a non-available phase', () async {
    final updater = buildUpdater(local: '0.0.2');
    await updater.check(userInitiated: true);
    updater.dismissAvailable();
    expect(updater.status.phase, UpdatePhase.upToDate);
  });

  test('openDownloadPage opens html_url', () async {
    final urls = _FakeUrls();
    final updater = buildUpdater(urls: urls);
    await updater.check(userInitiated: true);
    await updater.openDownloadPage();
    expect(urls.opened.single, contains('releases/tag/v0.0.2'));
  });

  test('silent check with no matching asset returns to idle', () async {
    final updater = buildUpdater(
      source: _FakeSource(_release(assets: const [])),
    );
    await updater.check(userInitiated: false);
    expect(updater.status.phase, UpdatePhase.idle);
  });

  test(
    'manual check with no matching asset surfaces error with kind',
    () async {
      final updater = buildUpdater(
        source: _FakeSource(_release(assets: const [])),
      );
      await updater.check(userInitiated: true);
      expect(updater.status.phase, UpdatePhase.error);
      expect(updater.status.failureKind, UpdateFailureKind.noMatchingAsset);
    },
  );

  test('silent check with unsupported runtime returns to idle', () async {
    final updater = buildUpdater(installer: const UnsupportedInstaller());
    await updater.check(userInitiated: false);
    expect(updater.status.phase, UpdatePhase.idle);
  });
}
