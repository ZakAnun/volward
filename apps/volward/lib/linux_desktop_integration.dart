import 'dart:convert';
import 'dart:io';

/// Paths used when installing Linux XDG / Desktop launchers for Volward.
class LinuxDesktopPaths {
  const LinuxDesktopPaths({
    required this.home,
    required this.execPath,
    required this.iconPng,
  });

  final Directory home;
  final String execPath;
  final File iconPng;
}

const _desktopFileName = 'com.volward.volward.desktop';
const _desktopShortcutName = 'volward.desktop';
const _iconName = 'volward.png';
const _settingsKey = 'linux_desktop_exec';

String _desktopEntryBody(String execPath) {
  return '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=Volward\n'
      'Exec="$execPath"\n'
      'Icon=volward\n'
      'StartupWMClass=com.volward.volward\n'
      'Categories=Utility;\n'
      'Terminal=false\n';
}

/// Installs app-grid + optional Desktop launchers for Linux first-run.
///
/// Returns the Exec path written, or `null` if skipped (empty home, missing
/// icon, etc.). Merges [settingsFile] so existing theme keys survive.
Future<String?> installLinuxDesktopIntegration({
  required LinuxDesktopPaths paths,
  required File settingsFile,
  bool writeDesktopShortcut = true,
}) async {
  final homePath = paths.home.path;
  if (homePath.isEmpty) return null;
  if (!await paths.iconPng.exists()) return null;

  final applicationsDir = Directory('$homePath/.local/share/applications');
  final appDesktop = File('${applicationsDir.path}/$_desktopFileName');
  final iconDest = File(
    '$homePath/.local/share/icons/hicolor/256x256/apps/$_iconName',
  );
  final desktopDir = Directory('$homePath/Desktop');
  final desktopShortcut = File('${desktopDir.path}/$_desktopShortcutName');

  final previousExec = await _readLinuxDesktopExec(settingsFile);
  final filesPresent = await appDesktop.exists() && await iconDest.exists();
  final desktopOk =
      !writeDesktopShortcut ||
      !await desktopDir.exists() ||
      await desktopShortcut.exists();

  if (previousExec == paths.execPath && filesPresent && desktopOk) {
    return previousExec;
  }

  await applicationsDir.create(recursive: true);
  await iconDest.parent.create(recursive: true);
  await paths.iconPng.copy(iconDest.path);

  final body = _desktopEntryBody(paths.execPath);
  await appDesktop.writeAsString(body);

  if (writeDesktopShortcut && await desktopDir.exists()) {
    await desktopShortcut.writeAsString(body);
    await Process.run('chmod', ['+x', desktopShortcut.path]);
  }

  await _mergeLinuxDesktopExec(settingsFile, paths.execPath);

  try {
    await Process.run('update-desktop-database', [applicationsDir.path]);
  } catch (_) {
    // Best-effort; ignore missing binary / failures.
  }

  return paths.execPath;
}

Future<String?> _readLinuxDesktopExec(File settingsFile) async {
  if (!await settingsFile.exists()) return null;
  try {
    final decoded = jsonDecode(await settingsFile.readAsString());
    if (decoded is! Map) return null;
    final value = decoded[_settingsKey];
    return value is String ? value : null;
  } catch (_) {
    return null;
  }
}

Future<void> _mergeLinuxDesktopExec(File settingsFile, String execPath) async {
  await settingsFile.parent.create(recursive: true);
  Map<String, dynamic> existing = {};
  if (await settingsFile.exists()) {
    try {
      final decoded = jsonDecode(await settingsFile.readAsString());
      if (decoded is Map) {
        existing = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      existing = {};
    }
  }
  existing[_settingsKey] = execPath;
  await settingsFile.writeAsString(jsonEncode(existing));
}
