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
    WindowsProcessStarter? start,
    void Function(int code)? exitProcess,
    String? localAppData,
  }) : _resolvedExecutable = resolvedExecutable ?? Platform.resolvedExecutable,
       _start = start ?? _startWindowsProcess,
       _exitProcess = exitProcess ?? exit,
       _localAppData = localAppData ?? Platform.environment['LOCALAPPDATA'];

  final String _resolvedExecutable;
  final WindowsProcessStarter _start;
  final void Function(int code) _exitProcess;
  final String? _localAppData;

  @override
  bool get canAutoInstall => true;

  /// Batch that installs after this process exits, then relaunches Volward.
  ///
  /// Running Inno with `/CLOSEAPPLICATIONS` via `Process.run` is unsafe: the
  /// installer can terminate this Dart process before relaunch code runs.
  static String buildUpdateBatch({
    required String installerPath,
    required String relaunchPath,
  }) {
    return '''
@echo off
setlocal
REM Wait briefly so the old Volward process can exit.
ping -n 3 127.0.0.1 >nul
"$installerPath" /VERYSILENT /NORESTART /FORCECLOSEAPPLICATIONS
if errorlevel 1 (
  "$installerPath"
  if errorlevel 1 exit /b %ERRORLEVEL%
)
if exist "$relaunchPath" (
  start "" "$relaunchPath"
) else (
  start "" "$installerPath"
)
endlocal
''';
  }

  String get _defaultRelaunchPath {
    final localAppData = _localAppData;
    if (localAppData != null && localAppData.isNotEmpty) {
      return '$localAppData\\Programs\\Volward\\volward.exe';
    }
    return _resolvedExecutable;
  }

  @override
  Future<void> installAndRelaunch({
    required File downloaded,
    required ReleaseInfo release,
  }) async {
    final batchFile = File(
      '${downloaded.parent.path}${Platform.pathSeparator}volward_update.cmd',
    );
    await batchFile.writeAsString(
      buildUpdateBatch(
        installerPath: downloaded.path,
        relaunchPath: _defaultRelaunchPath,
      ),
    );

    // Detach the update script via cmd.exe — Process.start on a .cmd path is
    // unreliable across Windows shells/associations.
    await _start('cmd.exe', [
      '/c',
      batchFile.path,
    ], mode: ProcessStartMode.detached);
    _exitProcess(0);
  }
}
