import 'dart:io';

import 'platform_installer.dart';
import 'update_models.dart';

typedef WindowsProcessStarter =
    Future<void> Function(
      String executable,
      List<String> arguments, {
      ProcessStartMode mode,
    });

Future<void> _startWindowsProcess(
  String executable,
  List<String> arguments, {
  ProcessStartMode mode = ProcessStartMode.normal,
}) async {
  await Process.start(executable, arguments, mode: mode);
}

class WindowsInstaller implements PlatformInstaller {
  WindowsInstaller({
    String? resolvedExecutable,
    Future<ProcessResult> Function(String, List<String>)? run,
    WindowsProcessStarter? start,
    void Function(int code)? exitProcess,
  }) : _resolvedExecutable = resolvedExecutable ?? Platform.resolvedExecutable,
       _run = run ?? Process.run,
       _start = start ?? _startWindowsProcess,
       _exitProcess = exitProcess ?? exit;

  final String _resolvedExecutable;
  final Future<ProcessResult> Function(String, List<String>) _run;
  final WindowsProcessStarter _start;
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
        await _start(exe.path, [], mode: ProcessStartMode.detached);
        _exitProcess(0);
        return;
      }
    }
    await _start(_resolvedExecutable, [], mode: ProcessStartMode.detached);
    _exitProcess(0);
  }
}
