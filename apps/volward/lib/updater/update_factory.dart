import 'dart:ffi';
import 'dart:io';

import 'app_updater.dart';
import 'downloader.dart';
import 'github_version_source.dart';
import 'linux_appimage_installer.dart';
import 'macos_installer.dart';
import 'package_info_version_reader.dart';
import 'platform_installer.dart';
import 'url_opener.dart';
import 'windows_installer.dart';

PlatformInstaller createPlatformInstaller() {
  if (Platform.isMacOS) return MacosInstaller();
  if (Platform.isWindows) return WindowsInstaller();
  if (Platform.isLinux) return LinuxAppImageInstaller();
  return const UnsupportedInstaller();
}

String currentOsName() {
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  return Platform.operatingSystem;
}

AppUpdater createDefaultAppUpdater() {
  return AppUpdater(
    localVersionReader: PackageInfoVersionReader(),
    versionSource: GitHubVersionSource(),
    downloader: HttpDownloader(),
    installer: createPlatformInstaller(),
    urlOpener: UrlLauncherOpener(),
    os: currentOsName(),
    abi: Abi.current(),
    tempDirectoryBuilder: () =>
        Directory.systemTemp.createTempSync('volward_update_'),
  );
}
