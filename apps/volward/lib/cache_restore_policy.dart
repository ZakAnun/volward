import 'scan_tree.dart';

/// Timeout budget for loading a persisted index/snapshot from disk into the
/// native engine. Larger files receive more time because JSON parse dominates.
Duration cacheRestoreTimeoutForByteSize(int? byteSize) {
  if (byteSize == null || byteSize <= 0) {
    return const Duration(seconds: 8);
  }
  const mb = 1024 * 1024;
  if (byteSize <= mb) {
    return const Duration(seconds: 8);
  }
  if (byteSize <= 32 * mb) {
    return const Duration(seconds: 30);
  }
  if (byteSize <= 128 * mb) {
    return const Duration(seconds: 60);
  }
  if (byteSize <= 512 * mb) {
    return const Duration(seconds: 180);
  }
  if (byteSize <= 1024 * mb) {
    return const Duration(seconds: 300);
  }
  return const Duration(seconds: 600);
}

/// True when [summary] describes an index already loaded for [preferredRoot].
bool indexSummaryMatchesRoot(
  Map<String, dynamic>? summary,
  String preferredRoot,
) {
  if (summary == null || summary.containsKey('error')) {
    return false;
  }
  final rootPath = summary['root_path']?.toString() ?? '';
  if (rootPath.isEmpty) {
    return false;
  }
  return ScanTreeBuilder.normalizeRoot(rootPath) ==
      ScanTreeBuilder.normalizeRoot(preferredRoot);
}
