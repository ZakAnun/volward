// ignore_for_file: prefer_initializing_formals

import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'asset_resolver.dart';
import 'downloader.dart';
import 'platform_installer.dart';
import 'update_models.dart';
import 'url_opener.dart';
import 'version_compare.dart';
import 'version_source.dart';

class AppUpdater extends ChangeNotifier {
  AppUpdater({
    required LocalVersionReader localVersionReader,
    required VersionSource versionSource,
    required Downloader downloader,
    required PlatformInstaller installer,
    required UrlOpener urlOpener,
    required this.os,
    required this.abi,
    required Directory Function() tempDirectoryBuilder,
  })  : _localVersionReader = localVersionReader,
        _versionSource = versionSource,
        _downloader = downloader,
        _installer = installer,
        _urlOpener = urlOpener,
        _tempDirectoryBuilder = tempDirectoryBuilder;

  factory AppUpdater.test({String localVersion = '0.0.0'}) {
    return AppUpdater(
      localVersionReader: _TestLocalVersionReader(localVersion),
      versionSource: _TestVersionSource(localVersion),
      downloader: const _TestDownloader(),
      installer: const UnsupportedInstaller(),
      urlOpener: const _TestUrlOpener(),
      os: 'test',
      abi: Abi.current(),
      tempDirectoryBuilder: () => Directory.systemTemp,
    );
  }

  final LocalVersionReader _localVersionReader;
  final VersionSource _versionSource;
  final Downloader _downloader;
  final PlatformInstaller _installer;
  final UrlOpener _urlOpener;
  final String os;
  final Abi abi;
  final Directory Function() _tempDirectoryBuilder;

  UpdateStatus _status = UpdateStatus.idle;
  UpdateStatus get status => _status;

  bool _dismissedThisSession = false;
  bool get shouldPromptOnStartup =>
      !_dismissedThisSession && _status.phase == UpdatePhase.available;

  String? _cachedLocalVersion;
  Future<String> localVersion() async {
    return _cachedLocalVersion ??= await _localVersionReader.currentVersion();
  }

  void dismissAvailable() {
    _dismissedThisSession = true;
    if (_status.phase == UpdatePhase.available) {
      _setStatus(UpdateStatus.idle);
    }
  }

  void dismissErrorPrompt() {
    _dismissedThisSession = true;
    if (_status.phase == UpdatePhase.error) {
      _setStatus(UpdateStatus.idle);
    }
  }

  Future<void> check({required bool userInitiated}) async {
    _setStatus(const UpdateStatus(phase: UpdatePhase.checking));
    try {
      final local = await localVersion();
      final release = await _versionSource.fetchLatest();
      if (!isRemoteNewer(remoteTag: release.tagName, localVersion: local)) {
        _setStatus(UpdateStatus(phase: UpdatePhase.upToDate, release: release));
        return;
      }

      final asset = resolveAsset(
        assets: release.assets,
        os: os,
        abi: abi,
        version: release.version,
      );
      if (asset == null) {
        _setStatus(
          UpdateStatus(
            phase: UpdatePhase.error,
            release: release,
            failureKind: UpdateFailureKind.noMatchingAsset,
            errorMessage: 'No matching asset for $os/$abi',
          ),
        );
        return;
      }
      // Prefer runtime capability over integrity so non-AppImage / non-bundle
      // installs get unsupportedRuntime instead of a misleading checksum error.
      if (!_installer.canAutoInstall) {
        _setStatus(
          UpdateStatus(
            phase: UpdatePhase.error,
            release: release,
            matchedAsset: asset,
            failureKind: UpdateFailureKind.unsupportedRuntime,
            errorMessage: 'Auto-update unsupported for this install',
          ),
        );
        return;
      }
      // Convention asset URLs always include a `.sha256` sidecar path, but older
      // releases may not have uploaded that file. Probe reachability before
      // advertising an installable update.
      final expectedSha256 = await _downloader.resolveExpectedSha256(asset);
      if (expectedSha256 == null) {
        _setStatus(
          UpdateStatus(
            phase: UpdatePhase.error,
            release: release,
            matchedAsset: asset,
            failureKind: UpdateFailureKind.integrity,
            errorMessage: 'Missing SHA-256 checksum for ${asset.name}',
          ),
        );
        return;
      }
      // Page/Atom paths synthesize download URLs; confirm the binary exists too.
      final reachable = await _downloader.isDownloadReachable(asset);
      if (!reachable) {
        _setStatus(
          UpdateStatus(
            phase: UpdatePhase.error,
            release: release,
            matchedAsset: asset,
            failureKind: UpdateFailureKind.noMatchingAsset,
            errorMessage: 'Asset not reachable: ${asset.name}',
          ),
        );
        return;
      }
      final verifiedAsset = asset.copyWith(sha256: expectedSha256);

      _setStatus(
        UpdateStatus(
          phase: UpdatePhase.available,
          release: release,
          matchedAsset: verifiedAsset,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('AppUpdater.check failed: $error\n$stackTrace');
      if (!userInitiated) {
        _setStatus(UpdateStatus.idle);
        return;
      }
      _setStatus(
        UpdateStatus(
          phase: UpdatePhase.error,
          failureKind: UpdateFailureKind.network,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> downloadAndInstall() async {
    if (_status.phase != UpdatePhase.available) {
      throw StateError(
        'Cannot install update while phase is ${_status.phase.name}',
      );
    }
    final release = _status.release;
    final asset = _status.matchedAsset;
    if (release == null || asset == null) {
      throw StateError('No available update to install');
    }

    try {
      final tempDirectory = _tempDirectoryBuilder();
      _setStatus(
        UpdateStatus(
          phase: UpdatePhase.downloading,
          release: release,
          matchedAsset: asset,
          progress: 0,
        ),
      );
      final file = await _downloader.download(
        asset,
        directory: tempDirectory,
        onProgress: (progress) {
          _setStatus(
            UpdateStatus(
              phase: UpdatePhase.downloading,
              release: release,
              matchedAsset: asset,
              progress: progress,
            ),
          );
        },
      );
      _setStatus(
        UpdateStatus(
          phase: UpdatePhase.installing,
          release: release,
          matchedAsset: asset,
          progress: 1,
        ),
      );
      await _installer.installAndRelaunch(downloaded: file, release: release);
    } catch (error, stackTrace) {
      debugPrint('AppUpdater.downloadAndInstall failed: $error\n$stackTrace');
      final failureKind = _failureKindForInstallError(error);
      _setStatus(
        UpdateStatus(
          phase: UpdatePhase.error,
          release: release,
          matchedAsset: asset,
          failureKind: failureKind,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  UpdateFailureKind _failureKindForInstallError(Object error) {
    if (error is UnsupportedError) return UpdateFailureKind.unsupportedRuntime;
    if (error is UpdateIntegrityException) return UpdateFailureKind.integrity;
    if (_status.phase == UpdatePhase.downloading) {
      return UpdateFailureKind.download;
    }
    return UpdateFailureKind.install;
  }

  Future<void> openDownloadPage() async {
    final url = _status.release?.htmlUrl;
    await _urlOpener.open(
      url == null || url.isEmpty
          ? 'https://github.com/ZakAnun/volward/releases/latest'
          : url,
    );
  }

  void _setStatus(UpdateStatus next) {
    _status = next;
    notifyListeners();
  }
}

class _TestLocalVersionReader implements LocalVersionReader {
  const _TestLocalVersionReader(this.version);

  final String version;

  @override
  Future<String> currentVersion() async => version;
}

class _TestVersionSource implements VersionSource {
  const _TestVersionSource(this.version);

  final String version;

  @override
  Future<ReleaseInfo> fetchLatest() async => ReleaseInfo(
        tagName: 'v$version',
        version: version,
        htmlUrl: 'https://example.invalid/releases/latest',
        body: '',
        assets: const [],
      );
}

class _TestDownloader implements Downloader {
  const _TestDownloader();

  @override
  Future<String?> resolveExpectedSha256(ReleaseAsset asset) async => null;

  @override
  Future<bool> isDownloadReachable(ReleaseAsset asset) async => false;

  @override
  Future<File> download(
    ReleaseAsset asset, {
    required Directory directory,
    DownloadProgress? onProgress,
  }) {
    throw UnsupportedError('Downloads are disabled in AppUpdater.test');
  }
}

class _TestUrlOpener implements UrlOpener {
  const _TestUrlOpener();

  @override
  Future<bool> open(String url) async => true;
}
