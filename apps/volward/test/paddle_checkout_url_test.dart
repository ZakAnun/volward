import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/paddle_checkout_url.dart';

void main() {
  test('accepts sandbox-buy.paddle.com', () {
    expect(
      isAllowedPaddleCheckoutUrl(
        Uri.parse('https://sandbox-buy.paddle.com/checkout?_ptxn=x'),
      ),
      isTrue,
    );
  });

  test('rejects volwardapp.com', () {
    expect(
      isAllowedPaddleCheckoutUrl(
        Uri.parse('https://www.volwardapp.com/pri_01abc'),
      ),
      isFalse,
    );
  });

  test('rejects example.com', () {
    expect(
      isAllowedPaddleCheckoutUrl(
        Uri.parse('https://example.com/checkout?pack=starter'),
      ),
      isFalse,
    );
  });
}
