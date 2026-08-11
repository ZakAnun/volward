import 'dart:io';

import 'package:crypto/crypto.dart';

String? normalizeSha256(String? raw) {
  if (raw == null) return null;
  final text = raw.trim().toLowerCase();
  var start = -1;
  var length = 0;
  for (var i = 0; i < text.length; i++) {
    if (_isHex(text.codeUnitAt(i))) {
      start = start < 0 ? i : start;
      length++;
    } else {
      if (length == 64) return text.substring(start, i);
      start = -1;
      length = 0;
    }
  }
  return length == 64 ? text.substring(start) : null;
}

String? parseSha256Checksum(String text, {required String assetName}) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  String? onlyChecksum;
  for (final line in lines) {
    final checksum = normalizeSha256(line);
    if (checksum == null) continue;
    onlyChecksum ??= checksum;
    if (line.contains(assetName)) return checksum;
  }
  return onlyChecksum;
}

bool _isHex(int codeUnit) {
  return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x61 && codeUnit <= 0x66);
}

Future<String> sha256File(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}
