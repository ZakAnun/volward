import 'package:aptabase_flutter/aptabase_flutter.dart';
import 'package:flutter/foundation.dart';

import 'analytics.dart';

/// Aptabase-backed [Analytics] implementation.
class AptabaseAnalytics implements Analytics {
  const AptabaseAnalytics();

  @override
  Future<void> track(String name, [Map<String, Object?>? props]) async {
    try {
      final filtered = filterAnalyticsProps(props);
      await Aptabase.instance.trackEvent(
        name,
        filtered.isEmpty ? null : filtered,
      );
    } catch (e, st) {
      debugPrint('Analytics track failed: $e\n$st');
    }
  }
}
