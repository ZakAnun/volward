import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'runtime/native_library.dart';
import 'runtime/native_string.dart';

typedef VolwardEngineCreateNative = Pointer<Void> Function();
typedef VolwardEngineCreate = Pointer<Void> Function();

typedef VolwardEngineFreeNative = Void Function(Pointer<Void>);
typedef VolwardEngineFree = void Function(Pointer<Void>);

typedef VolwardFreeStringNative = Void Function(Pointer<Utf8>);
typedef VolwardFreeString = void Function(Pointer<Utf8>);

abstract interface class VolwardBridge {
  bool get hasSnapshotFileApi;
  bool get hasSnapshotFilePbApi;
  bool get hasScanOptionsApi;
  bool get hasCheckpointApi;
  bool get hasQuickListApi;
  bool get hasIndexApi;
}

abstract interface class EngineBridge {
  NativeStringCodec get codec;

  Pointer<Void> createEngine();

  void freeEngine(Pointer<Void> engine);

  void freeString(Pointer<Utf8> value);
}

class EngineNativeBridge implements EngineBridge {
  EngineNativeBridge(NativeLibraryHandle library)
    : _create = library
          .lookup<NativeFunction<VolwardEngineCreateNative>>(
            'volward_engine_create',
          )
          .asFunction(),
      _free = library
          .lookup<NativeFunction<VolwardEngineFreeNative>>(
            'volward_engine_free',
          )
          .asFunction(),
      _freeString = library
          .lookup<NativeFunction<VolwardFreeStringNative>>(
            'volward_free_string',
          )
          .asFunction() {
    codec = NativeStringCodec(_freeString);
  }

  final VolwardEngineCreate _create;
  final VolwardEngineFree _free;
  final VolwardFreeString _freeString;

  @override
  late final NativeStringCodec codec;

  @override
  Pointer<Void> createEngine() => _create();

  @override
  void freeEngine(Pointer<Void> engine) => _free(engine);

  @override
  void freeString(Pointer<Utf8> value) => _freeString(value);
}
