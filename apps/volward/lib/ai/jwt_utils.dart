import 'dart:convert';

int? jwtExp(String token) {
  final parts = token.split('.');
  if (parts.length < 2) return null;
  try {
    var payload = parts[1];
    final mod = payload.length % 4;
    if (mod > 0) payload += '=' * (4 - mod);
    final decoded = utf8.decode(base64Url.decode(payload));
    final map = jsonDecode(decoded);
    if (map is! Map) return null;
    final exp = map['exp'];
    if (exp is int) return exp;
    if (exp is num) return exp.toInt();
    return null;
  } catch (_) {
    return null;
  }
}

bool isJwtExpiringSoon(
  String token, {
  Duration buffer = const Duration(days: 7),
}) {
  final exp = jwtExp(token);
  if (exp == null) return true;
  final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
  return DateTime.now().add(buffer).isAfter(expiry);
}
