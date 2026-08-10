import 'package:flutter_test/flutter_test.dart';
import 'package:volward/updater/linux_appimage_installer.dart';

void main() {
  group('LinuxAppImageInstaller.isAppImageRuntime', () {
    test('returns true when APPIMAGE is set', () {
      expect(
        LinuxAppImageInstaller.isAppImageRuntime(
          resolvedExecutable: '/tmp/.mount_volward/volward',
          environment: const {'APPIMAGE': '/opt/Volward.AppImage'},
        ),
        isTrue,
      );
    });

    test('returns true for an AppImage executable path', () {
      expect(
        LinuxAppImageInstaller.isAppImageRuntime(
          resolvedExecutable: '/opt/Volward.AppImage',
          environment: const {},
        ),
        isTrue,
      );
    });

    test('returns false outside an AppImage runtime', () {
      expect(
        LinuxAppImageInstaller.isAppImageRuntime(
          resolvedExecutable: '/usr/local/bin/volward',
          environment: const {},
        ),
        isFalse,
      );
    });
  });
}
