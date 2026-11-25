import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../bridge/bindings/scan.dart';
import 'runtime/native_library.dart';
import 'runtime/native_string.dart';

abstract interface class ScanBridge {
  bool get hasScanOptionsApi;
  bool get hasQuickListApi;

  String startScan(Pointer<Void> engine, String jobId, List<String> roots);

  String startScanAsync(Pointer<Void> engine, String jobId, List<String> roots);

  String startScanAsyncWithOptions(
    Pointer<Void> engine,
    String jobId,
    List<String> roots, {
    required bool incremental,
  });

  bool isScanRunning(Pointer<Void> engine);

  Map<String, dynamic>? getLastProgress(Pointer<Void> engine);

  void cancelScan(Pointer<Void> engine);

  String requestScanPause(Pointer<Void> engine, String root, String cacheDir);

  String? getLastPauseError(Pointer<Void> engine);

  List<Map<String, dynamic>> quickListDir(Pointer<Void> engine, String path);
}

class ScanNativeBridge implements ScanBridge {
  ScanNativeBridge(NativeLibraryHandle library, this._codec)
    : _startScan = library
          .lookup<NativeFunction<VolwardStartScanNative>>('volward_start_scan')
          .asFunction(),
      _startScanAsync = library
          .lookup<NativeFunction<VolwardStartScanAsyncNative>>(
            'volward_start_scan_async',
          )
          .asFunction(),
      _startScanAsyncWithOptions = _tryLookupStartScanAsyncWithOptions(library),
      _isScanRunning = library
          .lookup<NativeFunction<VolwardIsScanRunningNative>>(
            'volward_is_scan_running',
          )
          .asFunction(),
      _getLastProgressJson = library
          .lookup<NativeFunction<VolwardGetLastProgressJsonNative>>(
            'volward_get_last_progress_json',
          )
          .asFunction(),
      _cancelScan = library
          .lookup<NativeFunction<VolwardCancelScanNative>>(
            'volward_cancel_scan',
          )
          .asFunction(),
      _requestScanPause = _tryLookupRequestScanPause(library),
      _getLastPauseError = _tryLookupGetLastPauseError(library),
      _quickListDirJson = _tryLookupQuickListDirJson(library);

  final NativeStringCodec _codec;
  final VolwardStartScan _startScan;
  final VolwardStartScanAsync _startScanAsync;
  final VolwardStartScanAsyncWithOptions? _startScanAsyncWithOptions;
  final VolwardIsScanRunning _isScanRunning;
  final VolwardGetLastProgressJson _getLastProgressJson;
  final VolwardCancelScan _cancelScan;
  final VolwardRequestScanPause? _requestScanPause;
  final VolwardGetLastPauseError? _getLastPauseError;
  final VolwardQuickListDirJson? _quickListDirJson;

  @override
  bool get hasScanOptionsApi => _startScanAsyncWithOptions != null;

  @override
  bool get hasQuickListApi => _quickListDirJson != null;

  @override
  String startScan(Pointer<Void> engine, String jobId, List<String> roots) {
    final jobPtr = jobId.toNativeUtf8();
    final rootsPtr = jsonEncode(roots).toNativeUtf8();
    try {
      return _codec.decodeAndFree(_startScan(engine, jobPtr, rootsPtr));
    } finally {
      calloc.free(jobPtr);
      calloc.free(rootsPtr);
    }
  }

  @override
  String startScanAsync(
    Pointer<Void> engine,
    String jobId,
    List<String> roots,
  ) {
    return startScanAsyncWithOptions(engine, jobId, roots, incremental: false);
  }

  @override
  String startScanAsyncWithOptions(
    Pointer<Void> engine,
    String jobId,
    List<String> roots, {
    required bool incremental,
  }) {
    final jobPtr = jobId.toNativeUtf8();
    final rootsPtr = jsonEncode(roots).toNativeUtf8();
    try {
      final startWithOptions = _startScanAsyncWithOptions;
      final out = startWithOptions != null
          ? startWithOptions(engine, jobPtr, rootsPtr, incremental)
          : _startScanAsync(engine, jobPtr, rootsPtr);
      return _codec.decodeAndFree(out);
    } finally {
      calloc.free(jobPtr);
      calloc.free(rootsPtr);
    }
  }

  @override
  bool isScanRunning(Pointer<Void> engine) => _isScanRunning(engine);

  @override
  Map<String, dynamic>? getLastProgress(Pointer<Void> engine) {
    final ptr = _getLastProgressJson(engine);
    if (ptr == nullptr) return null;
    return jsonDecode(_codec.decodeAndFree(ptr)) as Map<String, dynamic>;
  }

  @override
  void cancelScan(Pointer<Void> engine) => _cancelScan(engine);

  @override
  String requestScanPause(Pointer<Void> engine, String root, String cacheDir) {
    final fn = _requestScanPause;
    if (fn == null) {
      return 'error:native dylib missing volward_request_scan_pause — rebuild Rust';
    }
    final rootPtr = root.toNativeUtf8();
    final cacheDirPtr = cacheDir.toNativeUtf8();
    try {
      final out = fn(engine, rootPtr, cacheDirPtr);
      return _codec.decodeAndFreeNullable(out) ?? 'error:null pause response';
    } finally {
      calloc.free(rootPtr);
      calloc.free(cacheDirPtr);
    }
  }

  @override
  String? getLastPauseError(Pointer<Void> engine) {
    final fn = _getLastPauseError;
    if (fn == null) return 'native dylib missing volward_get_last_pause_error';
    return _codec.decodeAndFreeNullable(fn(engine));
  }

  @override
  List<Map<String, dynamic>> quickListDir(Pointer<Void> engine, String path) {
    final lookup = _quickListDirJson;
    if (lookup == null) return const [];
    final pathPtr = path.toNativeUtf8();
    try {
      final out = lookup(engine, pathPtr);
      if (out == nullptr) return const [];
      final decoded = jsonDecode(_codec.decodeAndFree(out));
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } finally {
      calloc.free(pathPtr);
    }
  }

  static VolwardStartScanAsyncWithOptions? _tryLookupStartScanAsyncWithOptions(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardStartScanAsyncWithOptionsNative>>(
          'volward_start_scan_async_with_options',
        )
        ?.asFunction();
  }

  static VolwardRequestScanPause? _tryLookupRequestScanPause(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardRequestScanPauseNative>>(
          'volward_request_scan_pause',
        )
        ?.asFunction();
  }

  static VolwardGetLastPauseError? _tryLookupGetLastPauseError(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardGetLastPauseErrorNative>>(
          'volward_get_last_pause_error',
        )
        ?.asFunction();
  }

  static VolwardQuickListDirJson? _tryLookupQuickListDirJson(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardQuickListDirJsonNative>>(
          'volward_quick_list_dir_json',
        )
        ?.asFunction();
  }
}
