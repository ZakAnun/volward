import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/updater/macos_installer.dart';

void main() {
  group('MacosInstaller.appBundlePathFromExecutable', () {
    test('returns app bundle path for a bundled executable', () {
      final separator = Platform.pathSeparator;
      final executable = [
        '',
        'Applications',
        'Volward.app',
        'Contents',
        'MacOS',
        'volward',
      ].join(separator);

      expect(
        MacosInstaller.appBundlePathFromExecutable(executable),
        ['', 'Applications', 'Volward.app'].join(separator),
      );
    });

    test('returns null outside an app bundle', () {
      expect(
        MacosInstaller.appBundlePathFromExecutable(
          ['usr', 'local', 'bin', 'volward'].join(Platform.pathSeparator),
        ),
        isNull,
      );
    });

    test('returns null when MacOS is not under Contents', () {
      expect(
        MacosInstaller.appBundlePathFromExecutable(
          [
            'tmp',
            'Volward.app',
            'MacOS',
            'volward',
          ].join(Platform.pathSeparator),
        ),
        isNull,
      );
    });
  });
}
