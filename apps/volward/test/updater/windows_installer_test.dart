import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/updater/update_models.dart';
import 'package:volward/updater/windows_installer.dart';

void main() {
  test('relaunches in detached mode after installer succeeds', () async {
    ProcessStartMode? startMode;
    String? startedPath;
    var exited = false;
    final installer = WindowsInstaller(
      resolvedExecutable: r'C:\Volward\volward.exe',
      run: (command, arguments) async => ProcessResult(1, 0, '', ''),
      start: (executable, arguments, {mode = ProcessStartMode.normal}) async {
        startedPath = executable;
        startMode = mode;
      },
      exitProcess: (code) {
        expect(code, 0);
        exited = true;
      },
    );

    await installer.installAndRelaunch(
      downloaded: File(r'C:\Temp\volward-setup.exe'),
      release: const ReleaseInfo(
        tagName: 'v1.0.0',
        version: '1.0.0',
        htmlUrl: '',
        body: '',
        assets: [],
      ),
    );

    expect(startedPath, r'C:\Volward\volward.exe');
    expect(startMode, ProcessStartMode.detached);
    expect(exited, isTrue);
  });
}
