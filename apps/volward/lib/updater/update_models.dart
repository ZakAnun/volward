import 'dart:io';

enum UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  readyToInstall,
  installing,
  error,
}

enum UpdateFailureKind {
  network,
  noMatchingAsset,
  integrity,
  download,
  install,
  unsupportedRuntime,
}

class UpdateIntegrityException implements Exception {
  const UpdateIntegrityException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
    this.sha256,
    this.checksumUrl,
  });

  final String name;
  final String downloadUrl;
  final int sizeBytes;
  final String? sha256;
  final String? checksumUrl;

  bool get hasIntegrityMetadata =>
      (sha256 != null && sha256!.isNotEmpty) ||
      (checksumUrl != null && checksumUrl!.isNotEmpty);

  ReleaseAsset copyWith({String? sha256, String? checksumUrl}) {
    return ReleaseAsset(
      name: name,
      downloadUrl: downloadUrl,
      sizeBytes: sizeBytes,
      sha256: sha256 ?? this.sha256,
      checksumUrl: checksumUrl ?? this.checksumUrl,
    );
  }
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.htmlUrl,
    required this.body,
    required this.assets,
  });

  final String tagName;
  final String version; // normalized MAJOR.MINOR.PATCH
  final String htmlUrl;
  final String body;
  final List<ReleaseAsset> assets;
}

class UpdateStatus {
  const UpdateStatus({
    required this.phase,
    this.release,
    this.matchedAsset,
    this.progress,
    this.errorMessage,
    this.failureKind,
    this.downloadedFile,
  });

  final UpdatePhase phase;
  final ReleaseInfo? release;
  final ReleaseAsset? matchedAsset;
  final double? progress; // 0.0–1.0 while downloading
  final String? errorMessage;
  final UpdateFailureKind? failureKind;

  /// The verified package on disk. Non-null only in [UpdatePhase.readyToInstall]
  /// and [UpdatePhase.installing].
  final File? downloadedFile;

  static const idle = UpdateStatus(phase: UpdatePhase.idle);
}
