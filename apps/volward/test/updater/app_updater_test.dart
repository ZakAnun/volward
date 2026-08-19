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
  Object? error;
  Future<String?> Function(ReleaseAsset asset)? resolveSha256;
  Future<bool> Function(ReleaseAsset asset)? downloadReachable;

  @override
  Future<String?> resolveExpectedSha256(ReleaseAsset asset) async {
    if (resolveSha256 != null) return resolveSha256!(asset);
    final sha = asset.sha256;
    if (sha != null && sha.isNotEmpty) return sha;
    return null;
  }

  @override
  Future<bool> isDownloadReachable(ReleaseAsset asset) async {
    if (downloadReachable != null) return downloadReachable!(asset);
    return true;
  }

  @override
  Future<File> download(
    ReleaseAsset asset, {
    required Directory directory,
    DownloadProgress? onProgress,
  }) async {
    if (error != null) throw error!;
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
  File? lastDownloaded;
  ReleaseInfo? lastRelease;
  Object? error;

  @override
  bool get canAutoInstall => true;

  @override
  Future<void> installAndRelaunch({
    required File downloaded,
    required ReleaseInfo release,
  }) async {
    if (error != null) throw error!;
    lastDownloaded = downloaded;
    lastRelease = release;
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
            sha256:
                '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
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

  test('check rejects update assets without checksum metadata', () async {
    final updater = buildUpdater(
      source: _FakeSource(
        _release(
          assets: const [
            ReleaseAsset(
              name: 'volward-v0.0.2-macos-arm64.zip',
              downloadUrl: 'https://example.com/a.zip',
              sizeBytes: 3,
            ),
          ],
        ),
      ),
    );
    await updater.check(userInitiated: true);
    expect(updater.status.phase, UpdatePhase.error);
    expect(updater.status.failureKind, UpdateFailureKind.integrity);
  });

  test('check rejects assets whose checksum sidecar is unreachable', () async {
    final downloader = _FakeDownloader()..resolveSha256 = (_) async => null;
    final updater = buildUpdater(
      downloader: downloader,
      source: _FakeSource(
        _release(
          assets: const [
            ReleaseAsset(
              name: 'volward-v0.0.2-macos-arm64.zip',
              downloadUrl: 'https://example.com/a.zip',
              sizeBytes: 3,
              checksumUrl: 'https://example.com/a.zip.sha256',
            ),
          ],
        ),
      ),
    );
    await updater.check(userInitiated: true);
    expect(updater.status.phase, UpdatePhase.error);
    expect(updater.status.failureKind, UpdateFailureKind.integrity);
  });

  test('check prefers unsupportedRuntime over missing checksum', () async {
    final updater = buildUpdater(
      installer: const UnsupportedInstaller(),
      source: _FakeSource(
        _release(
          assets: const [
            ReleaseAsset(
              name: 'volward-v0.0.2-macos-arm64.zip',
              downloadUrl: 'https://example.com/a.zip',
              sizeBytes: 3,
            ),
          ],
        ),
      ),
    );
    await updater.check(userInitiated: true);
    expect(updater.status.phase, UpdatePhase.error);
    expect(updater.status.failureKind, UpdateFailureKind.unsupportedRuntime);
  });

  test('check rejects assets whose download URL is unreachable', () async {
    final downloader = _FakeDownloader()
      ..downloadReachable = (_) async => false;
    final updater = buildUpdater(downloader: downloader);
    await updater.check(userInitiated: true);
    expect(updater.status.phase, UpdatePhase.error);
    expect(updater.status.failureKind, UpdateFailureKind.noMatchingAsset);
  });

  test('check attaches resolved sha256 onto matchedAsset', () async {
    final updater = buildUpdater();
    await updater.check(userInitiated: true);
    expect(updater.status.phase, UpdatePhase.available);
    expect(
      updater.status.matchedAsset?.sha256,
      '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
    );
  });

  test(
    'downloadAndInstall classifies checksum failures as integrity',
    () async {
      final installer = _FakeInstaller();
      final downloader = _FakeDownloader()
        ..error = const UpdateIntegrityException('bad checksum');
      final updater = buildUpdater(
        installer: installer,
        downloader: downloader,
      );

      await updater.check(userInitiated: true);
      await updater.downloadAndInstall();

      expect(updater.status.phase, UpdatePhase.error);
      expect(updater.status.failureKind, UpdateFailureKind.integrity);
      expect(installer.installed, isFalse);
    },
  );

  test('openDownloadPage opens html_url', () async {
    final urls = _FakeUrls();
    final updater = buildUpdater(urls: urls);
    await updater.check(userInitiated: true);
    await updater.openDownloadPage();
    expect(urls.opened.single, contains('releases/tag/v0.0.2'));
  });

  test('silent check with no matching asset surfaces fallback error', () async {
    final updater = buildUpdater(
      source: _FakeSource(_release(assets: const [])),
    );
    await updater.check(userInitiated: false);
    expect(updater.status.phase, UpdatePhase.error);
    expect(updater.status.failureKind, UpdateFailureKind.noMatchingAsset);
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

  test(
    'silent check with unsupported runtime surfaces fallback error',
    () async {
      final updater = buildUpdater(installer: const UnsupportedInstaller());
      await updater.check(userInitiated: false);
      expect(updater.status.phase, UpdatePhase.error);
      expect(updater.status.failureKind, UpdateFailureKind.unsupportedRuntime);
    },
  );

  test('downloadOnly parks at readyToInstall without installing', () async {
    final installer = _FakeInstaller();
    final updater = buildUpdater(installer: installer);
    await updater.check(userInitiated: true);

    await updater.downloadOnly();

    expect(updater.status.phase, UpdatePhase.readyToInstall);
    expect(updater.status.downloadedFile, isNotNull);
    expect(installer.installed, isFalse);
  });

  test('downloadOnly rejects a non-available phase', () async {
    final updater = buildUpdater(local: '0.0.2');
    await updater.check(userInitiated: true);
    expect(updater.status.phase, UpdatePhase.upToDate);
    expect(updater.downloadOnly(), throwsStateError);
  });

  test('downloadOnly classifies transport failures as download', () async {
    final installer = _FakeInstaller();
    final downloader = _FakeDownloader()..error = Exception('socket closed');
    final updater = buildUpdater(installer: installer, downloader: downloader);
    await updater.check(userInitiated: true);

    await updater.downloadOnly();

    expect(updater.status.phase, UpdatePhase.error);
    expect(updater.status.failureKind, UpdateFailureKind.download);
    expect(installer.installed, isFalse);
  });

  test('downloadOnly classifies checksum failures as integrity', () async {
    final installer = _FakeInstaller();
    final downloader = _FakeDownloader()
      ..error = const UpdateIntegrityException('bad checksum');
    final updater = buildUpdater(installer: installer, downloader: downloader);
    await updater.check(userInitiated: true);

    await updater.downloadOnly();

    expect(updater.status.phase, UpdatePhase.error);
    expect(updater.status.failureKind, UpdateFailureKind.integrity);
    expect(installer.installed, isFalse);
  });

  test('installDownloaded hands the package to the installer', () async {
    final installer = _FakeInstaller();
    final downloader = _FakeDownloader();
    final updater = buildUpdater(installer: installer, downloader: downloader);
    await updater.check(userInitiated: true);
    await updater.downloadOnly();

    await updater.installDownloaded();

    expect(installer.installed, isTrue);
    expect(installer.lastDownloaded?.path, downloader.lastFile?.path);
    expect(installer.lastRelease?.version, '0.0.2');
  });

  test('installDownloaded rejects a non-readyToInstall phase', () async {
    final updater = buildUpdater();
    await updater.check(userInitiated: true);
    expect(updater.status.phase, UpdatePhase.available);
    expect(updater.installDownloaded(), throwsStateError);
  });

  test('installDownloaded classifies installer failures as install', () async {
    final installer = _FakeInstaller()..error = Exception('copy failed');
    final updater = buildUpdater(installer: installer);
    await updater.check(userInitiated: true);
    await updater.downloadOnly();

    await updater.installDownloaded();

    expect(updater.status.phase, UpdatePhase.error);
    expect(updater.status.failureKind, UpdateFailureKind.install);
  });

  test(
    'checkAndPrefetch downloads a newer release but never installs',
    () async {
      final installer = _FakeInstaller();
      final updater = buildUpdater(installer: installer);

      await updater.checkAndPrefetch();

      expect(updater.status.phase, UpdatePhase.readyToInstall);
      expect(updater.status.downloadedFile, isNotNull);
      expect(updater.showsReadyBanner, isTrue);
      expect(installer.installed, isFalse);
    },
  );

  test('checkAndPrefetch skips the download when already up to date', () async {
    final downloader = _FakeDownloader();
    final updater = buildUpdater(local: '0.0.2', downloader: downloader);

    await updater.checkAndPrefetch();

    expect(updater.status.phase, UpdatePhase.upToDate);
    expect(downloader.lastFile, isNull);
    expect(updater.showsReadyBanner, isFalse);
  });

  test('checkAndPrefetch stays silent on network failure', () async {
    final updater = buildUpdater(
      source: _FakeSource(null, error: Exception('offline')),
    );

    await updater.checkAndPrefetch();

    expect(updater.status.phase, UpdatePhase.idle);
    expect(updater.showsReadyBanner, isFalse);
  });

  test(
    'checkAndPrefetch surfaces unsupportedRuntime without a banner',
    () async {
      final updater = buildUpdater(installer: const UnsupportedInstaller());

      await updater.checkAndPrefetch();

      expect(updater.status.phase, UpdatePhase.error);
      expect(updater.status.failureKind, UpdateFailureKind.unsupportedRuntime);
      expect(updater.showsReadyBanner, isFalse);
    },
  );

  test(
    'dismissReadyToInstall hides the banner but keeps the package',
    () async {
      final updater = buildUpdater();
      await updater.checkAndPrefetch();
      expect(updater.showsReadyBanner, isTrue);

      updater.dismissReadyToInstall();

      expect(updater.showsReadyBanner, isFalse);
      expect(updater.status.phase, UpdatePhase.readyToInstall);
      expect(updater.status.downloadedFile, isNotNull);
    },
  );
}
