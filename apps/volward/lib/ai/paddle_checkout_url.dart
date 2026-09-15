bool isAllowedPaddleCheckoutUrl(Uri uri) {
  if (uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  if (host == 'volwardapp.com' || host == 'www.volwardapp.com') return false;
  const exact = {
    'buy.paddle.com',
    'sandbox-buy.paddle.com',
    'checkout.paddle.com',
  };
  if (exact.contains(host)) return true;
  return host.endsWith('.paddle.com');
}
