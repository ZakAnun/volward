import 'analytics.dart';

/// Drop-in analytics sink used when Aptabase is not configured.
class NoopAnalytics implements Analytics {
  const NoopAnalytics();

  @override
  Future<void> track(String name, [Map<String, Object?>? props]) async {}
}
