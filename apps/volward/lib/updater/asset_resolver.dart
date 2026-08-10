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

ReleaseAsset? resolveAsset({
  required List<ReleaseAsset> assets,
  required String os,
  required Abi abi,
  required String version,
}) {
  final name = expectedAssetName(os: os, abi: abi, version: version);
  if (name == null) return null;
  for (final asset in assets) {
    if (asset.name == name) return asset;
  }
  return null;
}
