import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/updater/update_models.dart';
import 'package:volward/updater/windows_installer.dart';

void main() {
  test('buildUpdateBatch runs silent install then relaunches', () {
    final batch = WindowsInstaller.buildUpdateBatch(
      installerPath: r'C:\Temp\VolwardSetup.exe',
      relaunchPath: r'C:\Users\me\AppData\Local\Programs\Volward\volward.exe',
    );

    expect(batch, contains(r'"C:\Temp\VolwardSetup.exe" /VERYSILENT'));
    expect(batch, contains('/FORCECLOSEAPPLICATIONS'));
    expect(
      batch,
      contains(
        r'start "" "C:\Users\me\AppData\Local\Programs\Volward\volward.exe"',
      ),
    );
  });

  test('installAndRelaunch detaches update script then exits', () async {
    final directory = await Directory.systemTemp.createTemp(
      'volward_windows_installer_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final installerFile = File('${directory.path}/VolwardSetup.exe');
    await installerFile.writeAsBytes(const [0]);

    String? started;
    List<String>? startedArgs;
    ProcessStartMode? capturedMode;
    var exited = false;
    final installer = WindowsInstaller(
      resolvedExecutable: r'C:\Old\volward.exe',
      localAppData: r'C:\Users\me\AppData\Local',
      start: (executable, arguments, {mode = ProcessStartMode.normal}) async {
        started = executable;
        startedArgs = arguments;
        capturedMode = mode;
      },
      exitProcess: (code) {
        expect(code, 0);
        exited = true;
      },
    );

    await installer.installAndRelaunch(
      downloaded: installerFile,
      release: const ReleaseInfo(
        tagName: 'v0.0.2',
        version: '0.0.2',
        htmlUrl: '',
        body: '',
        assets: [],
      ),
    );

    expect(started, 'cmd.exe');
    expect(startedArgs, isNotNull);
    expect(startedArgs![0], '/c');
    expect(startedArgs![1], endsWith('volward_update.cmd'));
    expect(capturedMode, ProcessStartMode.detached);
    expect(exited, isTrue);
    final batch = await File(startedArgs![1]).readAsString();
    expect(batch, contains(installerFile.path));
    expect(
      batch,
      contains(r'C:\Users\me\AppData\Local\Programs\Volward\volward.exe'),
    );
  });
}
