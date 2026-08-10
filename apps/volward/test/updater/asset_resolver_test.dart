import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/updater/asset_resolver.dart';
import 'package:volward/updater/update_models.dart';

void main() {
  const assets = [
    ReleaseAsset(
      name: 'volward-v0.0.2-macos-arm64.zip',
      downloadUrl: 'https://example.com/arm64.zip',
      sizeBytes: 10,
    ),
    ReleaseAsset(
      name: 'volward-v0.0.2-macos-x64.zip',
      downloadUrl: 'https://example.com/x64.zip',
      sizeBytes: 11,
    ),
    ReleaseAsset(
      name: 'VolwardSetup-v0.0.2-windows-x64.exe',
      downloadUrl: 'https://example.com/setup.exe',
      sizeBytes: 12,
    ),
    ReleaseAsset(
      name: 'Volward-v0.0.2-linux-x86_64.AppImage',
      downloadUrl: 'https://example.com/app.AppImage',
      sizeBytes: 13,
    ),
  ];

  test('expectedAssetName matches CI conventions', () {
    expect(
      expectedAssetName(os: 'macos', abi: Abi.macosArm64, version: '0.0.2'),
      'volward-v0.0.2-macos-arm64.zip',
    );
    expect(
      expectedAssetName(os: 'macos', abi: Abi.macosX64, version: '0.0.2'),
      'volward-v0.0.2-macos-x64.zip',
    );
    expect(
      expectedAssetName(os: 'windows', abi: Abi.windowsX64, version: '0.0.2'),
      'VolwardSetup-v0.0.2-windows-x64.exe',
    );
    expect(
      expectedAssetName(os: 'linux', abi: Abi.linuxX64, version: '0.0.2'),
      'Volward-v0.0.2-linux-x86_64.AppImage',
    );
  });

  test('resolveAsset picks the matching asset', () {
    final asset = resolveAsset(
      assets: assets,
      os: 'macos',
      abi: Abi.macosArm64,
      version: '0.0.2',
    );
    expect(asset?.name, 'volward-v0.0.2-macos-arm64.zip');
  });

  test('resolveAsset returns null when missing', () {
    final asset = resolveAsset(
      assets: assets,
      os: 'linux',
      abi: Abi.linuxArm64,
      version: '0.0.2',
    );
    expect(asset, isNull);
  });
}
