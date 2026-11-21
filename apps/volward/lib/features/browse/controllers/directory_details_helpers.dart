import 'package:volward/scan_tree.dart';

/// Shared byte formatting used by the directory page sections and dialogs.
String formatDirectoryBytes(num? bytes) {
  if (bytes == null) return '—';
  final b = bytes.toInt();
  if (b < 1024) return '$b B';
  if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
  return '${(b / 1073741824).toStringAsFixed(2)} GB';
}

String refreshPathFromFocus({required String rootPath, ScanTreeNode? focused}) {
  if (focused != null && focused.isDirectory) return focused.path;
  return rootPath;
}

String? deleteTargetFromFocus(ScanTreeNode? focused) {
  if (focused == null || focused.category == 'System') return null;
  if (!focused.isDirectory) {
    final entryId = focused.entryId;
    if (entryId != null && entryId.isNotEmpty) return entryId;
  }
  return focused.path;
}

String _parentPathOf(String path) => parentFsPath(path);

String refreshPathForDeleteTargets({
  required String fallbackPath,
  required Iterable<String> targetPaths,
}) {
  final parentPaths = targetPaths
      .where((path) => path.isNotEmpty)
      .map(_parentPathOf)
      .toSet();
  if (parentPaths.length == 1) return parentPaths.single;
  return ScanTreeBuilder.normalizeRoot(fallbackPath);
}
