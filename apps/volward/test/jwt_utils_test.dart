import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/jwt_utils.dart';

void main() {
  // exp = 2000000000 (2033-05-18)
  const payload = 'eyJhbGciOiJub25lIn0.eyJleHAiOjIwMDAwMDAwMDB9.';
  const token = '${payload}sig';

  test('jwtExp reads exp claim', () {
    expect(jwtExp(token), 2000000000);
  });

  test('isJwtExpiringSoon false when far from expiry', () {
    expect(isJwtExpiringSoon(token), isFalse);
  });
}
