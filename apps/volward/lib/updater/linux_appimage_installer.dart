import 'dart:io';

import 'platform_installer.dart';
import 'update_models.dart';

typedef LinuxProcessStarter =
    Future<void> Function(
      String executable,
      List<String> arguments, {
      ProcessStartMode mode,
    });

Future<void> _startLinuxProcess(
  String executable,
  List<String> arguments, {
  ProcessStartMode mode = ProcessStartMode.normal,
}) async {
  await Process.start(executable, arguments, mode: mode);
}

class LinuxAppImageInstaller implements PlatformInstaller {
  LinuxAppImageInstaller({
    String? resolvedExecutable,
    Map<String, String>? environment,
    Future<ProcessResult> Function(String, List<String>)? run,
    LinuxProcessStarter? start,
    void Function(int code)? exitProcess,
  }) : _resolvedExecutable = resolvedExecutable ?? Platform.resolvedExecutable,
       _environment = environment ?? Platform.environment,
       _run = run ?? Process.run,
       _start = start ?? _startLinuxProcess,
       _exitProcess = exitProcess ?? exit;

  final String _resolvedExecutable;
  final Map<String, String> _environment;
  final Future<ProcessResult> Function(String, List<String>) _run;
  final LinuxProcessStarter _start;
  final void Function(int code) _exitProcess;

  static bool isAppImageRuntime({
    required String resolvedExecutable,
    required Map<String, String> environment,
  }) {
    if ((environment['APPIMAGE'] ?? '').isNotEmpty) return true;
    return resolvedExecutable.endsWith('.AppImage');
  }

  @override
  bool get canAutoInstall => isAppImageRuntime(
        resolvedExecutable: _resolvedExecutable,
        environment: _environment,
      );

  @override
  Future<void> installAndRelaunch({
    required File downloaded,
    required ReleaseInfo release,
  }) async {
    if (!canAutoInstall) {
      throw UnsupportedError('Not running as AppImage');
    }
    final targetPath = _environment['APPIMAGE'] ?? _resolvedExecutable;
    final target = File(targetPath);
    final staging = File('$targetPath.new');
    final previous = File('$targetPath.old');

    if (await staging.exists()) {
      await staging.delete();
    }
    await downloaded.copy(staging.path);
    final chmod = await _run('chmod', ['+x', staging.path]);
    if (chmod.exitCode != 0) {
      throw StateError('chmod failed: ${chmod.stderr}');
    }

    // Replace the directory entry while this process still holds the old inode.
    if (await previous.exists()) {
      await previous.delete();
    }
    if (await target.exists()) {
      await target.rename(previous.path);
    }
    await staging.rename(target.path);
    try {
      if (await previous.exists()) {
        await previous.delete();
      }
    } catch (_) {
      // Best-effort cleanup; leaving *.old is recoverable.
    }

    await _start(target.path, [], mode: ProcessStartMode.detached);
    _exitProcess(0);
  }
}
