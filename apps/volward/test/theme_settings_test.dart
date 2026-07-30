import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/theme/volward_theme_settings.dart';
import 'package:volward/theme/volward_tokens.dart';

void main() {
  test('load restores theme preference and accent from disk', () async {
    final temp = await Directory.systemTemp.createTemp('volward-settings-test');
    addTearDown(() => temp.delete(recursive: true));

    final settingsFile = File('${temp.path}/settings.json')
      ..writeAsStringSync(
        jsonEncode({
          'theme_preference': VolwardThemePreference.dark.index,
          'accent_color': VolwardTokens.accentPresets[1].$2.toARGB32(),
        }),
      );

    final settings = VolwardThemeSettings()..settingsFileForTest = settingsFile;
    await settings.load();

    expect(settings.preference, VolwardThemePreference.dark);
    expect(settings.localePreference, VolwardLocalePreference.system);
    expect(
      settings.accentColor.toARGB32(),
      VolwardTokens.accentPresets[1].$2.toARGB32(),
    );
  });

  test('load restores locale preference from disk', () async {
    final temp = await Directory.systemTemp.createTemp('volward-settings-test');
    addTearDown(() => temp.delete(recursive: true));

    final settingsFile = File('${temp.path}/settings.json')
      ..writeAsStringSync(
        jsonEncode({
          'theme_preference': VolwardThemePreference.system.index,
          'locale_preference': VolwardLocalePreference.zh.index,
          'accent_color': VolwardTokens.defaultAccent.toARGB32(),
        }),
      );

    final settings = VolwardThemeSettings()..settingsFileForTest = settingsFile;
    await settings.load();

    expect(settings.localePreference, VolwardLocalePreference.zh);
    expect(settings.localeOverride?.languageCode, 'zh');
  });

  test('invalid locale preference falls back to system', () async {
    final temp = await Directory.systemTemp.createTemp('volward-settings-test');
    addTearDown(() => temp.delete(recursive: true));

    final settingsFile = File('${temp.path}/settings.json')
      ..writeAsStringSync(
        jsonEncode({
          'theme_preference': VolwardThemePreference.system.index,
          'locale_preference': 999,
          'accent_color': VolwardTokens.defaultAccent.toARGB32(),
        }),
      );

    final settings = VolwardThemeSettings()..settingsFileForTest = settingsFile;
    await settings.load();

    expect(settings.localePreference, VolwardLocalePreference.system);
    expect(settings.localeOverride, isNull);
  });

  test('setPreference persists and rolls back on write failure', () async {
    final temp = await Directory.systemTemp.createTemp('volward-settings-test');
    addTearDown(() => temp.delete(recursive: true));

    final settingsFile = File('${temp.path}/settings.json');
    final settings = VolwardThemeSettings()..settingsFileForTest = settingsFile;

    await settings.setPreference(VolwardThemePreference.light);

    final saved =
        jsonDecode(settingsFile.readAsStringSync()) as Map<String, dynamic>;
    expect(saved['theme_preference'], VolwardThemePreference.light.index);

    // Parent path is an existing file, so create/write should fail.
    final blockedParent = File('${temp.path}/blocked');
    blockedParent.writeAsStringSync('not-a-directory');
    settings.settingsFileForTest = File('${blockedParent.path}/settings.json');

    await settings.setPreference(VolwardThemePreference.dark);
    expect(settings.preference, VolwardThemePreference.light);
  });

  test('setLocalePreference persists', () async {
    final temp = await Directory.systemTemp.createTemp('volward-settings-test');
    addTearDown(() => temp.delete(recursive: true));

    final settingsFile = File('${temp.path}/settings.json');
    final settings = VolwardThemeSettings()..settingsFileForTest = settingsFile;

    await settings.setLocalePreference(VolwardLocalePreference.en);

    final saved =
        jsonDecode(settingsFile.readAsStringSync()) as Map<String, dynamic>;
    expect(saved['locale_preference'], VolwardLocalePreference.en.index);
    expect(settings.localeOverride?.languageCode, 'en');
  });
}
