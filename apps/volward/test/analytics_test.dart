import 'package:flutter_test/flutter_test.dart';
import 'package:volward/analytics/analytics.dart';
import 'package:volward/analytics/noop_analytics.dart';

void main() {
  test('NoopAnalytics.track does not throw', () async {
    const analytics = NoopAnalytics();
    await analytics.track('app_open');
    await analytics.track('scan_started', {'incremental': 1, 'path': '/tmp'});
  });

  test('filterAnalyticsProps keeps only String and num', () {
    final filtered = filterAnalyticsProps({
      'incremental': 1,
      'ok': true,
      'label': 'scan',
      'nested': {'a': 1},
      'empty': null,
      'ratio': 1.5,
    });

    expect(filtered, {'incremental': 1, 'label': 'scan', 'ratio': 1.5});
  });

  test('filterAnalyticsProps handles null and empty', () {
    expect(filterAnalyticsProps(null), isEmpty);
    expect(filterAnalyticsProps(const {}), isEmpty);
  });

  test('bootstrap without defines keeps NoopAnalytics', () async {
    Analytics.instance = const NoopAnalytics();
    await Analytics.bootstrap();
    expect(Analytics.instance, isA<NoopAnalytics>());
  });
}
