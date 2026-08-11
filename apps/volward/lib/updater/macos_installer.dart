import 'dart:io';

import 'platform_installer.dart';
import 'update_models.dart';

class MacosInstaller implements PlatformInstaller {
  MacosInstaller({
    String? resolvedExecutable,
    Future<ProcessResult> Function(String, List<String>)? run,
    void Function(int code)? exitProcess,
  })  : _resolvedExecutable = resolvedExecutable ?? Platform.resolvedExecutable,
        _run = run ?? Process.run,
        _exitProcess = exitProcess ?? exit;

  final String _resolvedExecutable;
  final Future<ProcessResult> Function(String, List<String>) _run;
  final void Function(int code) _exitProcess;

  @override
  bool get canAutoInstall =>
      appBundlePathFromExecutable(_resolvedExecutable) != null;

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
    final backupMove = await _run('mv', [currentApp, backup]);
    if (backupMove.exitCode != 0) {
      throw StateError('Failed to back up current app: ${backupMove.stderr}');
    }

    Object? replacementError;
    try {
      final move = await _run('mv', [newApp.path, currentApp]);
      if (move.exitCode != 0) {
        replacementError = StateError(
          'Failed to move new app into place: ${move.stderr}',
        );
      }
    } catch (error) {
      replacementError = error;
    }
    if (replacementError != null) {
      await _restoreBackup(currentApp: currentApp, backup: backup);
      throw StateError('Failed to replace current app: $replacementError');
    }

    // Clear quarantine so Gatekeeper is less likely to block the replacement.
    await _run('xattr', ['-cr', currentApp]);
    Object? openError;
    try {
      // `-n` forces a new instance even if a stale process briefly remains.
      final open = await _run('open', ['-n', currentApp]);
      if (open.exitCode != 0) {
        openError = StateError('open failed: ${open.stderr}');
      }
    } catch (error) {
      openError = error;
    }
    if (openError != null) {
      await _restoreBackup(currentApp: currentApp, backup: backup);
      throw StateError('open failed: $openError');
    }
    await _run('rm', ['-rf', backup]);
    _exitProcess(0);
  }

  Future<void> _restoreBackup({
    required String currentApp,
    required String backup,
  }) async {
    final remove = await _run('rm', ['-rf', currentApp]);
    if (remove.exitCode != 0) {
      throw StateError(
        'Failed to remove replacement app during rollback: ${remove.stderr}',
      );
    }
    final restore = await _run('mv', [backup, currentApp]);
    if (restore.exitCode != 0) {
      throw StateError('Failed to restore app backup: ${restore.stderr}');
    }
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
