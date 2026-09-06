import 'dart:io';

String _escapeAppleScript(String value) =>
    value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

String _escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Best-effort desktop notification for coverage job events (Design §10).
Future<void> showCoverageDesktopNotification({
  required String title,
  required String body,
}) async {
  try {
    if (Platform.isMacOS) {
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
