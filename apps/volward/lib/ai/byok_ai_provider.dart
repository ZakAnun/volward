import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_contract.dart';
import 'ai_provider.dart';
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
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String apiKey;
  final Duration requestTimeout;
  final AiContract? contract;
  final http.Client _client;
  final bool _ownsClient;
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
      _client.close();
    }
  }

  @override
  Future<AiQuotaInfo?> queryQuota() async => null;

  @override
  Future<List<AiVerdict>> analyze(List<AiCandidate> candidates) async {
    lastTokenUsage = null;
    _tokenUsageComplete = true;
    if (apiKey.trim().isEmpty) {
      throw Exception('empty_api_key');
    }
    final contract = _resolveContract();
    final size = contract.batchSize();
    final out = <AiVerdict>[];
    for (var i = 0; i < candidates.length; i += size) {
      final end = i + size < candidates.length ? i + size : candidates.length;
      out.addAll(await _analyzeBatch(contract, candidates.sublist(i, end)));
    }
    return out;
  }

  Future<List<AiVerdict>> _analyzeBatch(
    AiContract contract,
    List<AiCandidate> batch,
  ) async {
    final body = contract.buildRequestJson(batch);
    final endpoint = contract.upstreamEndpoint();
    for (var attempt = 0; attempt < 3; attempt++) {
      late final http.Response response;
      try {
        response = await _client
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
      _recordTokenUsage(response.body, batch);
      return contract.parseResponseJson(response.body, batch);
    }
    throw Exception('rate_limited_after_retries');
  }

  void _recordTokenUsage(String responseBody, List<AiCandidate> batch) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map) {
        _recordEstimatedTokenUsage(batch);
        return;
      }
      final usage = decoded['usage'];
      if (usage is! Map) {
        _recordEstimatedTokenUsage(batch);
        return;
      }
      final promptTokens = (usage['prompt_tokens'] as num?)?.toInt();
      final completionTokens = (usage['completion_tokens'] as num?)?.toInt();
      if (promptTokens == null || completionTokens == null) {
        _recordEstimatedTokenUsage(batch);
        return;
      }
      final totalTokens =
          (usage['total_tokens'] as num?)?.toInt() ??
          promptTokens + completionTokens;
      _accumulateTokenUsage(
        ByokTokenUsage(
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          totalTokens: totalTokens,
        ),
      );
    } catch (_) {
      _recordEstimatedTokenUsage(batch);
    }
  }

  void _recordEstimatedTokenUsage(List<AiCandidate> batch) {
    _tokenUsageComplete = false;
    final promptTokens = batch.length * 8 + 200;
    final completionTokens = batch.length * 40;
    _accumulateTokenUsage(
      ByokTokenUsage(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: promptTokens + completionTokens,
      ),
    );
  }

  void _accumulateTokenUsage(ByokTokenUsage usage) {
    final previous = lastTokenUsage;
    lastTokenUsage = ByokTokenUsage(
      promptTokens: (previous?.promptTokens ?? 0) + usage.promptTokens,
      completionTokens:
          (previous?.completionTokens ?? 0) + usage.completionTokens,
      totalTokens: (previous?.totalTokens ?? 0) + usage.totalTokens,
    );
  }
}
