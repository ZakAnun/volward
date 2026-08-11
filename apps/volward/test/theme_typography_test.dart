import 'package:flutter_test/flutter_test.dart';
import 'package:volward/theme/apple_tokens.dart';

void main() {
  test('typography families are not Apple-only hard bind', () {
    expect(AppleTypography.displayFamily.contains('AppleSystemUIFont'), isFalse);
    expect(AppleTypography.textFamily.contains('AppleSystemUIFont'), isFalse);
    expect(AppleTypography.displayFamily, isNotEmpty);
  });

  test('typography styles use cross-platform font fallbacks', () {
    expect(AppleTypography.fontFamilyFallback, isNotEmpty);
    expect(
      AppleTypography.fontFamilyFallback.contains('AppleSystemUIFont'),
      isFalse,
    );
    expect(AppleTypography.body.fontFamilyFallback, isNotEmpty);
    expect(AppleTypography.body.fontFamily, isNull);
  });
}
