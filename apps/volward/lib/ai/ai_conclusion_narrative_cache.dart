import 'dart:convert';
import 'dart:io';

/// Disk cache for synthesized conclusion narratives, stored next to the
/// `ai_analysis` result files and keyed by result cache key + content hash.
class ConclusionNarrativeCache {
  const ConclusionNarrativeCache(this.cacheDir);

  final Directory cacheDir;

  File _file(String resultCacheKey) {
    final safeKey = resultCacheKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File('${cacheDir.path}/ai_analysis/$safeKey.narrative.json');
  }

  /// Returns cached text only when [contentHash] matches the stored entry.
  Future<String?> read(String resultCacheKey, String contentHash) async {
    if (resultCacheKey.isEmpty || contentHash.isEmpty) return null;
    final file = _file(resultCacheKey);
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      if (decoded['content_hash'] != contentHash) return null;
      final text = decoded['text'];
      if (text is! String || text.trim().isEmpty) return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(
    String resultCacheKey,
    String contentHash,
    String text,
  ) async {
    if (resultCacheKey.isEmpty || contentHash.isEmpty || text.isEmpty) return;
    final file = _file(resultCacheKey);
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'schema_version': 1,
          'content_hash': contentHash,
          'text': text,
        }),
      );
    } catch (_) {}
  }
}
