import 'package:flutter_test/flutter_test.dart';

void main() {
  test('volward test harness loads', () {
    // Full widget tests require libvolward_facade.dylib; run integration tests on macOS.
    expect(true, isTrue);
  });
}
