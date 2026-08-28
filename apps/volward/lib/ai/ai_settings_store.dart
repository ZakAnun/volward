import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../snapshot_cache.dart';
import '../volward_session.dart';
import 'ai_contract.dart';
import 'ai_provider.dart';
import 'byok_ai_provider.dart';
import 'platform_ai_provider.dart';
import 'platform_auth_store.dart';

enum AiMode { off, byok, platform }

class ByokTokenUsageTotals {
  const ByokTokenUsageTotals({
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.analysisCount,
    required this.estimatedAnalysisCount,
    required this.partialAnalysisCount,
    required this.updatedAtMs,
  });

  static const empty = ByokTokenUsageTotals(
    inputTokens: 0,
    outputTokens: 0,
    totalTokens: 0,
    analysisCount: 0,
    estimatedAnalysisCount: 0,
    partialAnalysisCount: 0,
    updatedAtMs: 0,
  );

  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final int analysisCount;
  final int estimatedAnalysisCount;
  final int partialAnalysisCount;
  final int updatedAtMs;
}

class AiSettingsStore {
  AiSettingsStore._();
  static final AiSettingsStore instance = AiSettingsStore._();

  static const _kMode = 'ai_mode';
  static const _kPrivacyVersion = 'ai_privacy_accepted_version';
  static const _kProvider = 'ai_byok_provider';
  static const _kByokKeyName = 'volward_byok_api_key';

  /// Bumped to 2 when Platform mode shipped: paths now transit Volward servers.
  static const kCurrentPrivacyVersion = 2;

  @visibleForTesting
  File? settingsFileForTest;

  /// Prefer the legacy macOS keychain: Data Protection Keychain needs
  /// `keychain-access-groups` + a Mac App Development profile, which breaks
  /// Flutter CLI builds that omit `-allowProvisioningUpdates` (-34018 otherwise).
  final _secure = const FlutterSecureStorage(
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  File _settingsFile() =>
      settingsFileForTest ??
      File('${SnapshotCache.cacheDir().path}/settings.json');

  File _byokUsageFile() =>
      File('${_settingsFile().parent.path}/ai_byok_usage.json');

  Future<void> _byokUsageWriteTail = Future<void>.value();

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
    return switch (raw) {
      'byok' => AiMode.byok,
      'platform' => AiMode.platform,
      _ => AiMode.off,
    };
  }

  Future<void> setMode(AiMode mode) async {
    final map = await _readMap();
    map[_kMode] = mode.name;
    await _writeMap(map);
  }

  Future<bool> isPrivacyAccepted() async =>
      ((await _readMap())[_kPrivacyVersion] as int? ?? 0) >=
      kCurrentPrivacyVersion;

  Future<void> setPrivacyAccepted(bool value) async {
    final map = await _readMap();
    map[_kPrivacyVersion] = value ? kCurrentPrivacyVersion : 0;
    map.remove('ai_privacy_accepted'); // drop the legacy bool
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

  Future<ByokTokenUsageTotals> getByokTokenUsageTotals() async {
    await _byokUsageWriteTail;
    return _readByokUsageTotals();
  }

  Future<ByokTokenUsageTotals> addByokTokenUsage({
    required int inputTokens,
    required int outputTokens,
    required int totalTokens,
    required bool estimated,
    required bool partial,
  }) async {
    final operation = _byokUsageWriteTail.then(
      (_) => _addByokTokenUsage(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: totalTokens,
        estimated: estimated,
        partial: partial,
      ),
    );
    _byokUsageWriteTail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return operation;
  }

  Future<ByokTokenUsageTotals> _addByokTokenUsage({
    required int inputTokens,
    required int outputTokens,
    required int totalTokens,
    required bool estimated,
    required bool partial,
  }) async {
    final file = _byokUsageFile();
    await file.parent.create(recursive: true);
    final lockFile = File('${file.path}.lock');
    final lock = await lockFile.open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
      final current = await _readByokUsageTotals();
      final updated = ByokTokenUsageTotals(
        inputTokens: current.inputTokens + _nonNegativeInt(inputTokens),
        outputTokens: current.outputTokens + _nonNegativeInt(outputTokens),
        totalTokens: current.totalTokens + _nonNegativeInt(totalTokens),
        analysisCount: current.analysisCount + 1,
        estimatedAnalysisCount:
            current.estimatedAnalysisCount + (estimated ? 1 : 0),
        partialAnalysisCount: current.partialAnalysisCount + (partial ? 1 : 0),
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      final temporaryFile = File(
        '${file.path}.$pid.${Isolate.current.hashCode}.'
        '${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      await temporaryFile.writeAsString(
        jsonEncode({
          'input_tokens': updated.inputTokens,
          'output_tokens': updated.outputTokens,
          'total_tokens': updated.totalTokens,
          'analysis_count': updated.analysisCount,
          'estimated_analysis_count': updated.estimatedAnalysisCount,
          'partial_analysis_count': updated.partialAnalysisCount,
          'updated_at_ms': updated.updatedAtMs,
        }),
        flush: true,
      );
      try {
        await temporaryFile.rename(file.path);
      } catch (_) {
        if (await temporaryFile.exists()) await temporaryFile.delete();
        rethrow;
      }
      return updated;
    } finally {
      await lock.unlock();
      await lock.close();
    }
  }

  Future<ByokTokenUsageTotals> _readByokUsageTotals() async {
    final file = _byokUsageFile();
    if (!await file.exists()) return ByokTokenUsageTotals.empty;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return ByokTokenUsageTotals.empty;
      return ByokTokenUsageTotals(
        inputTokens: _nonNegativeInt(raw['input_tokens']),
        outputTokens: _nonNegativeInt(raw['output_tokens']),
        totalTokens: _nonNegativeInt(raw['total_tokens']),
        analysisCount: _nonNegativeInt(raw['analysis_count']),
        estimatedAnalysisCount: _nonNegativeInt(
          raw['estimated_analysis_count'],
        ),
        partialAnalysisCount: _nonNegativeInt(raw['partial_analysis_count']),
        updatedAtMs: _nonNegativeInt(raw['updated_at_ms']),
      );
    } catch (_) {
      return ByokTokenUsageTotals.empty;
    }
  }

  Future<AiProvider?> resolveProvider() async {
    final mode = await getMode();
    switch (mode) {
      case AiMode.off:
        return null;
      case AiMode.platform:
        final token = await PlatformAuthStore.instance.userToken();
        if (token == null || token.isEmpty) return null;
        return PlatformAiProvider(token: token);
      case AiMode.byok:
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
}

int _nonNegativeInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  return parsed < 0 ? 0 : parsed;
}
