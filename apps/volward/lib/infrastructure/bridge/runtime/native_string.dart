import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef NativeStringFree = void Function(Pointer<Utf8> value);

class NativeStringCodec {
  const NativeStringCodec(this._free);

  final NativeStringFree _free;

  String decodeAndFree(Pointer<Utf8> value) {
    if (value == nullptr) {
      throw StateError('Native string pointer is null');
    }
    try {
      return value.toDartString();
    } finally {
      _free(value);
    }
  }

  String? decodeAndFreeNullable(Pointer<Utf8> value) {
    if (value == nullptr) return null;
    return decodeAndFree(value);
  }
}
