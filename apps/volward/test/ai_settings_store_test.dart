import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/theme/volward_theme_settings.dart';

void main() {
  test('getMode defaults to off when unset', () async {
    final temp = await Directory.systemTemp.createTemp('volward-ai-settings');
    addTearDown(() => temp.delete(recursive: true));

    final f = File('${temp.path}/settings.json')..writeAsStringSync('{}');
    final store = AiSettingsStore.instance..settingsFileForTest = f;
    addTearDown(() => store.settingsFileForTest = null);

    expect(await store.getMode(), AiMode.off);
  });

  test(
    'legacy bool consent does not satisfy the platform-era disclosure',
    () async {
      final temp = await Directory.systemTemp.createTemp('volward-ai-privacy');
      addTearDown(() => temp.delete(recursive: true));

      final f = File('${temp.path}/settings.json')
        ..writeAsStringSync('{"ai_privacy_accepted": true}');
      final store = AiSettingsStore.instance..settingsFileForTest = f;
      addTearDown(() => store.settingsFileForTest = null);

      expect(await store.isPrivacyAccepted(), isFalse);
    },
  );

  test('accepting stamps the current version', () async {
    final temp = await Directory.systemTemp.createTemp('volward-ai-privacy2');
    addTearDown(() => temp.delete(recursive: true));

    final f = File('${temp.path}/settings.json')..writeAsStringSync('{}');
    final store = AiSettingsStore.instance..settingsFileForTest = f;
    addTearDown(() => store.settingsFileForTest = null);

    await store.setPrivacyAccepted(true);
    expect(await store.isPrivacyAccepted(), isTrue);

    final saved = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    expect(
      saved['ai_privacy_accepted_version'],
      AiSettingsStore.kCurrentPrivacyVersion,
    );
    expect(saved.containsKey('ai_privacy_accepted'), isFalse);
  });

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

  test('BYOK token usage accumulates without consuming credits', () async {
    final temp = await Directory.systemTemp.createTemp('volward-ai-usage');
    addTearDown(() => temp.delete(recursive: true));

    final settingsFile = File('${temp.path}/settings.json')
      ..writeAsStringSync(jsonEncode({'theme_preference': 1}));
    final store = AiSettingsStore.instance..settingsFileForTest = settingsFile;
    addTearDown(() => store.settingsFileForTest = null);

    await store.addByokTokenUsage(
      inputTokens: 300,
      outputTokens: 50,
      totalTokens: 350,
      estimated: false,
      partial: false,
    );
    final totals = await store.addByokTokenUsage(
      inputTokens: 600,
      outputTokens: 100,
      totalTokens: 700,
      estimated: true,
      partial: false,
    );

    expect(totals.inputTokens, 900);
    expect(totals.outputTokens, 150);
    expect(totals.totalTokens, 1050);
    expect(totals.analysisCount, 2);
    expect(totals.estimatedAnalysisCount, 1);
    expect(totals.partialAnalysisCount, 0);
    final saved = jsonDecode(settingsFile.readAsStringSync()) as Map;
    expect(saved['theme_preference'], 1);
    expect(saved.containsKey('credits'), isFalse);
  });

  test('BYOK token usage serializes concurrent increments', () async {
    final temp = await Directory.systemTemp.createTemp('volward-ai-usage-race');
    addTearDown(() => temp.delete(recursive: true));

    final settingsFile = File('${temp.path}/settings.json')
      ..writeAsStringSync(jsonEncode({'theme_preference': 2}));
    final store = AiSettingsStore.instance..settingsFileForTest = settingsFile;
    addTearDown(() => store.settingsFileForTest = null);

    await Future.wait([
      for (var index = 0; index < 20; index++)
        store.addByokTokenUsage(
          inputTokens: 10,
          outputTokens: 2,
          totalTokens: 12,
          estimated: false,
          partial: index.isEven,
        ),
    ]);
    final totals = await store.getByokTokenUsageTotals();

    expect(totals.inputTokens, 200);
    expect(totals.outputTokens, 40);
    expect(totals.totalTokens, 240);
    expect(totals.analysisCount, 20);
    expect(totals.partialAnalysisCount, 10);
    final saved = jsonDecode(settingsFile.readAsStringSync()) as Map;
    expect(saved['theme_preference'], 2);
    expect(saved.containsKey('ai_byok_token_usage'), isFalse);
    expect(File('${temp.path}/ai_byok_usage.json.lock').existsSync(), isTrue);
    expect(
      temp.listSync().where((entry) => entry.path.endsWith('.tmp')),
      isEmpty,
    );
  });

  test('VolwardThemeSettings persist merges and preserves AI keys', () async {
    final temp = await Directory.systemTemp.createTemp('volward-ai-theme');
    addTearDown(() => temp.delete(recursive: true));

    final settingsFile = File('${temp.path}/settings.json')
      ..writeAsStringSync(
        jsonEncode({
          'theme_preference': 0,
          'ai_mode': 'byok',
          'ai_privacy_accepted_version': 2,
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
    expect(saved['ai_privacy_accepted_version'], 2);
    expect(saved['ai_byok_provider'], 'anthropic');
  });
}
