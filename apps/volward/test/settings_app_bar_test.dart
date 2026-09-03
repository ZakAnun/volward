import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/settings_page.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/theme/volward_theme_settings.dart';
import 'package:volward/theme/volward_tokens.dart';
import 'package:volward/updater/app_updater.dart';
import 'package:volward/volward_session.dart';

Future<void> _pumpSettings(
  WidgetTester tester, {
  required Brightness brightness,
}) async {
  final themeSettings = VolwardThemeSettings();
  final updater = AppUpdater.test();
  addTearDown(themeSettings.dispose);
  addTearDown(updater.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: buildVolwardTheme(brightness: brightness),
      home: SettingsPage(
        themeSettings: themeSettings,
        session: VolwardSession.test(),
        deletableOnly: false,
        onDeletableOnlyChanged: (_) {},
        updater: updater,
      ),
    ),
  );
  await tester.pump();
}

Color? _appBarBackground(WidgetTester tester) {
  final appBarContext = tester.element(find.byType(AppBar));
  final appBar = tester.widget<AppBar>(find.byType(AppBar));
  return appBar.backgroundColor ??
      Theme.of(appBarContext).appBarTheme.backgroundColor;
}

void main() {
  testWidgets(
    'settings app bar follows the light page surface instead of fixed black',
    (tester) async {
      await _pumpSettings(tester, brightness: Brightness.light);

      final tokens = VolwardTokens.light(VolwardTokens.defaultAccent);
      expect(_appBarBackground(tester), tokens.canvasParchment);
      expect(_appBarBackground(tester), isNot(tokens.surfaceBlack));

      final title = tester.widget<Text>(find.text('Settings'));
      expect(
        title.style?.color ??
            Theme.of(
              tester.element(find.text('Settings')),
            ).appBarTheme.titleTextStyle?.color,
        tokens.ink,
      );
    },
  );

  testWidgets('settings app bar follows the dark page surface', (tester) async {
    await _pumpSettings(tester, brightness: Brightness.dark);

    final tokens = VolwardTokens.dark(VolwardTokens.defaultAccent);
    expect(_appBarBackground(tester), tokens.canvasParchment);

    final title = tester.widget<Text>(find.text('Settings'));
    expect(
      title.style?.color ??
          Theme.of(
            tester.element(find.text('Settings')),
          ).appBarTheme.titleTextStyle?.color,
      tokens.ink,
    );
  });
}
