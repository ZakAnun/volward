import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_contract.dart';
import 'ai_provider.dart';
import 'cancel_token.dart';
import '../volward_session.dart';

const _kRequestTimeout = Duration(seconds: 90);

class ByokTokenUsage {
  const ByokTokenUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
}

/// DeepSeek Chat Completions BYOK provider (transport only).
///
/// Request/parse/batch/endpoint come from [AiContract] (FFI in production).
class ByokAiProvider implements AiProvider {
  ByokAiProvider({
    required this.apiKey,
    this.contract,
    http.Client? client,
    this.requestTimeout = _kRequestTimeout,
  }) : _ownsClient = client == null,
       _client = client ?? http.Client();

  final String apiKey;
  final Duration requestTimeout;
  final AiContract? contract;
  final bool _ownsClient;
  http.Client _client;
  bool _clientClosed = false;
  bool _tokenUsageComplete = true;

  /// Legacy accessor used by cost estimate UI; model is owned by the contract.
  String get model => 'deepseek-v4-flash';

  ByokTokenUsage? lastTokenUsage;
  bool get hasReliableTokenUsage =>
      lastTokenUsage != null && _tokenUsageComplete;

  AiContract _resolveContract() {
    final injected = contract;
    if (injected != null) return injected;
    final session = VolwardSession.instance;
    if (session == null) {
      throw Exception('ai_contract_unavailable');
    }
    return SessionAiContract(session);
  }

  /// Call when the provider is no longer needed (closes owned client only).
  void dispose() {
    if (_ownsClient) {
      try {
        _client.close();
      } catch (_) {}
    }
  }

  http.Client _ensureClient() {
    if (_clientClosed) {
      _client = http.Client();
      _clientClosed = false;
    }
    return _client;
  }

  void _abortClient() {
    _clientClosed = true;
    try {
      _client.close();
    } catch (_) {}
  }

  @override
  Future<AiQuotaInfo?> queryQuota() async => null;

  @override
  Future<AnalyzeResult> analyze(
    List<AiCandidate> candidates, {
    CancelToken? cancelToken,
  }) async {
    lastTokenUsage = null;
    _tokenUsageComplete = true;
    if (apiKey.trim().isEmpty) {
      throw Exception('empty_api_key');
    }
    final contract = _resolveContract();
    final size = contract.batchSize();
    final out = <AiVerdict>[];
    var promptTokens = 0;
    var completionTokens = 0;
    var estimated = false;
    for (var i = 0; i < candidates.length; i += size) {
      final end = i + size < candidates.length ? i + size : candidates.length;
      final sub = await _analyzeBatch(
        contract,
        candidates.sublist(i, end),
        cancelToken: cancelToken,
      );
      out.addAll(sub.verdicts);
      promptTokens += sub.promptTokens;
      completionTokens += sub.completionTokens;
      estimated = estimated || sub.estimated;
      // Reflect completed batches incrementally so a later failure still
      // leaves the partial usage for the caller (workspace) to record.
      lastTokenUsage = ByokTokenUsage(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: promptTokens + completionTokens,
      );
      _tokenUsageComplete = !estimated;
    }
    return AnalyzeResult(
      verdicts: out,
      tokens: promptTokens + completionTokens,
      credits: 0,
      inputTokens: promptTokens,
      outputTokens: completionTokens,
      estimated: estimated,
    );
  }

  Future<
    ({
      List<AiVerdict> verdicts,
      int promptTokens,
      int completionTokens,
      bool estimated,
    })
  >
  _analyzeBatch(
    AiContract contract,
    List<AiCandidate> batch, {
    CancelToken? cancelToken,
  }) async {
    final body = contract.buildRequestJson(batch);
    final endpoint = contract.upstreamEndpoint();
    cancelToken?.whenCancelled.then((_) => _abortClient());
    for (var attempt = 0; attempt < 3; attempt++) {
      if (cancelToken?.isCancelled ?? false) {
        throw const CoverageCancelledException();
      }
      late final http.Response response;
      try {
        response = await _ensureClient()
            .post(
              Uri.parse(endpoint),
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
        if (cancelToken?.isCancelled ?? false) {
          throw const CoverageCancelledException();
        }
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
      final usage = _extractTokenUsage(response.body, batch);
      return (
        verdicts: contract.parseResponseJson(response.body, batch),
        promptTokens: usage.promptTokens,
        completionTokens: usage.completionTokens,
        estimated: usage.estimated,
      );
    }
    throw Exception('rate_limited_after_retries');
  }

  ({int promptTokens, int completionTokens, bool estimated}) _extractTokenUsage(
    String responseBody,
    List<AiCandidate> batch,
  ) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map) {
        return _estimatedUsage(batch);
      }
      final usage = decoded['usage'];
      if (usage is! Map) {
        return _estimatedUsage(batch);
      }
      final promptTokens = (usage['prompt_tokens'] as num?)?.toInt();
      final completionTokens = (usage['completion_tokens'] as num?)?.toInt();
      if (promptTokens == null || completionTokens == null) {
        return _estimatedUsage(batch);
      }
      return (
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        estimated: false,
      );
    } catch (_) {
      return _estimatedUsage(batch);
    }
  }

  ({int promptTokens, int completionTokens, bool estimated}) _estimatedUsage(
    List<AiCandidate> batch,
  ) {
    return (
      promptTokens: batch.length * 8 + 200,
      completionTokens: batch.length * 40,
      estimated: true,
    );
  }
}
