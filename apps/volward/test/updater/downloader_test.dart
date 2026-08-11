import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:volward/updater/downloader.dart';
import 'package:volward/updater/update_models.dart';

const _bytesSha256 =
    '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';

void main() {
  test('downloads and verifies a sha256 sidecar', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('.sha256')) {
        return http.Response('$_bytesSha256  package.zip\n', 200);
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    final directory = await Directory.systemTemp.createTemp(
      'volward_downloader_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final file = await HttpDownloader(client: client).download(
      const ReleaseAsset(
        name: 'package.zip',
        downloadUrl: 'https://example.invalid/package.zip',
        checksumUrl: 'https://example.invalid/package.zip.sha256',
        sizeBytes: 3,
      ),
      directory: directory,
    );

    expect(await file.readAsBytes(), [1, 2, 3]);
  });

  test('deletes the download when sha256 does not match', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('.sha256')) {
        return http.Response(
            '${List.filled(64, '0').join()}  package.zip\n', 200);
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    final directory = await Directory.systemTemp.createTemp(
      'volward_downloader_mismatch_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    await expectLater(
      HttpDownloader(client: client).download(
        const ReleaseAsset(
          name: 'package.zip',
          downloadUrl: 'https://example.invalid/package.zip',
          checksumUrl: 'https://example.invalid/package.zip.sha256',
          sizeBytes: 3,
        ),
        directory: directory,
      ),
      throwsA(isA<UpdateIntegrityException>()),
    );

    expect(await File('${directory.path}/package.zip').exists(), isFalse);
  });

  test('resolveExpectedSha256 returns null when sidecar is missing', () async {
    final client = MockClient((request) async {
      return http.Response('not found', 404);
    });

    final sha = await HttpDownloader(client: client).resolveExpectedSha256(
      const ReleaseAsset(
        name: 'package.zip',
        downloadUrl: 'https://example.invalid/package.zip',
        checksumUrl: 'https://example.invalid/package.zip.sha256',
        sizeBytes: 3,
      ),
    );

    expect(sha, isNull);
  });

  test('isDownloadReachable accepts HEAD 200', () async {
    final client = MockClient((request) async {
      expect(request.method, 'HEAD');
      return http.Response('', 200);
    });

    final reachable = await HttpDownloader(client: client).isDownloadReachable(
      const ReleaseAsset(
        name: 'package.zip',
        downloadUrl: 'https://example.invalid/package.zip',
        sizeBytes: 3,
      ),
    );

    expect(reachable, isTrue);
  });

  test('isDownloadReachable falls back to ranged GET when HEAD is rejected',
      () async {
    final client = MockClient((request) async {
      if (request.method == 'HEAD') {
        return http.Response('', 405);
      }
      expect(request.method, 'GET');
      expect(request.headers['Range'], 'bytes=0-0');
      return http.Response.bytes([1], 206);
    });

    final reachable = await HttpDownloader(client: client).isDownloadReachable(
      const ReleaseAsset(
        name: 'package.zip',
        downloadUrl: 'https://example.invalid/package.zip',
        sizeBytes: 3,
      ),
    );

    expect(reachable, isTrue);
  });

  test('isDownloadReachable returns false on 404', () async {
    final client = MockClient((request) async {
      return http.Response('missing', 404);
    });

    final reachable = await HttpDownloader(client: client).isDownloadReachable(
      const ReleaseAsset(
        name: 'package.zip',
        downloadUrl: 'https://example.invalid/package.zip',
        sizeBytes: 3,
      ),
    );

    expect(reachable, isFalse);
  });
}
