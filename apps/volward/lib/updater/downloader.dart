import 'dart:io';

import 'package:http/http.dart' as http;

import 'checksum.dart';
import 'update_models.dart';

typedef DownloadProgress = void Function(double progress);

abstract class Downloader {
  /// Resolves a usable SHA-256 for [asset], or `null` if none is available.
  ///
  /// Implementations should treat a missing/unreachable checksum sidecar as
  /// `null` (not throw), so callers can surface an integrity error before
  /// advertising an update as installable.
  Future<String?> resolveExpectedSha256(ReleaseAsset asset);

  /// Returns whether [asset.downloadUrl] appears reachable without downloading
  /// the full payload (HEAD, with a ranged GET fallback).
  Future<bool> isDownloadReachable(ReleaseAsset asset);

  Future<File> download(
    ReleaseAsset asset, {
    required Directory directory,
    DownloadProgress? onProgress,
  });
}

class HttpDownloader implements Downloader {
  HttpDownloader({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<String?> resolveExpectedSha256(ReleaseAsset asset) async {
    final inline = normalizeSha256(asset.sha256);
    if (inline != null) return inline;
    final checksumUrl = asset.checksumUrl;
    if (checksumUrl == null || checksumUrl.isEmpty) return null;

    final response = await _client.get(
      Uri.parse(checksumUrl),
      headers: const {
        'User-Agent': 'Volward-Updater',
        'Accept': 'text/plain, */*',
      },
    );
    if (response.statusCode != 200) return null;
    return parseSha256Checksum(response.body, assetName: asset.name);
  }

  @override
  Future<bool> isDownloadReachable(ReleaseAsset asset) async {
    final uri = Uri.parse(asset.downloadUrl);
    final head = await _client.send(
      http.Request('HEAD', uri)
        ..followRedirects = true
        ..headers['User-Agent'] = 'Volward-Updater'
        ..headers['Accept'] = '*/*',
    );
    await head.stream.drain<void>();
    if (head.statusCode == 200 || head.statusCode == 206) return true;

    // Some hosts reject HEAD; probe with a 1-byte ranged GET instead.
    if (head.statusCode == 403 ||
        head.statusCode == 405 ||
        head.statusCode == 501) {
      final ranged = await _client.send(
        http.Request('GET', uri)
          ..followRedirects = true
          ..headers['User-Agent'] = 'Volward-Updater'
          ..headers['Accept'] = '*/*'
          ..headers['Range'] = 'bytes=0-0',
      );
      await ranged.stream.drain<void>();
      return ranged.statusCode == 200 || ranged.statusCode == 206;
    }
    return false;
  }

  @override
  Future<File> download(
    ReleaseAsset asset, {
    required Directory directory,
    DownloadProgress? onProgress,
  }) async {
    await directory.create(recursive: true);
    final file = File('${directory.path}/${asset.name}');
    final request = http.Request('GET', Uri.parse(asset.downloadUrl))
      // GitHub asset URLs redirect to object storage.
      ..followRedirects = true
      ..headers['User-Agent'] = 'Volward-Updater'
      ..headers['Accept'] = '*/*';
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw StateError('Download failed: HTTP ${response.statusCode}');
    }
    final total = response.contentLength ?? asset.sizeBytes;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (asset.sizeBytes > 0 && received != asset.sizeBytes) {
      await file.delete();
      throw UpdateIntegrityException(
        'Download size mismatch: expected ${asset.sizeBytes}, got $received',
      );
    }
    final expectedSha256 = await resolveExpectedSha256(asset);
    if (expectedSha256 == null) {
      await file.delete();
      throw UpdateIntegrityException(
        'Missing SHA-256 checksum for ${asset.name}',
      );
    }
    final actualSha256 = await sha256File(file);
    if (actualSha256 != expectedSha256) {
      await file.delete();
      throw UpdateIntegrityException(
        'SHA-256 mismatch for ${asset.name}: '
        'expected $expectedSha256, got $actualSha256',
      );
    }
    onProgress?.call(1.0);
    return file;
  }
}
