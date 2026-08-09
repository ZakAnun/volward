import 'package:flutter/material.dart';

import 'home_page.dart';
import 'l10n/generated/app_localizations.dart';
import 'theme/volward_theme.dart';
import 'theme/volward_theme_settings.dart';
import 'volward_session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VolwardApp());
}

class VolwardApp extends StatefulWidget {
  const VolwardApp({super.key});

  @override
  State<VolwardApp> createState() => _VolwardAppState();
}

class _VolwardAppState extends State<VolwardApp> {
  late final VolwardSession _session;
  late final VolwardThemeSettings _themeSettings;
  late final Future<void> _themeReady;

  @override
  void initState() {
    super.initState();
    _session = VolwardSession();
    _themeSettings = VolwardThemeSettings();
    _themeReady = _themeSettings.load();
  }

  @override
  void dispose() {
    _session.dispose();
    _themeSettings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _themeReady,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            theme: buildVolwardTheme(brightness: Brightness.light),
            home: const _ThemeBootstrapPlaceholder(),
          );
        }

        return ListenableBuilder(
          listenable: _themeSettings,
          builder: (context, _) {
            final accent = _themeSettings.accentColor;
            return MaterialApp(
              onGenerateTitle: (context) =>
                  AppLocalizations.of(context).appTitle,
              locale: _themeSettings.localeOverride,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildVolwardTheme(
                brightness: Brightness.light,
                accent: accent,
              ),
              darkTheme: buildVolwardTheme(
                brightness: Brightness.dark,
                accent: accent,
              ),
              themeMode: _themeSettings.themeMode,
              home: HomePage(session: _session, themeSettings: _themeSettings),
            );
          },
        );
      },
    );
  }
}

class _ThemeBootstrapPlaceholder extends StatelessWidget {
  const _ThemeBootstrapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: const SizedBox.expand(),
    );
  }
}
