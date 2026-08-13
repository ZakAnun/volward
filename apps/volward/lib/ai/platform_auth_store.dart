import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device + user JWT store for Volward Platform mode.
/// Full register/OTP flow lands in a later task; Task 2 only needs [userToken].
class PlatformAuthStore {
  PlatformAuthStore._();
  static final PlatformAuthStore instance = PlatformAuthStore._();

  static const _kUserToken = 'volward_platform_token';
  static const _kDeviceUuid = 'volward_device_uuid';

  final _secure = const FlutterSecureStorage(
    mOptions: MacOsOptions(
      useDataProtectionKeyChain: false,
    ),
  );

  @visibleForTesting
  String? debugUserToken;

  Future<String?> userToken() async {
    if (debugUserToken != null) return debugUserToken;
    return _secure.read(key: _kUserToken);
  }

  Future<void> clearUserToken() async {
    debugUserToken = null;
    await _secure.delete(key: _kUserToken);
  }

  @visibleForTesting
  Future<void> debugSetUserToken(String? token) async {
    debugUserToken = token;
    if (token == null) {
      await _secure.delete(key: _kUserToken);
    } else {
      await _secure.write(key: _kUserToken, value: token);
    }
  }

  // Placeholders for Task 6 — keep API surface stable.
  Future<String> ensureDeviceRegistered() async {
    throw UnimplementedError('PlatformAuthStore.ensureDeviceRegistered');
  }

  Future<void> requestOtp(String email) async {
    throw UnimplementedError('PlatformAuthStore.requestOtp');
  }

  Future<PlatformUser> verifyOtp(String email, String code) async {
    throw UnimplementedError('PlatformAuthStore.verifyOtp');
  }

  Future<PlatformUser?> currentUser() async => null;

  String get deviceUuidKey => _kDeviceUuid;
}

class PlatformUser {
  const PlatformUser({
    required this.userId,
    required this.email,
    required this.credits,
  });

  final String userId;
  final String email;
  final int credits;
}
