import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../snapshot_cache.dart';
import 'volward_tokens.dart';

enum VolwardThemePreference { system, light, dark }

/// User appearance preferences with disk persistence (hot-reload-safe ordinals).
class VolwardThemeSettings extends ChangeNotifier {
  int _preferenceIndex = VolwardThemePreference.system.index;
  int _accentValue = VolwardTokens.defaultAccent.toARGB32();

  /// Overrides disk path in tests.
  @visibleForTesting
  File? settingsFileForTest;

  VolwardThemePreference get preference =>
      VolwardThemePreference.values[_preferenceIndex.clamp(
        0,
        VolwardThemePreference.values.length - 1,
      )];

  Color get accentColor => Color(_accentValue);

  ThemeMode get themeMode => switch (preference) {
    VolwardThemePreference.system => ThemeMode.system,
    VolwardThemePreference.light => ThemeMode.light,
    VolwardThemePreference.dark => ThemeMode.dark,
  };

  Future<void> load() async {
    final file = settingsFileForTest ?? _settingsFile();
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      _preferenceIndex =
          (map['theme_preference'] as num?)?.toInt() ?? _preferenceIndex;
      _accentValue = (map['accent_color'] as num?)?.toInt() ?? _accentValue;
      _preferenceIndex = _preferenceIndex.clamp(
        0,
        VolwardThemePreference.values.length - 1,
      );
      notifyListeners();
    } catch (e, st) {
      debugPrint('VolwardThemeSettings: load failed: $e\n$st');
    }
  }

  Future<void> setPreference(VolwardThemePreference value) async {
    if (preference == value) return;
    final previousIndex = _preferenceIndex;
    _preferenceIndex = value.index;
    notifyListeners();
    try {
      await _persist();
    } catch (e, st) {
      _preferenceIndex = previousIndex;
      notifyListeners();
      debugPrint('VolwardThemeSettings: setPreference persist failed: $e\n$st');
    }
  }

  Future<void> setAccentColor(Color color) async {
    final next = color.toARGB32();
    if (_accentValue == next) return;
    final previousValue = _accentValue;
    _accentValue = next;
    notifyListeners();
    try {
      await _persist();
    } catch (e, st) {
      _accentValue = previousValue;
      notifyListeners();
      debugPrint(
        'VolwardThemeSettings: setAccentColor persist failed: $e\n$st',
      );
    }
  }

  Future<void> _persist() async {
    try {
      final file = settingsFileForTest ?? _settingsFile();
      await file.parent.create(recursive: true);
      final payload = jsonEncode({
        'theme_preference': _preferenceIndex,
        'accent_color': _accentValue,
      });
      await file.writeAsString(payload);
    } catch (e, st) {
      debugPrint('VolwardThemeSettings: persist failed: $e\n$st');
      rethrow;
    }
  }

  static File _settingsFile() =>
      File('${SnapshotCache.cacheDir().path}/settings.json');
}
