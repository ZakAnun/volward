import 'dart:ffi';

import 'update_models.dart';

String? expectedAssetName({
  required String os,
  required Abi abi,
  required String version,
}) {
  if (os == 'macos' && abi == Abi.macosArm64) {
    return 'volward-v$version-macos-arm64.zip';
  }
  if (os == 'macos' && abi == Abi.macosX64) {
    return 'volward-v$version-macos-x64.zip';
  }
  if (os == 'windows' && abi == Abi.windowsX64) {
    return 'VolwardSetup-v$version-windows-x64.exe';
  }
  if (os == 'linux' && abi == Abi.linuxX64) {
    return 'Volward-v$version-linux-x86_64.AppImage';
  }
  return null;
}

/// Stable `*-latest-*` names published beside the versioned archives.
String? expectedLatestAssetName({required String os, required Abi abi}) {
  if (os == 'macos' && abi == Abi.macosArm64) {
    return 'volward-latest-macos-arm64.zip';
  }
  if (os == 'macos' && abi == Abi.macosX64) {
    return 'volward-latest-macos-x64.zip';
  }
  if (os == 'windows' && abi == Abi.windowsX64) {
    return 'VolwardSetup-latest-windows-x64.exe';
  }
  if (os == 'linux' && abi == Abi.linuxX64) {
    return 'Volward-latest-linux-x86_64.AppImage';
  }
  return null;
}

List<ReleaseAsset> resolveAssetCandidates({
  required List<ReleaseAsset> assets,
  required String os,
  required Abi abi,
  required String version,
}) {
  final byName = {for (final asset in assets) asset.name: asset};
  final wanted = <String>[
    if (expectedAssetName(os: os, abi: abi, version: version) case final name?)
      name,
    if (expectedLatestAssetName(os: os, abi: abi) case final name?) name,
  ];
  final seen = <String>{};
  final candidates = <ReleaseAsset>[];
  for (final name in wanted) {
    final asset = byName[name];
    if (asset == null || !seen.add(asset.name)) continue;
    candidates.add(asset);
  }
  return candidates;
}

ReleaseAsset? resolveAsset({
  required List<ReleaseAsset> assets,
  required String os,
  required Abi abi,
  required String version,
}) {
  final candidates = resolveAssetCandidates(
    assets: assets,
    os: os,
    abi: abi,
    version: version,
  );
  return candidates.firstOrNull;
}

/// Latest-style aliases often ship without a `.sha256` sidecar; reuse the
/// versioned archive's checksum for the same release version only.
ReleaseAsset withInheritedChecksum(
  ReleaseAsset asset,
  List<ReleaseAsset> pool, {
  required String os,
  required Abi abi,
  required String version,
}) {
  if (asset.hasIntegrityMetadata) return asset;
  final donorName = expectedAssetName(os: os, abi: abi, version: version);
  if (donorName == null || donorName == asset.name) return asset;
  for (final other in pool) {
    if (other.name != donorName) continue;
    if (!other.hasIntegrityMetadata) continue;
    return asset.copyWith(sha256: other.sha256, checksumUrl: other.checksumUrl);
  }
  return asset;
}
