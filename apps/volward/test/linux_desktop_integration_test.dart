import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/linux_desktop_integration.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('volward-xdg-');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('installs application and desktop launchers with quoted Exec', () async {
    final icon = File('${tmp.path}/volward.png')..writeAsBytesSync([1, 2, 3]);
    final home = Directory('${tmp.path}/home')..createSync();
    Directory('${home.path}/Desktop').createSync();
    final settings = File('${home.path}/settings.json');
    final exec = '${tmp.path}/Volward-v0.0.5-linux-x86_64.AppImage';

    final written = await installLinuxDesktopIntegration(
      paths: LinuxDesktopPaths(home: home, execPath: exec, iconPng: icon),
      settingsFile: settings,
    );

    expect(written, exec);
    final app = File(
      '${home.path}/.local/share/applications/com.volward.volward.desktop',
    );
    expect(app.readAsStringSync(), contains('Exec="$exec"'));
    expect(app.readAsStringSync(), contains('Icon=volward'));
    expect(
      app.readAsStringSync(),
      contains('StartupWMClass=com.volward.volward'),
    );
    final desktop = File('${home.path}/Desktop/volward.desktop');
    expect(desktop.existsSync(), isTrue);
    expect(desktop.statSync().mode & 0x49, isNonZero); // owner/group/other execute bit
    expect(
      File(
        '${home.path}/.local/share/icons/hicolor/256x256/apps/volward.png',
      ).existsSync(),
      isTrue,
    );
    expect(settings.readAsStringSync(), contains('linux_desktop_exec'));
  });

  test('skips rewrite when exec path is unchanged', () async {
    final icon = File('${tmp.path}/volward.png')..writeAsBytesSync([1]);
    final home = Directory('${tmp.path}/home')..createSync();
    Directory('${home.path}/Desktop').createSync();
    final settings = File('${home.path}/settings.json');
    final exec = '${tmp.path}/Volward.AppImage';
    final paths = LinuxDesktopPaths(home: home, execPath: exec, iconPng: icon);
    await installLinuxDesktopIntegration(paths: paths, settingsFile: settings);
    final first = File('${home.path}/Desktop/volward.desktop').statSync().modified;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await installLinuxDesktopIntegration(paths: paths, settingsFile: settings);
    final second = File(
      '${home.path}/Desktop/volward.desktop',
    ).statSync().modified;
    expect(second, first);
  });
}
