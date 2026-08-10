import 'update_models.dart';

abstract class LocalVersionReader {
  Future<String> currentVersion();
}

abstract class VersionSource {
  Future<ReleaseInfo> fetchLatest();
}
