import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'analytics/analytics.dart';
import 'analytics/analytics_events.dart';
import 'home_page.dart';
import 'l10n/generated/app_localizations.dart';
import 'theme/volward_theme.dart';
import 'theme/volward_theme_settings.dart';
import 'updater/app_updater.dart';
import 'updater/update_factory.dart';
import 'volward_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Analytics.bootstrap();
  // platform is attached by AptabaseAnalytics; explicit here keeps Noop path clear too.
  unawaited(
    Analytics.instance.track(AnalyticsEvents.appOpen, {
      'platform': analyticsPlatformLabel(),
    }),
  );
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
  late final AppUpdater _updater;
  late final Future<void> _themeReady;

  @override
  void initState() {
    super.initState();
    _session = VolwardSession();
    _themeSettings = VolwardThemeSettings();
    _updater = createDefaultAppUpdater();
    _themeReady = _themeSettings.load();
  }

  @override
  void dispose() {
    _session.dispose();
    _themeSettings.dispose();
    _updater.dispose();
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
            scrollBehavior: const _VolwardScrollBehavior(),
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
              scrollBehavior: const _VolwardScrollBehavior(),
              home: HomePage(
                session: _session,
                themeSettings: _themeSettings,
                updater: _updater,
              ),
            );
          },
        );
      },
    );
  }
}

class _VolwardScrollBehavior extends MaterialScrollBehavior {
  const _VolwardScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
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
