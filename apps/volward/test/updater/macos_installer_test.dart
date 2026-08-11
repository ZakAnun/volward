import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/updater/macos_installer.dart';
import 'package:volward/updater/update_models.dart';

const _release = ReleaseInfo(
  tagName: 'v0.0.2',
  version: '0.0.2',
  htmlUrl: '',
  body: '',
  assets: [],
);

ProcessResult _result({int exitCode = 0, String stderr = ''}) {
  return ProcessResult(1, exitCode, '', stderr);
}

void main() {
  group('MacosInstaller.appBundlePathFromExecutable', () {
    test('returns app bundle path for a bundled executable', () {
      final separator = Platform.pathSeparator;
      final executable = [
        '',
        'Applications',
        'Volward.app',
        'Contents',
        'MacOS',
        'volward',
      ].join(separator);

      expect(
        MacosInstaller.appBundlePathFromExecutable(executable),
        ['', 'Applications', 'Volward.app'].join(separator),
      );
    });

    test('returns null outside an app bundle', () {
      expect(
        MacosInstaller.appBundlePathFromExecutable(
          ['usr', 'local', 'bin', 'volward'].join(Platform.pathSeparator),
        ),
        isNull,
      );
    });

    test('returns null when MacOS is not under Contents', () {
      expect(
        MacosInstaller.appBundlePathFromExecutable(
          [
            'tmp',
            'Volward.app',
            'MacOS',
            'volward',
          ].join(Platform.pathSeparator),
        ),
        isNull,
      );
    });
  });

  group('MacosInstaller failure rollback', () {
    late Directory temp;
    late String currentApp;
    late File downloaded;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('macos_installer_test_');
      currentApp = '${temp.path}/Volward.app';
      downloaded = File('${temp.path}/update.zip');
    });

    tearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    test('stops when moving the current app to backup fails', () async {
      var exitCalled = false;
      var attemptedReplacement = false;

      Future<ProcessResult> run(String command, List<String> args) async {
        if (command == 'unzip') {
          await Directory('${args.last}/Volward.app').create();
        }
        if (command == 'mv' && args.first == currentApp) {
          return _result(exitCode: 1, stderr: 'backup denied');
        }
        if (command == 'mv' && args.last == currentApp) {
          attemptedReplacement = true;
        }
        return _result();
      }

      final installer = MacosInstaller(
        resolvedExecutable: '$currentApp/Contents/MacOS/volward',
        run: run,
        exitProcess: (_) => exitCalled = true,
      );

      await expectLater(
        installer.installAndRelaunch(downloaded: downloaded, release: _release),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Failed to back up current app'),
          ),
        ),
      );
      expect(attemptedReplacement, isFalse);
      expect(exitCalled, isFalse);
    });

    test('restores backup when moving the replacement fails', () async {
      var exitCalled = false;
      var mvCount = 0;
      final calls = <(String, List<String>)>[];

      Future<ProcessResult> run(String command, List<String> args) async {
        calls.add((command, List.of(args)));
        if (command == 'unzip') {
          await Directory('${args.last}/Volward.app').create();
        }
        if (command == 'mv') {
          mvCount++;
          if (mvCount == 2) {
            return _result(exitCode: 1, stderr: 'replace denied');
          }
        }
        return _result();
      }

      final installer = MacosInstaller(
        resolvedExecutable: '$currentApp/Contents/MacOS/volward',
        run: run,
        exitProcess: (_) => exitCalled = true,
      );

      await expectLater(
        installer.installAndRelaunch(downloaded: downloaded, release: _release),
        throwsA(isA<StateError>()),
      );
      expect(
        calls.any(
          (call) =>
              call.$1 == 'rm' &&
              call.$2.length == 2 &&
              call.$2.last == currentApp,
        ),
        isTrue,
      );
      expect(
        calls.any(
          (call) =>
              call.$1 == 'mv' &&
              call.$2.first.startsWith('$currentApp.bak-') &&
              call.$2.last == currentApp,
        ),
        isTrue,
      );
      expect(exitCalled, isFalse);
    });

    test('restores backup and does not exit when open fails', () async {
      var exitCalled = false;
      final calls = <(String, List<String>)>[];

      Future<ProcessResult> run(String command, List<String> args) async {
        calls.add((command, List.of(args)));
        if (command == 'unzip') {
          await Directory('${args.last}/Volward.app').create();
        }
        if (command == 'open') {
          return _result(exitCode: 1, stderr: 'launch denied');
        }
        return _result();
      }

      final installer = MacosInstaller(
        resolvedExecutable: '$currentApp/Contents/MacOS/volward',
        run: run,
        exitProcess: (_) => exitCalled = true,
      );

      await expectLater(
        installer.installAndRelaunch(downloaded: downloaded, release: _release),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('open failed'),
          ),
        ),
      );

      final openIndex = calls.indexWhere((call) => call.$1 == 'open');
      expect(openIndex, greaterThanOrEqualTo(0));
      expect(calls[openIndex].$2, ['-n', currentApp]);
      expect(calls[openIndex + 1].$1, 'rm');
      expect(calls[openIndex + 1].$2, ['-rf', currentApp]);
      expect(calls[openIndex + 2].$1, 'mv');
      expect(calls[openIndex + 2].$2.first, startsWith('$currentApp.bak-'));
      expect(calls[openIndex + 2].$2.last, currentApp);
      expect(exitCalled, isFalse);
    });
  });
}
