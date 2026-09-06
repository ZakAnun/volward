import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_lifecycle.dart';

void main() {
  test('hidden lifecycle does not mark app quit', () {
    expect(shouldMarkAppQuitOnLifecycle(AppLifecycleState.hidden), isFalse);
  });

  test('paused lifecycle does not mark app quit on desktop', () {
    expect(shouldMarkAppQuitOnLifecycle(AppLifecycleState.paused), isFalse);
  });

  test('detached lifecycle marks app quit', () {
    expect(shouldMarkAppQuitOnLifecycle(AppLifecycleState.detached), isTrue);
  });
}
