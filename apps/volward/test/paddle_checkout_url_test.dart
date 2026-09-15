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

  test('accepts volwardapp.com pay link with _ptxn', () {
    expect(
      isAllowedPaddleCheckoutUrl(
        Uri.parse('https://volwardapp.com/pay?_ptxn=txn_01abc'),
      ),
      isTrue,
    );
  });

  test('rejects volwardapp.com pri path', () {
    expect(
      isAllowedPaddleCheckoutUrl(
        Uri.parse('https://www.volwardapp.com/pri_01abc'),
      ),
      isFalse,
    );
  });

  test('rejects volwardapp.com pay without _ptxn', () {
    expect(
      isAllowedPaddleCheckoutUrl(Uri.parse('https://volwardapp.com/pay')),
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
