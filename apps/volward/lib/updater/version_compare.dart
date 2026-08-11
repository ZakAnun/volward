/// Returns `MAJOR.MINOR.PATCH` or null if not a stable release tag.
String? normalizeReleaseTag(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final withoutV = trimmed.startsWith('v') || trimmed.startsWith('V')
      ? trimmed.substring(1)
      : trimmed;
  final parts = withoutV.split('.');
  if (parts.length != 3 || parts.any((part) => !_isDigits(part))) {
    return null;
  }
  return parts.join('.');
}

int compareSemver(String a, String b) {
  List<int> parts(String v) =>
      v.split('.').map(int.parse).toList(growable: false);
  final pa = parts(a);
  final pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final c = pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return 0;
}

bool isRemoteNewer({
  required String remoteTag,
  required String localVersion,
}) {
  final remote = normalizeReleaseTag(remoteTag);
  final local = normalizeReleaseTag(localVersion);
  if (remote == null || local == null) return false;
  return compareSemver(remote, local) > 0;
}

bool _isDigits(String value) {
  if (value.isEmpty) return false;
  for (var i = 0; i < value.length; i++) {
    final code = value.codeUnitAt(i);
    if (code < 0x30 || code > 0x39) return false;
  }
  return true;
}
