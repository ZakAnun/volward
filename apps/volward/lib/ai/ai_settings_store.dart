import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../snapshot_cache.dart';
import '../volward_session.dart';
import 'ai_contract.dart';
import 'ai_provider.dart';
import 'byok_ai_provider.dart';
import 'platform_ai_provider.dart';

enum AiMode { byok, platform }

class AiSettingsStore {
  AiSettingsStore._();
  static final AiSettingsStore instance = AiSettingsStore._();

  static const _kMode = 'ai_mode';
  static const _kPrivacy = 'ai_privacy_accepted';
  static const _kProvider = 'ai_byok_provider';
  static const _kByokKeyName = 'volward_byok_api_key';

  @visibleForTesting
  File? settingsFileForTest;

  /// Prefer the legacy macOS keychain: Data Protection Keychain needs
  /// `keychain-access-groups` + a Mac App Development profile, which breaks
  /// Flutter CLI builds that omit `-allowProvisioningUpdates` (-34018 otherwise).
  final _secure = const FlutterSecureStorage(
    mOptions: MacOsOptions(
      useDataProtectionKeyChain: false,
    ),
  );

  File _settingsFile() =>
      settingsFileForTest ??
      File('${SnapshotCache.cacheDir().path}/settings.json');

  Future<Map<String, dynamic>> _readMap() async {
    final file = _settingsFile();
    if (!await file.exists()) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {};
  }

  Future<void> _writeMap(Map<String, dynamic> map) async {
    final file = _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(map));
  }

  Future<AiMode> getMode() async {
    final raw = (await _readMap())[_kMode];
    return raw == 'platform' ? AiMode.platform : AiMode.byok;
  }

  Future<void> setMode(AiMode mode) async {
    final map = await _readMap();
    map[_kMode] = mode.name;
    await _writeMap(map);
  }

  Future<bool> isPrivacyAccepted() async =>
      (await _readMap())[_kPrivacy] == true;

  Future<void> setPrivacyAccepted(bool value) async {
    final map = await _readMap();
    map[_kPrivacy] = value;
    await _writeMap(map);
  }

  Future<String> getByokProvider() async =>
      (await _readMap())[_kProvider] as String? ?? 'deepseek';

  Future<void> setByokProvider(String provider) async {
    final map = await _readMap();
    map[_kProvider] = provider;
    await _writeMap(map);
  }

  Future<String?> getByokKey() => _secure.read(key: _kByokKeyName);
  Future<void> setByokKey(String key) =>
      _secure.write(key: _kByokKeyName, value: key);
  Future<void> clearByokKey() => _secure.delete(key: _kByokKeyName);

  Future<AiProvider?> resolveProvider() async {
    final mode = await getMode();
    if (mode == AiMode.platform) return PlatformAiProvider();
    final key = await getByokKey();
    if (key == null || key.isEmpty) return null;
    try {
      final session = VolwardSession.instance;
      if (session != null) {
        return ByokAiProvider(
          apiKey: key,
          contract: SessionAiContract(session),
        );
      }
      // Unit tests / pre-session: provider without contract (analyze needs inject).
      return ByokAiProvider(apiKey: key);
    } catch (_) {
      // Native lib older than Dart contract surface — UI shows update hint.
      return null;
    }
  }
}
