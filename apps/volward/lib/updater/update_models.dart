enum UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  installing,
  error,
}

enum UpdateFailureKind {
  network,
  noMatchingAsset,
  download,
  install,
  unsupportedRuntime,
}

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  final String name;
  final String downloadUrl;
  final int sizeBytes;
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
  });

  final UpdatePhase phase;
  final ReleaseInfo? release;
  final ReleaseAsset? matchedAsset;
  final double? progress; // 0.0–1.0 while downloading
  final String? errorMessage;
  final UpdateFailureKind? failureKind;

  static const idle = UpdateStatus(phase: UpdatePhase.idle);
}
