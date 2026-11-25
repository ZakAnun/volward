import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef VolwardDeleteEntriesJsonNative =
    Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Bool);
typedef VolwardDeleteEntriesJson =
    Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, bool);

typedef VolwardEmptyTrashJsonNative = Pointer<Utf8> Function(Pointer<Void>);
typedef VolwardEmptyTrashJson = Pointer<Utf8> Function(Pointer<Void>);
