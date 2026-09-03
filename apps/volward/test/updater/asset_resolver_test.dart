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

  test('resolveAsset prefers the versioned name used by v0.0.4', () {
    const mixed = [
      ReleaseAsset(
        name: 'volward-latest-macos-arm64.zip',
        downloadUrl: 'https://example.com/latest.zip',
        sizeBytes: 10,
      ),
      ReleaseAsset(
        name: 'volward-v0.0.5-macos-arm64.zip',
        downloadUrl: 'https://example.com/v005.zip',
        sizeBytes: 11,
      ),
    ];
    expect(
      resolveAsset(
        assets: mixed,
        os: 'macos',
        abi: Abi.macosArm64,
        version: '0.0.5',
      )?.name,
      'volward-v0.0.5-macos-arm64.zip',
    );
  });

  test(
    'resolveAsset falls back to the latest alias when the tag name is absent',
    () {
      const mixed = [
        ReleaseAsset(
          name: 'volward-latest-macos-arm64.zip',
          downloadUrl: 'https://example.com/latest.zip',
          sizeBytes: 10,
        ),
        ReleaseAsset(
          name: 'volward-v0.0.4-macos-arm64.zip',
          downloadUrl: 'https://example.com/v004.zip',
          sizeBytes: 11,
          checksumUrl: 'https://example.com/v004.zip.sha256',
        ),
      ];
      expect(
        resolveAsset(
          assets: mixed,
          os: 'macos',
          abi: Abi.macosArm64,
          version: '0.0.5',
        )?.name,
        'volward-latest-macos-arm64.zip',
      );
    },
  );

  test('resolveAsset does not pick a leftover older versioned archive', () {
    const mixed = [
      ReleaseAsset(
        name: 'volward-v0.0.4-macos-arm64.zip',
        downloadUrl: 'https://example.com/v004.zip',
        sizeBytes: 11,
      ),
    ];
    expect(
      resolveAsset(
        assets: mixed,
        os: 'macos',
        abi: Abi.macosArm64,
        version: '0.0.5',
      ),
      isNull,
    );
  });

  test('withInheritedChecksum copies the same-version sidecar', () {
    const latest = ReleaseAsset(
      name: 'volward-latest-macos-arm64.zip',
      downloadUrl: 'https://example.com/latest.zip',
      sizeBytes: 10,
    );
    const leftover = ReleaseAsset(
      name: 'volward-v0.0.4-macos-arm64.zip',
      downloadUrl: 'https://example.com/v004.zip',
      sizeBytes: 11,
      checksumUrl: 'https://example.com/v004.zip.sha256',
    );
    const versioned = ReleaseAsset(
      name: 'volward-v0.0.5-macos-arm64.zip',
      downloadUrl: 'https://example.com/v005.zip',
      sizeBytes: 11,
      checksumUrl: 'https://example.com/v005.zip.sha256',
    );
    expect(
      withInheritedChecksum(
        latest,
        [latest, leftover, versioned],
        os: 'macos',
        abi: Abi.macosArm64,
        version: '0.0.5',
      ).checksumUrl,
      versioned.checksumUrl,
    );
    expect(
      withInheritedChecksum(
        latest,
        [latest, leftover],
        os: 'macos',
        abi: Abi.macosArm64,
        version: '0.0.5',
      ).checksumUrl,
      isNull,
    );
  });
}
