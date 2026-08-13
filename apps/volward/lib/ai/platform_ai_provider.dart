import 'ai_provider.dart';

class PlatformAiProvider implements AiProvider {
  PlatformAiProvider({
    this.token,
    // ignore: unused_element_parameter — wired in Platform Auth task
    Object? client,
    this.baseUrl = const String.fromEnvironment(
      'VOLWARD_API_BASE',
      defaultValue: 'https://api.yourdomain.com/v1',
    ),
  });

  final String? token;
  final String baseUrl;
  int lastCreditsUsed = 0;

  @override
  Future<List<AiVerdict>> analyze(List<AiCandidate> candidates) {
    throw UnimplementedError('Platform mode not yet available');
  }

  @override
  Future<AiQuotaInfo?> queryQuota() async => null;
}
