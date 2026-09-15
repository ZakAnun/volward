bool _isVolwardPayCheckout(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host != 'volwardapp.com' && host != 'www.volwardapp.com') {
    return false;
  }
  final path = uri.path;
  final pathOk = path == '/pay' || path.startsWith('/pay/');
  if (!pathOk) return false;
  return uri.queryParameters.containsKey('_ptxn');
}

bool isAllowedPaddleCheckoutUrl(Uri uri) {
  if (uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  if (_isVolwardPayCheckout(uri)) return true;
  if (host == 'volwardapp.com' || host == 'www.volwardapp.com') return false;
  const exact = {
    'buy.paddle.com',
    'sandbox-buy.paddle.com',
    'checkout.paddle.com',
  };
  if (exact.contains(host)) return true;
  return host.endsWith('.paddle.com');
}
