import 'dart:io';

import 'platform_installer.dart';
import 'update_models.dart';

class MacosInstaller implements PlatformInstaller {
  MacosInstaller({
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

  /// `.../Volward.app/Contents/MacOS/volward` → `.../Volward.app`
  static String? appBundlePathFromExecutable(String executable) {
    final parts = executable.split(Platform.pathSeparator);
    final macosIdx = parts.lastIndexOf('MacOS');
    if (macosIdx < 2) return null;
    if (parts[macosIdx - 1] != 'Contents') return null;
    return parts.sublist(0, macosIdx - 1).join(Platform.pathSeparator);
  }

  @override
  Future<void> installAndRelaunch({
    required File downloaded,
    required ReleaseInfo release,
  }) async {
    final currentApp = appBundlePathFromExecutable(_resolvedExecutable);
    if (currentApp == null) {
      throw StateError('Not running from a .app bundle');
    }
    final extractDir = await Directory.systemTemp.createTemp(
      'volward_extract_',
    );
    final unzip = await _run('unzip', [
      '-qo',
      downloaded.path,
      '-d',
      extractDir.path,
    ]);
    if (unzip.exitCode != 0) {
      throw StateError('unzip failed: ${unzip.stderr}');
    }
    final newApp = await _findAppBundle(extractDir);
    if (newApp == null) {
      throw StateError('volward.app not found in zip');
    }
    final backup = '$currentApp.bak-${DateTime.now().millisecondsSinceEpoch}';
    await _run('mv', [currentApp, backup]);
    try {
      final move = await _run('mv', [newApp.path, currentApp]);
      if (move.exitCode != 0) {
        throw StateError('Failed to move new app into place');
      }
    } catch (_) {
      await _run('mv', [backup, currentApp]);
      rethrow;
    }
    await _run('xattr', ['-cr', currentApp]);
    final open = await _run('open', [currentApp]);
    if (open.exitCode != 0) {
      throw StateError('open failed: ${open.stderr}');
    }
    await _run('rm', ['-rf', backup]);
    _exitProcess(0);
  }

  Future<Directory?> _findAppBundle(Directory root) async {
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Directory && entity.path.endsWith('.app')) {
        return entity;
      }
    }
    return null;
  }
}
