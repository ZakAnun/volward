import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

String _escapeAppleScript(String value) =>
    value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

String _escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Native notification bridge (macOS). Clicking a notification activates the
/// app and emits the snapshot id on [coverageNotificationOpens].
class CoverageNotificationChannel {
  CoverageNotificationChannel._();

  static const _channel = MethodChannel('com.volward/notifications');
  static final _opens = StreamController<String>.broadcast();
  static bool _listening = false;

  static Stream<String> get opens {
    _ensureListening();
    return _opens.stream;
  }

  static void _ensureListening() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'openCoverageResult') return false;
      final snapshotId = call.arguments as String?;
      if (snapshotId == null || snapshotId.isEmpty) return false;
      if (!_opens.hasListener) return false;
      _opens.add(snapshotId);
      return true;
    });
  }

  /// Snapshot id from a click that happened before anyone listened.
  static Future<String?> takePendingOpen() async {
    _ensureListening();
    try {
      return await _channel.invokeMethod<String>('takePendingOpen');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Returns `false` when the native bridge is unavailable or permission is denied.
  static Future<bool> show({
    required String title,
    required String body,
    String? snapshotId,
  }) async {
    _ensureListening();
    try {
      final shown = await _channel.invokeMethod<bool>('show', {
        'title': title,
        'body': body,
        if (snapshotId != null) 'snapshotId': snapshotId,
      });
      return shown ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('CoverageNotificationChannel: show failed ($e)');
      return false;
    }
  }
}

/// Snapshot ids of coverage notifications the user clicked.
Stream<String> get coverageNotificationOpens =>
    CoverageNotificationChannel.opens;

/// Best-effort desktop notification for coverage job events (Design §10).
Future<void> showCoverageDesktopNotification({
  required String title,
  required String body,
  String? snapshotId,
}) async {
  try {
    if (Platform.isMacOS) {
      if (await CoverageNotificationChannel.show(
        title: title,
        body: body,
        snapshotId: snapshotId,
      )) {
        return;
      }
      final safeTitle = _escapeAppleScript(title);
      final safeBody = _escapeAppleScript(body);
      await Process.run('osascript', [
        '-e',
        'display notification "$safeBody" with title "$safeTitle"',
      ]);
      return;
    }
    if (Platform.isLinux) {
      final which = await Process.run('which', ['notify-send']);
      if (which.exitCode != 0) return;
      await Process.run('notify-send', [title, body]);
      return;
    }
    if (Platform.isWindows) {
      final safeTitle = _escapeXml(title);
      final safeBody = _escapeXml(body);
      await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null; "
            "[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > \$null; "
            "\$xml = New-Object Windows.Data.Xml.Dom.XmlDocument; "
            "\$xml.LoadXml('<toast><visual><binding template=\"ToastText02\"><text id=\"1\">$safeTitle</text><text id=\"2\">$safeBody</text></binding></visual></toast>'); "
            "\$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml); "
            "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Volward').Show(\$toast);",
      ]);
    }
  } catch (_) {}
}
