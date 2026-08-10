import 'dart:io';

import 'update_models.dart';

abstract class PlatformInstaller {
  /// Returns true if this runtime can auto-install (e.g. AppImage yes, tar.gz no).
  bool get canAutoInstall;

  /// Replace/install [downloaded] and relaunch. May exit the process.
  Future<void> installAndRelaunch({
    required File downloaded,
    required ReleaseInfo release,
  });
}

class UnsupportedInstaller implements PlatformInstaller {
  const UnsupportedInstaller([this.reason = 'Unsupported update runtime']);

  final String reason;

  @override
  bool get canAutoInstall => false;

  @override
  Future<void> installAndRelaunch({
    required File downloaded,
    required ReleaseInfo release,
  }) {
    throw UnsupportedError(reason);
  }
}
