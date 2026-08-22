import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class PlatformUser {
  const PlatformUser({
    required this.userId,
    required this.email,
    required this.credits,
  });

  final String userId;
  final String email;
  final int credits;

  factory PlatformUser.fromJson(Map<String, dynamic> j) => PlatformUser(
    userId: (j['user_id'] ?? j['id'] ?? '') as String,
    email: (j['email'] ?? '') as String,
    credits: (j['credits'] as num?)?.toInt() ?? 0,
  );
}

/// Device + user JWT store for Volward Platform mode.
class PlatformAuthStore {
  PlatformAuthStore._();
  static final PlatformAuthStore instance = PlatformAuthStore._();

  static const _kUserToken = 'volward_platform_token';
  static const _kDeviceUuid = 'volward_device_uuid';
  static const _kDeviceToken = 'volward_device_token';
  static const _kCachedEmail = 'volward_platform_email';

  static const defaultBaseUrl = String.fromEnvironment(
    'VOLWARD_API_BASE',
    defaultValue: '',
  );

  final _secure = const FlutterSecureStorage(
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  http.Client? _client;
  String? _baseUrlOverride;

  @visibleForTesting
  String? debugUserToken;

  bool _debugTokenMode = false;

  @visibleForTesting
  void configureForTest({http.Client? client, String? baseUrl}) {
    _client = client;
    _baseUrlOverride = baseUrl;
  }

  @visibleForTesting
  Future<void> debugSetUserToken(String? token) async {
    _debugTokenMode = true;
    debugUserToken = token;
  }

  String get _base {
    final value = _baseUrlOverride ?? defaultBaseUrl;
    if (value.trim().isEmpty) {
      throw StateError('platform_api_unconfigured');
    }
    return value;
  }

  http.Client get _http => _client ?? http.Client();

  Future<String?> userToken() async {
    if (_debugTokenMode) return debugUserToken;
    return _secure.read(key: _kUserToken);
  }

  Future<void> clearUserToken() async {
    debugUserToken = null;
    if (_debugTokenMode) return;
    await _secure.delete(key: _kUserToken);
    await _secure.delete(key: _kCachedEmail);
  }

  Future<String> ensureDeviceRegistered() async {
    var uuid = await _secure.read(key: _kDeviceUuid);
    if (uuid == null || uuid.isEmpty) {
      uuid = _newUuidV4();
      await _secure.write(key: _kDeviceUuid, value: uuid);
    }

    final existingDeviceToken = await _secure.read(key: _kDeviceToken);
    final existingUser = await userToken();
    if (existingUser != null && existingUser.isNotEmpty) {
      return existingUser;
    }
    if (existingDeviceToken != null && existingDeviceToken.isNotEmpty) {
      return existingDeviceToken;
    }

    String appVersion = '0.0.0';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
    } catch (_) {}

    final platform = Platform.isMacOS
        ? 'macos'
        : Platform.isWindows
        ? 'windows'
        : Platform.isLinux
        ? 'linux'
        : 'unknown';

    final res = await _http
        .post(
          Uri.parse('$_base/device/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'device_uuid': uuid,
            'platform': platform,
            'app_version': appVersion,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      throw Exception('device_register_failed:${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final token = body['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('device_register_failed:missing_token');
    }
    await _secure.write(key: _kDeviceToken, value: token);
    return token;
  }

  Future<void> requestOtp(String email) async {
    final deviceToken = await ensureDeviceRegistered();
    final res = await _http
        .post(
          Uri.parse('$_base/auth/request-otp'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $deviceToken',
          },
          body: jsonEncode({'email': email.trim()}),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 429) {
      throw Exception('otp_resend_too_soon');
    }
    if (res.statusCode != 200) {
      throw Exception('otp_request_failed:${res.statusCode}');
    }
  }

  Future<PlatformUser> verifyOtp(String email, String code) async {
    final deviceToken = await ensureDeviceRegistered();
    final uuid = await _secure.read(key: _kDeviceUuid);
    final res = await _http
        .post(
          Uri.parse('$_base/auth/verify-otp'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $deviceToken',
          },
          body: jsonEncode({
            'email': email.trim(),
            'code': code.trim(),
            'device_uuid': uuid,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('otp_verify_failed:${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final token = body['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('otp_verify_failed:missing_token');
    }
    await _secure.write(key: _kUserToken, value: token);
    debugUserToken = token;
    await _secure.write(key: _kCachedEmail, value: email.trim());
    return PlatformUser.fromJson(body);
  }

  Future<PlatformUser?> currentUser() async {
    final token = await userToken();
    if (token == null || token.isEmpty) return null;
    final res = await _http
        .get(
          Uri.parse('$_base/auth/me'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 401) {
      await clearUserToken();
      return null;
    }
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return PlatformUser.fromJson(body);
  }

  static String _newUuidV4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String hex(int i) => i.toRadixString(16).padLeft(2, '0');
    final h = b.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
