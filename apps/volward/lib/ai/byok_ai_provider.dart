import 'dart:convert';
import 'package:http/http.dart' as http;
import 'ai_provider.dart';

const _kDefaultModel = 'claude-haiku-4-5-20251001';
// One verdict costs roughly 60–120 output tokens, so 40 paths per request
// stays well inside `_kMaxOutputTokens` even for verbose reasons.
const _kMaxBatchSize = 40;
const _kMaxOutputTokens = 8192;
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

class ByokAiProvider implements AiProvider {
  final String apiKey;
  final String model;
  const ByokAiProvider({required this.apiKey, this.model = _kDefaultModel});

  @override
  Future<AiQuotaInfo?> queryQuota() async => null;

  @override
  Future<List<AiVerdict>> analyze(List<AiCandidate> candidates) async {
    final results = <AiVerdict>[];
    for (var i = 0; i < candidates.length; i += _kMaxBatchSize) {
      final end = (i + _kMaxBatchSize).clamp(0, candidates.length);
      results.addAll(await _analyzeBatch(candidates.sublist(i, end)));
    }
    return results;
  }

  Future<List<AiVerdict>> _analyzeBatch(List<AiCandidate> batch) async {
    final userContent = batch.map((c) {
      final type = c.isDir ? 'dir' : 'file';
      final extra = c.childCount != null ? ', ${c.childCount} files' : '';
      return '${c.path} [$type$extra, ${_humanSize(c.sizeBytes)}]';
    }).join('\n');

    final body = jsonEncode({
      'model': model,
      'max_tokens': _kMaxOutputTokens,
      'system': _kSystemPrompt,
      'messages': [
        {'role': 'user', 'content': userContent},
      ],
    });

    for (var attempt = 0; attempt < 3; attempt++) {
      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: body,
      );
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
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final text = (decoded['content'] as List).first['text'] as String;
      if (decoded['stop_reason'] == 'max_tokens') {
        // Truncated JSON would silently drop verdicts; flag the whole batch
        // for manual review instead.
        return _unparsedBatch(batch, 'AI response was truncated');
      }
      try {
        final list = jsonDecode(text) as List;
        return list
            .map((e) => AiVerdict.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return _unparsedBatch(batch, 'AI response could not be parsed');
      }
    }
    throw Exception('rate_limited_after_retries');
  }

  static List<AiVerdict> _unparsedBatch(
    List<AiCandidate> batch,
    String reason,
  ) => batch
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
