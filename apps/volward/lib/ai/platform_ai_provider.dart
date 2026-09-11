import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_provider.dart';
import 'cancel_token.dart';
import 'platform_auth_store.dart';

const _kPlatformTimeout = Duration(seconds: 300);

class PlatformAiProvider implements AiProvider {
  PlatformAiProvider({
    required this.token,
    http.Client? client,
    String? baseUrl,
    this.requestTimeout = _kPlatformTimeout,
  }) : _ownsClient = client == null,
       _client = client ?? http.Client(),
       baseUrl = baseUrl ?? PlatformAuthStore.defaultBaseUrl;

  final String token;
  final String baseUrl;
  final Duration requestTimeout;
  final bool _ownsClient;
  http.Client _client;
  bool _clientClosed = false;

  int lastCreditsUsed = 0;
  int? lastCreditsRemaining;

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

  Future<String> _requireUserToken() async {
    final token = await PlatformAuthStore.instance.ensureUserToken();
    if (token == null || token.isEmpty) {
      await PlatformAuthStore.instance.clearUserToken();
      throw Exception('session_expired');
    }
    return token;
  }

  Future<http.Response> _authorizedRequest(
    Future<http.Response> Function(String token) makeRequest,
  ) async {
    var token = await _requireUserToken();
    var res = await makeRequest(token);
    if (res.statusCode != 401) {
      return res;
    }

    final refreshed = await PlatformAuthStore.instance.refreshSession();
    if (refreshed == null) {
      await PlatformAuthStore.instance.clearUserToken();
      throw Exception('session_expired');
    }
    final newToken = await PlatformAuthStore.instance.userToken();
    if (newToken == null || newToken.isEmpty) {
      await PlatformAuthStore.instance.clearUserToken();
      throw Exception('session_expired');
    }
    res = await makeRequest(newToken);
    if (res.statusCode == 401) {
      await PlatformAuthStore.instance.clearUserToken();
      throw Exception('session_expired');
    }
    return res;
  }

  @override
  Future<AiQuotaInfo?> queryQuota() async {
    _ensureConfigured();
    final res = await _authorizedRequest(
      (token) => _ensureClient()
          .get(
            Uri.parse('$baseUrl/ai/quota'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30)),
    );
    await _mapErrorStatus(res.statusCode);
    if (res.statusCode != 200) {
      throw Exception('api_error:${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final remaining = (body['credits_remaining'] as num?)?.toInt() ?? 0;
    final total = (body['credits_total'] as num?)?.toInt() ?? remaining;
    lastCreditsRemaining = remaining;
    return AiQuotaInfo(creditsRemaining: remaining, creditsTotal: total);
  }

  @override
  Future<AnalyzeResult> analyze(
    List<AiCandidate> candidates, {
    CancelToken? cancelToken,
  }) async {
    _ensureConfigured();
    cancelToken?.whenCancelled.then((_) => _abortClient());
    if (cancelToken?.isCancelled ?? false) {
      throw const CoverageCancelledException();
    }
    final payload = {
      'candidates': candidates
          .map(
            (c) => {
              'path': c.path,
              'size_bytes': c.sizeBytes,
              'is_dir': c.isDir,
              if (c.childCount != null) 'child_count': c.childCount,
              if (c.extension != null) 'extension': c.extension,
              if (c.cleanupSource != null && c.cleanupSource!.isNotEmpty)
                'cleanup_source': c.cleanupSource,
              if (c.cleanupHint != null && c.cleanupHint!.isNotEmpty)
                'cleanup_hint': c.cleanupHint,
              if (c.retentionDays != null) 'retention_days': c.retentionDays,
              // Never send member_paths to Platform proxy.
            },
          )
          .toList(),
    };

    final http.Response res;
    try {
      res = await _authorizedRequest(
        (token) => _ensureClient()
            .post(
              Uri.parse('$baseUrl/ai/analyze'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(payload),
            )
            .timeout(requestTimeout),
      );
    } on http.ClientException {
      if (cancelToken?.isCancelled ?? false) {
        throw const CoverageCancelledException();
      }
      rethrow;
    }

    await _mapErrorStatus(res.statusCode);
    if (res.statusCode != 200) {
      throw Exception('api_error:${res.statusCode}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    lastCreditsUsed = (body['credits_used'] as num?)?.toInt() ?? 1;
    lastCreditsRemaining = (body['credits_remaining'] as num?)?.toInt();
    final entries = body['entries'];
    if (entries is! List) {
      throw Exception('api_error:bad_entries');
    }
    final verdicts = entries
        .whereType<Map>()
        .map((e) => AiVerdict.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return AnalyzeResult(verdicts: verdicts, credits: lastCreditsUsed);
  }

  void _ensureConfigured() {
    if (baseUrl.trim().isEmpty) {
      throw StateError('platform_api_unconfigured');
    }
  }

  Future<void> _mapErrorStatus(int status) async {
    switch (status) {
      case 402:
        throw Exception('insufficient_credits');
      case 403:
        throw Exception('link_account_required');
    }
  }
}
