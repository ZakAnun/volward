import 'package:aptabase_flutter/aptabase_flutter.dart';
import 'package:flutter/foundation.dart';

import 'aptabase_analytics.dart';
import 'noop_analytics.dart';

/// Product analytics facade. Business code should depend on this type only.
abstract class Analytics {
  Future<void> track(String name, [Map<String, Object?>? props]);

  /// Global sink used by app code. Defaults to [NoopAnalytics].
  static Analytics instance = const NoopAnalytics();

  /// Reads compile-time defines and wires Aptabase or Noop.
  ///
  /// Requires both `APTABASE_APP_KEY` and `APTABASE_HOST`. Either missing → Noop.
  static Future<void> bootstrap() async {
    const key = String.fromEnvironment('APTABASE_APP_KEY');
    const host = String.fromEnvironment('APTABASE_HOST');
    if (key.isEmpty || host.isEmpty) {
      instance = const NoopAnalytics();
      return;
    }

    try {
      await Aptabase.init(key, const InitOptions(host: host));
      instance = const AptabaseAnalytics();
    } catch (e, st) {
      debugPrint('Analytics bootstrap failed: $e\n$st');
      instance = const NoopAnalytics();
    }
  }
}

/// Keeps only Aptabase-supported property types (`String` / `num`).
Map<String, dynamic> filterAnalyticsProps(Map<String, Object?>? props) {
  if (props == null || props.isEmpty) return const <String, dynamic>{};
  final filtered = <String, dynamic>{};
  for (final entry in props.entries) {
    final value = entry.value;
    if (value is String || value is num) {
      filtered[entry.key] = value;
    }
  }
  return filtered;
}
