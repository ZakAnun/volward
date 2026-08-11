import 'dart:io';

import 'package:http/http.dart' as http;

import 'update_models.dart';

typedef DownloadProgress = void Function(double progress);

abstract class Downloader {
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
      throw StateError(
        'Download size mismatch: expected ${asset.sizeBytes}, got $received',
      );
    }
    onProgress?.call(1.0);
    return file;
  }
}
