import 'dart:io';

import 'platform_installer.dart';
import 'update_models.dart';

class WindowsInstaller implements PlatformInstaller {
  WindowsInstaller({
    String? resolvedExecutable,
    Future<ProcessResult> Function(String, List<String>)? run,
    void Function(int code)? exitProcess,
  }) : _resolvedExecutable = resolvedExecutable ?? Platform.resolvedExecutable,
       _run = run ?? Process.run,
       _exitProcess = exitProcess ?? exit;

  final String _resolvedExecutable;
  final Future<ProcessResult> Function(String, List<String>) _run;
  final void Function(int code) _exitProcess;

  @override
  bool get canAutoInstall => true;

  @override
  Future<void> installAndRelaunch({
    required File downloaded,
    required ReleaseInfo release,
  }) async {
    var result = await _run(downloaded.path, [
      '/VERYSILENT',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
    ]);
    if (result.exitCode != 0) {
      result = await _run(downloaded.path, []);
      if (result.exitCode != 0) {
        throw StateError('Installer failed: ${result.stderr}');
      }
      return;
    }

    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null) {
      final exe = File('$localAppData\\Programs\\Volward\\volward.exe');
      if (await exe.exists()) {
        final relaunch = await _run(exe.path, []);
        if (relaunch.exitCode != 0) {
          throw StateError('Relaunch failed: ${relaunch.stderr}');
        }
        _exitProcess(0);
        return;
      }
    }
    final relaunch = await _run(_resolvedExecutable, []);
    if (relaunch.exitCode != 0) {
      throw StateError('Relaunch failed: ${relaunch.stderr}');
    }
    _exitProcess(0);
  }
}
