import 'dart:io';

import 'package:flutter/services.dart';

/// macOS-only helpers for Full Disk Access settings flow.
abstract final class MacosSettings {
  static const _channel = MethodChannel('com.volward/macos_settings');

  /// Absolute path to the running `.app` bundle (Debug build path included).
  static String? appBundlePath() {
    if (!Platform.isMacOS) return null;
    final exe = File(Platform.resolvedExecutable);
    return exe.parent.parent.parent.path;
  }

  static Future<void> touchFullDiskAccessProbe() async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod<void>('touchFullDiskAccessProbe');
  }

  static Future<void> openFullDiskAccessSettings() async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod<void>('openFullDiskAccessSettings');
  }

  static Future<void> copyAppBundlePath() async {
    final path = appBundlePath();
    if (path == null) return;
    await Clipboard.setData(ClipboardData(text: path));
  }
}
