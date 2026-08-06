import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/home_page.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/scan_preview.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/theme/volward_theme_settings.dart';
import 'package:volward/volward_session.dart';
import 'package:volward/widgets/scan_column_view.dart';

/// A session whose preview is observable and whose restore hangs forever, so
/// the startup test can prove the preview is not gated on full restore.
class _BlockingSession extends VolwardSession {
  _BlockingSession({this.exposePreview = false}) : super.test() {
    setScanRoots(['/']);
  }

  final bool exposePreview;
  int previewCalls = 0;
  final Completer<void> _restoreGate = Completer<void>();

  late final ScanSnapshotState _previewSnapshot = ScanSnapshotState.fromWire(
    buildPreviewSnapshot(
      rootPath: '/',
      quickListEntries: const [
        {'path': '/Documents', 'is_dir': true},
      ],
    ),
  );

  @override
  ScanSnapshotState? get lastSnapshot =>
      exposePreview ? _previewSnapshot : null;

  @override
  bool get restoringSnapshot => exposePreview;

  @override
  Future<void> previewTarget({int? expectedGeneration}) async {
    previewCalls++;
  }

  @override
  Future<void> restoreCachedSnapshotIfNeeded() {
    // Hangs on an unresolved Completer — no Timer is scheduled, so the widget
    // test's teardown check for pending timers stays green.
    return _restoreGate.future;
  }
}

Widget _shell(VolwardSession session, VolwardThemeSettings themeSettings) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildVolwardTheme(brightness: Brightness.light),
    home: HomePage(session: session, themeSettings: themeSettings),
  );
}

void main() {
  testWidgets('HomePage starts the preview before a hanging restore completes',
      (tester) async {
    final session = _BlockingSession()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-startup-test-no-session.json',
      )
      ..defaultRootForTest = (() => '/')
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    addTearDown(themeSettings.dispose);

    await tester.pumpWidget(_shell(session, themeSettings));
    await tester.pump();

    expect(session.previewCalls, 1);
    // The folder action stays reachable during startup loading.
    expect(find.byIcon(Icons.folder_open_outlined), findsWidgets);
  });

  testWidgets(
      'HomePage keeps the folder picker visible when no launch root exists',
      (tester) async {
    final session = _BlockingSession()
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-startup-test-no-session.json',
      )
      ..defaultRootForTest = (() => '')
      ..rootExistsForTest = ((_) => false);
    final themeSettings = VolwardThemeSettings();
    addTearDown(themeSettings.dispose);

    await tester.pumpWidget(_shell(session, themeSettings));
    await tester.pump();

    // No valid root → preview is never started, picker stays available.
    expect(session.previewCalls, 0);
    expect(find.byIcon(Icons.folder_open_outlined), findsWidgets);
  });

  testWidgets('HomePage shows the preview while cache restore is in flight',
      (tester) async {
    // Point the session-state loader at a path that does not exist so a real
    // on-disk session.json (from a previous app run on this machine) cannot
    // leak into the test and change _scanRoots mid-startup.
    final session = _BlockingSession(exposePreview: true)
      ..sessionStateFileForTest = File(
        '${Directory.systemTemp.path}/volward-startup-test-no-session.json',
      )
      ..rootExistsForTest = ((_) => true);
    final themeSettings = VolwardThemeSettings();
    addTearDown(themeSettings.dispose);

    await tester.pumpWidget(_shell(session, themeSettings));
    await tester.pump();

    expect(session.previewCalls, 1);
    expect(find.byType(ScanColumnView), findsOneWidget);
  });
}
