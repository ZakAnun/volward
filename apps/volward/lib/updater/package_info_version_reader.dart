import 'package:package_info_plus/package_info_plus.dart';

import 'version_source.dart';

class PackageInfoVersionReader implements LocalVersionReader {
  @override
  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }
}
