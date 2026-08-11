import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/updater/linux_appimage_installer.dart';
import 'package:volward/updater/update_models.dart';

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

  test('relaunches the replaced AppImage in detached mode', () async {
    final directory = await Directory.systemTemp.createTemp(
      'volward_linux_installer_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final target = File('${directory.path}/Volward.AppImage');
    final downloaded = File('${directory.path}/downloaded.AppImage');
    await target.writeAsString('old');
    await downloaded.writeAsString('new');
    ProcessStartMode? startMode;
    String? startedPath;
    var exited = false;
    final installer = LinuxAppImageInstaller(
      resolvedExecutable: target.path,
      environment: {'APPIMAGE': target.path},
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
      downloaded: downloaded,
      release: const ReleaseInfo(
        tagName: 'v1.0.0',
        version: '1.0.0',
        htmlUrl: '',
        body: '',
        assets: [],
      ),
    );

    expect(startedPath, target.path);
    expect(startMode, ProcessStartMode.detached);
    expect(exited, isTrue);
    expect(await target.readAsString(), 'new');
  });

  test('restores previous AppImage when relaunch fails', () async {
    final directory = await Directory.systemTemp.createTemp(
      'volward_linux_installer_rollback_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final target = File('${directory.path}/Volward.AppImage');
    final downloaded = File('${directory.path}/downloaded.AppImage');
    await target.writeAsString('old');
    await downloaded.writeAsString('new');
    var exited = false;
    final installer = LinuxAppImageInstaller(
      resolvedExecutable: target.path,
      environment: {'APPIMAGE': target.path},
      run: (command, arguments) async => ProcessResult(1, 0, '', ''),
      start: (executable, arguments, {mode = ProcessStartMode.normal}) async {
        throw StateError('relaunch failed');
      },
      exitProcess: (_) => exited = true,
    );

    await expectLater(
      installer.installAndRelaunch(
        downloaded: downloaded,
        release: const ReleaseInfo(
          tagName: 'v1.0.0',
          version: '1.0.0',
          htmlUrl: '',
          body: '',
          assets: [],
        ),
      ),
      throwsA(isA<StateError>()),
    );

    expect(exited, isFalse);
    expect(await target.readAsString(), 'old');
    expect(await File('${target.path}.old').exists(), isFalse);
  });
}
