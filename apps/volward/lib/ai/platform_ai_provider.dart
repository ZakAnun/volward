import 'ai_provider.dart';

class PlatformAiProvider implements AiProvider {
  @override
  Future<List<AiVerdict>> analyze(List<AiCandidate> candidates) {
    throw UnimplementedError('Platform mode not yet available');
  }

  @override
  Future<AiQuotaInfo?> queryQuota() async => null;
}
