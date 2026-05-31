import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef VolwardEngineCreateNative = Pointer<Void> Function();
typedef VolwardEngineCreate = Pointer<Void> Function();

typedef VolwardEngineFreeNative = Void Function(Pointer<Void>);
typedef VolwardEngineFree = void Function(Pointer<Void>);

typedef VolwardFreeStringNative = Void Function(Pointer<Utf8>);
typedef VolwardFreeString = void Function(Pointer<Utf8>);

typedef VolwardProbeCapabilitiesJsonNative = Pointer<Utf8> Function(Pointer<Void>);
typedef VolwardProbeCapabilitiesJson = Pointer<Utf8> Function(Pointer<Void>);

typedef VolwardIsDeepScanReadyNative = Bool Function(Pointer<Void>);
typedef VolwardIsDeepScanReady = bool Function(Pointer<Void>);

typedef VolwardStartScanNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardStartScan = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef VolwardCancelScanNative = Void Function(Pointer<Void>);
typedef VolwardCancelScan = void Function(Pointer<Void>);

typedef VolwardGetLastSnapshotJsonNative = Pointer<Utf8> Function(Pointer<Void>);
typedef VolwardGetLastSnapshotJson = Pointer<Utf8> Function(Pointer<Void>);

final class VolwardNativeBridge {
  VolwardNativeBridge._(this._lib) {
    _create = _lib
        .lookup<NativeFunction<VolwardEngineCreateNative>>('volward_engine_create')
        .asFunction();
    _free = _lib
        .lookup<NativeFunction<VolwardEngineFreeNative>>('volward_engine_free')
        .asFunction();
    _freeString = _lib
        .lookup<NativeFunction<VolwardFreeStringNative>>('volward_free_string')
        .asFunction();
    _probeCapabilitiesJson = _lib
        .lookup<NativeFunction<VolwardProbeCapabilitiesJsonNative>>(
          'volward_probe_capabilities_json',
        )
        .asFunction();
    _isDeepScanReady = _lib
        .lookup<NativeFunction<VolwardIsDeepScanReadyNative>>(
          'volward_is_deep_scan_ready',
        )
        .asFunction();
    _startScan = _lib
        .lookup<NativeFunction<VolwardStartScanNative>>('volward_start_scan')
        .asFunction();
    _cancelScan = _lib
        .lookup<NativeFunction<VolwardCancelScanNative>>('volward_cancel_scan')
        .asFunction();
    _getLastSnapshotJson = _lib
        .lookup<NativeFunction<VolwardGetLastSnapshotJsonNative>>(
          'volward_get_last_snapshot_json',
        )
        .asFunction();
  }

  static VolwardNativeBridge? _instance;

  static VolwardNativeBridge get instance {
    return _instance ??= open();
  }

  /// Independent bridge instance (e.g. for [Isolate.run] workers).
  static VolwardNativeBridge open() => VolwardNativeBridge._(_openLibrary());

  final DynamicLibrary _lib;
  late final VolwardEngineCreate _create;
  late final VolwardEngineFree _free;
  late final VolwardFreeString _freeString;
  late final VolwardProbeCapabilitiesJson _probeCapabilitiesJson;
  late final VolwardIsDeepScanReady _isDeepScanReady;
  late final VolwardStartScan _startScan;
  late final VolwardCancelScan _cancelScan;
  late final VolwardGetLastSnapshotJson _getLastSnapshotJson;

  Pointer<Void> createEngine() => _create();

  void freeEngine(Pointer<Void> engine) => _free(engine);

  Map<String, dynamic> probeCapabilities(Pointer<Void> engine) {
    final ptr = _probeCapabilitiesJson(engine);
    return _decodeJsonPtr(ptr);
  }

  bool isDeepScanReady(Pointer<Void> engine) => _isDeepScanReady(engine);

  String startScan(Pointer<Void> engine, String jobId, List<String> roots) {
    final jobPtr = jobId.toNativeUtf8();
    final rootsPtr = jsonEncode(roots).toNativeUtf8();
    try {
      final out = _startScan(engine, jobPtr, rootsPtr);
      return out.toDartString();
    } finally {
      calloc.free(jobPtr);
      calloc.free(rootsPtr);
    }
  }

  void cancelScan(Pointer<Void> engine) => _cancelScan(engine);

  Map<String, dynamic>? getLastSnapshot(Pointer<Void> engine) {
    final ptr = _getLastSnapshotJson(engine);
    if (ptr == nullptr) {
      return null;
    }
    return _decodeJsonPtr(ptr);
  }

  Map<String, dynamic> _decodeJsonPtr(Pointer<Utf8> ptr) {
    try {
      final raw = ptr.toDartString();
      return jsonDecode(raw) as Map<String, dynamic>;
    } finally {
      _freeString(ptr);
    }
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isMacOS) {
      final exe = Platform.resolvedExecutable;
      final libPath = '${File(exe).parent.path}/../Frameworks/libvolward_facade.dylib';
      return DynamicLibrary.open(libPath);
    }
    if (Platform.isLinux) {
      final exe = Platform.resolvedExecutable;
      final libPath = '${File(exe).parent.path}/lib/libvolward_facade.so';
      return DynamicLibrary.open(libPath);
    }
    if (Platform.isWindows) {
      final exe = Platform.resolvedExecutable;
      final libPath = '${File(exe).parent.path}/volward_facade.dll';
      return DynamicLibrary.open(libPath);
    }
    throw UnsupportedError('Volward native bridge: unsupported platform');
  }
}
