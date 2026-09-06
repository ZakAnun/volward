import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_lifecycle.dart';

void main() {
  test('waitUntilReady resolves when predicate becomes true', () async {
    var ready = false;
    final result = waitUntilReady(
      isReady: () => ready,
      pollInterval: const Duration(milliseconds: 10),
      timeout: const Duration(milliseconds: 200),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    ready = true;
    expect(await result, isTrue);
  });

  test('waitUntilReady times out when predicate stays false', () async {
    final result = await waitUntilReady(
      isReady: () => false,
      pollInterval: const Duration(milliseconds: 10),
      timeout: const Duration(milliseconds: 50),
    );
    expect(result, isFalse);
  });
}
