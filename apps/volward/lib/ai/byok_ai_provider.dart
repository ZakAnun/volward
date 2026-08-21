import 'dart:async';

import 'package:http/http.dart' as http;

import 'ai_contract.dart';
import 'ai_provider.dart';
import '../volward_session.dart';

const _kRequestTimeout = Duration(seconds: 90);

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

  /// Legacy accessor used by cost estimate UI; model is owned by the contract.
  String get model => 'deepseek-v4-flash';

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
      return contract.parseResponseJson(response.body, batch);
    }
    throw Exception('rate_limited_after_retries');
  }
}
