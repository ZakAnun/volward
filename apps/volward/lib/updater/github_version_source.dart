import 'dart:convert';

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
      throw GitHubHttpException(
        'GitHub releases/latest failed: HTTP ${response.statusCode}',
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
