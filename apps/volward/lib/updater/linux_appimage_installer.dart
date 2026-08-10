import 'dart:io';

import 'platform_installer.dart';
import 'update_models.dart';

class LinuxAppImageInstaller implements PlatformInstaller {
  LinuxAppImageInstaller({
    String? resolvedExecutable,
    Map<String, String>? environment,
    Future<ProcessResult> Function(String, List<String>)? run,
    void Function(int code)? exitProcess,
  }) : _resolvedExecutable = resolvedExecutable ?? Platform.resolvedExecutable,
       _environment = environment ?? Platform.environment,
       _run = run ?? Process.run,
       _exitProcess = exitProcess ?? exit;

  final String _resolvedExecutable;
  final Map<String, String> _environment;
  final Future<ProcessResult> Function(String, List<String>) _run;
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
    await downloaded.copy(staging.path);
    final chmod = await _run('chmod', ['+x', staging.path]);
    if (chmod.exitCode != 0) {
      throw StateError('chmod failed');
    }
    await staging.rename(target.path);
    final relaunch = await _run(target.path, []);
    if (relaunch.exitCode != 0) {
      throw StateError('Relaunch failed: ${relaunch.stderr}');
    }
    _exitProcess(0);
  }
}
