import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/theme/volward_theme_settings.dart';

void main() {
  test('AiSettingsStore setMode preserves existing theme_preference', () async {
    final temp = await Directory.systemTemp.createTemp('volward-ai-settings');
    addTearDown(() => temp.delete(recursive: true));

    final settingsFile = File('${temp.path}/settings.json')
      ..writeAsStringSync(jsonEncode({'theme_preference': 1}));

    final store = AiSettingsStore.instance..settingsFileForTest = settingsFile;
    addTearDown(() => store.settingsFileForTest = null);

    await store.setMode(AiMode.platform);

    final saved =
        jsonDecode(settingsFile.readAsStringSync()) as Map<String, dynamic>;
    expect(saved['theme_preference'], 1);
    expect(saved['ai_mode'], 'platform');
    expect(await store.getMode(), AiMode.platform);
  });

  test('VolwardThemeSettings persist merges and preserves AI keys', () async {
    final temp = await Directory.systemTemp.createTemp('volward-ai-theme');
    addTearDown(() => temp.delete(recursive: true));

    final settingsFile = File('${temp.path}/settings.json')
      ..writeAsStringSync(
        jsonEncode({
          'theme_preference': 0,
          'ai_mode': 'byok',
          'ai_privacy_accepted': true,
          'ai_byok_provider': 'anthropic',
        }),
      );

    final theme = VolwardThemeSettings()..settingsFileForTest = settingsFile;
    await theme.load();
    await theme.setPreference(VolwardThemePreference.dark);

    final saved =
        jsonDecode(settingsFile.readAsStringSync()) as Map<String, dynamic>;
    expect(saved['theme_preference'], VolwardThemePreference.dark.index);
    expect(saved['ai_mode'], 'byok');
    expect(saved['ai_privacy_accepted'], true);
    expect(saved['ai_byok_provider'], 'anthropic');
  });
}
