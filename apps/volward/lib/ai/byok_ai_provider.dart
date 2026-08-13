import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_provider.dart';

const _kDefaultModel = 'deepseek-v4-flash';
// One verdict costs roughly 60–120 output tokens, so 40 paths per request
// stays well inside `_kMaxOutputTokens` even for verbose reasons.
const _kMaxBatchSize = 40;
const _kMaxOutputTokens = 8192;
const _kRequestTimeout = Duration(seconds: 90);
const _kEndpoint = 'https://api.deepseek.com/chat/completions';
const _kSystemPrompt = '''
You are a disk cleanup assistant. Given a list of file/directory paths with sizes,
classify each as one of: safe_to_remove | review_needed | keep.

Rules:
- safe_to_remove: build artifacts, package caches, temp files with no user data
- review_needed: unclear purpose or could contain user data
- keep: user documents, source code, personal files

Respond ONLY with a JSON array, one entry per input path:
[{"path": "...", "verdict": "safe_to_remove|review_needed|keep",
  "confidence": "high|medium|low", "reason": "one short sentence in the user's language"}]
''';

/// DeepSeek Chat Completions (OpenAI-compatible) BYOK provider.
///
/// Endpoint: `POST https://api.deepseek.com/chat/completions`
/// Auth: `Authorization: Bearer <api-key>`
class ByokAiProvider implements AiProvider {
  ByokAiProvider({
    required this.apiKey,
    this.model = _kDefaultModel,
    http.Client? client,
    this.requestTimeout = _kRequestTimeout,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String apiKey;
  final String model;
  final Duration requestTimeout;
  final http.Client _client;
  final bool _ownsClient;

  /// Call when the provider is no longer needed (closes owned client only).
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  @override
  Future<AiQuotaInfo?> queryQuota() async => null;

  @override
  Future<List<AiVerdict>> analyze(List<AiCandidate> candidates) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('empty_api_key');
    }
    final results = <AiVerdict>[];
    try {
      for (var i = 0; i < candidates.length; i += _kMaxBatchSize) {
        final end = (i + _kMaxBatchSize).clamp(0, candidates.length);
        results.addAll(await _analyzeBatch(candidates.sublist(i, end)));
      }
      return results;
    } finally {
      // Keep the client alive across batches within one analyze() call;
      // dispose() is for callers that own a long-lived provider instance.
    }
  }

  Future<List<AiVerdict>> _analyzeBatch(List<AiCandidate> batch) async {
    final userContent = batch.map((c) {
      final type = c.isDir ? 'dir' : 'file';
      final extra = c.childCount != null ? ', ${c.childCount} files' : '';
      return '${c.path} [$type$extra, ${_humanSize(c.sizeBytes)}]';
    }).join('\n');

    final body = jsonEncode({
      'model': model,
      'temperature': 0,
      'max_tokens': _kMaxOutputTokens,
      // Classification does not need chain-of-thought; thinking burns the
      // completion budget and can leave `content` empty when max_tokens is tight.
      'thinking': {'type': 'disabled'},
      'messages': [
        {'role': 'system', 'content': _kSystemPrompt},
        {'role': 'user', 'content': userContent},
      ],
    });

    for (var attempt = 0; attempt < 3; attempt++) {
      late final http.Response response;
      try {
        response = await _client
            .post(
              Uri.parse(_kEndpoint),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
              },
              body: body,
            )
            .timeout(requestTimeout);
      } on TimeoutException {
        throw Exception('request_timeout');
      } on http.ClientException catch (e) {
        throw Exception('network_error:$e');
      }

      if (response.statusCode == 429) {
        await Future.delayed(Duration(seconds: 1 << attempt));
        continue;
      }
      if (response.statusCode == 401) {
        throw Exception('invalid_api_key');
      }
      if (response.statusCode != 200) {
        throw Exception('api_error:${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return _unparsedBatch(batch, 'AI response is not a JSON object');
      }

      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) {
        return _unparsedBatch(batch, 'AI response missing choices');
      }
      final first = choices.first;
      if (first is! Map) {
        return _unparsedBatch(batch, 'AI choice is not an object');
      }
      final choice = Map<String, dynamic>.from(first);

      if (choice['finish_reason']?.toString() == 'length') {
        // Truncated JSON would silently drop verdicts; flag the whole batch
        // for manual review instead.
        return _unparsedBatch(batch, 'AI response was truncated');
      }

      final message = choice['message'];
      if (message is! Map) {
        return _unparsedBatch(batch, 'AI response missing message');
      }
      final text = message['content']?.toString() ?? '';
      try {
        final list = jsonDecode(_stripMarkdownFence(text)) as List;
        return list
            .map((e) => AiVerdict.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return _unparsedBatch(batch, 'AI response could not be parsed');
      }
    }
    throw Exception('rate_limited_after_retries');
  }

  /// Some models wrap JSON in ```json ... ```; strip if present.
  static String _stripMarkdownFence(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    final lines = trimmed.split('\n');
    if (lines.length < 3) return trimmed;
    // Drop first fence line and trailing ```.
    final end = lines.last.trim() == '```' ? lines.length - 1 : lines.length;
    return lines.sublist(1, end).join('\n').trim();
  }

  static List<AiVerdict> _unparsedBatch(
    List<AiCandidate> batch,
    String reason,
  ) =>
      batch
          .map(
            (c) => AiVerdict(
              path: c.path,
              verdict: 'review_needed',
              confidence: 'low',
              reason: reason,
            ),
          )
          .toList();

  static String _humanSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}
