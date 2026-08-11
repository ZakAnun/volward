import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'update_models.dart';
import 'version_compare.dart';
import 'version_source.dart';

const kDefaultGitHubOwner = 'ZakAnun';
const kDefaultGitHubRepo = 'volward';

ReleaseInfo parseGitHubLatestRelease(Map<String, dynamic> json) {
  final tag = json['tag_name'] as String? ?? '';
  final version = normalizeReleaseTag(tag);
  if (version == null) {
    throw FormatException('Unsupported release tag: $tag');
  }
  final assetsJson = json['assets'] as List<dynamic>? ?? const [];
  final assets = <ReleaseAsset>[];
  for (final raw in assetsJson) {
    final map = raw as Map<String, dynamic>;
    final name = map['name'] as String? ?? '';
    final url = map['browser_download_url'] as String? ?? '';
    final size = (map['size'] as num?)?.toInt() ?? 0;
    if (name.isEmpty || url.isEmpty) continue;
    assets.add(ReleaseAsset(name: name, downloadUrl: url, sizeBytes: size));
  }
  return ReleaseInfo(
    tagName: tag,
    version: version,
    htmlUrl: json['html_url'] as String? ?? '',
    body: json['body'] as String? ?? '',
    assets: assets,
  );
}

/// Extracts `v0.0.1` from `https://github.com/o/r/releases/tag/v0.0.1`.
String? tagFromReleasePageUrl(Uri url) {
  final segments = url.pathSegments;
  final tagIndex = segments.indexOf('tag');
  if (tagIndex < 0 || tagIndex + 1 >= segments.length) return null;
  final releasesIndex = segments.indexOf('releases');
  if (releasesIndex < 0 || releasesIndex + 1 != tagIndex) return null;
  return segments[tagIndex + 1];
}

/// Builds download URLs from CI asset naming when the Releases API is unavailable.
List<ReleaseAsset> conventionReleaseAssets({
  required String owner,
  required String repo,
  required String tagName,
  required String version,
}) {
  final names = <String>[
    'volward-v$version-macos-arm64.zip',
    'volward-v$version-macos-x64.zip',
    'VolwardSetup-v$version-windows-x64.exe',
    'Volward-v$version-linux-x86_64.AppImage',
  ];
  return [
    for (final name in names)
      ReleaseAsset(
        name: name,
        downloadUrl:
            'https://github.com/$owner/$repo/releases/download/$tagName/$name',
        sizeBytes: 0,
      ),
  ];
}

class GitHubVersionSource implements VersionSource {
  GitHubVersionSource({
    http.Client? client,
    this.owner = kDefaultGitHubOwner,
    this.repo = kDefaultGitHubRepo,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String owner;
  final String repo;

  @override
  Future<ReleaseInfo> fetchLatest() async {
    // Prefer the public release page redirect: unauthenticated api.github.com
    // is easily rate-limited (60 req/hour/IP) and returns HTTP 403.
    try {
      return await _fetchLatestViaReleasePage();
    } catch (error, stackTrace) {
      debugPrint(
        'GitHubVersionSource: release-page lookup failed, falling back to API: '
        '$error\n$stackTrace',
      );
      return _fetchLatestViaApi();
    }
  }

  Future<ReleaseInfo> _fetchLatestViaReleasePage() async {
    final uri = Uri.https('github.com', '/$owner/$repo/releases/latest');
    // Do not auto-follow: we need the Location header that points at /tag/vX.Y.Z.
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers['User-Agent'] = 'Volward-Updater'
      ..headers['Accept'] = 'text/html';
    final streamed = await _client.send(request);
    await streamed.stream.drain<void>();

    final location = streamed.headers['location'];
    final redirected = (location == null || location.isEmpty)
        ? null
        : uri.resolve(location);
    final tagUrl = redirected ?? streamed.request?.url ?? uri;
    // Some environments still land on 200 with the final URL after a proxy.
    if (streamed.statusCode != 302 &&
        streamed.statusCode != 301 &&
        streamed.statusCode != 303 &&
        streamed.statusCode != 307 &&
        streamed.statusCode != 308 &&
        streamed.statusCode != 200) {
      throw GitHubHttpException(
        'GitHub release page failed: HTTP ${streamed.statusCode}',
      );
    }

    final tag = tagFromReleasePageUrl(tagUrl);
    if (tag == null) {
      throw GitHubHttpException(
        'Could not resolve latest release tag from $tagUrl '
        '(status=${streamed.statusCode}, location=$location)',
      );
    }
    final version = normalizeReleaseTag(tag);
    if (version == null) {
      throw FormatException('Unsupported release tag: $tag');
    }
    return ReleaseInfo(
      tagName: tag,
      version: version,
      htmlUrl: 'https://github.com/$owner/$repo/releases/tag/$tag',
      body: '',
      assets: conventionReleaseAssets(
        owner: owner,
        repo: repo,
        tagName: tag,
        version: version,
      ),
    );
  }

  Future<ReleaseInfo> _fetchLatestViaApi() async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/$owner/$repo/releases/latest',
    );
    final response = await _client.get(
      uri,
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Volward-Updater',
      },
    );
    if (response.statusCode != 200) {
      final hint = response.statusCode == 403
          ? ' (API rate limit exceeded for unauthenticated requests)'
          : '';
      throw GitHubHttpException(
        'GitHub releases/latest failed: HTTP ${response.statusCode}$hint',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return parseGitHubLatestRelease(json);
  }
}

class GitHubHttpException implements Exception {
  GitHubHttpException(this.message);
  final String message;
  @override
  String toString() => message;
}
