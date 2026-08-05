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

typedef VolwardProbeCapabilitiesJsonNative = Pointer<Utf8> Function(
    Pointer<Void>);
typedef VolwardProbeCapabilitiesJson = Pointer<Utf8> Function(Pointer<Void>);

typedef VolwardIsDeepScanReadyNative = Bool Function(Pointer<Void>);
typedef VolwardIsDeepScanReady = bool Function(Pointer<Void>);

typedef VolwardStartScanNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef VolwardStartScan = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);

typedef VolwardStartScanAsyncNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef VolwardStartScanAsync = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);

typedef VolwardStartScanAsyncWithOptionsNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Bool);
typedef VolwardStartScanAsyncWithOptions = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, bool);

typedef VolwardIsScanRunningNative = Bool Function(Pointer<Void>);
typedef VolwardIsScanRunning = bool Function(Pointer<Void>);

typedef VolwardGetLastProgressJsonNative = Pointer<Utf8> Function(
    Pointer<Void>);
typedef VolwardGetLastProgressJson = Pointer<Utf8> Function(Pointer<Void>);

typedef VolwardCancelScanNative = Void Function(Pointer<Void>);
typedef VolwardCancelScan = void Function(Pointer<Void>);

typedef VolwardGetLastSnapshotJsonNative = Pointer<Utf8> Function(
    Pointer<Void>);
typedef VolwardGetLastSnapshotJson = Pointer<Utf8> Function(Pointer<Void>);

typedef VolwardSetLastSnapshotJsonNative = Bool Function(
    Pointer<Void>, Pointer<Utf8>);
typedef VolwardSetLastSnapshotJson = bool Function(
    Pointer<Void>, Pointer<Utf8>);

typedef VolwardWriteLastSnapshotToPathNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);
typedef VolwardWriteLastSnapshotToPath = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);

typedef VolwardLoadLastSnapshotFromPathNative = Bool Function(
    Pointer<Void>, Pointer<Utf8>);
typedef VolwardLoadLastSnapshotFromPath = bool Function(
    Pointer<Void>, Pointer<Utf8>);

typedef VolwardWriteLastCheckpointToPathNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);
typedef VolwardWriteLastCheckpointToPath = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);

typedef VolwardWriteLastSnapshotToPathPbNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);
typedef VolwardWriteLastSnapshotToPathPb = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);

typedef VolwardWriteLastCheckpointToPathPbNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);
typedef VolwardWriteLastCheckpointToPathPb = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);

typedef VolwardQuickListDirJsonNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);
typedef VolwardQuickListDirJson = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);

typedef VolwardOpenPermissionSettingsNative = Bool Function(Pointer<Void>);
typedef VolwardOpenPermissionSettings = bool Function(Pointer<Void>);

typedef VolwardDeleteEntriesJsonNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Bool);
typedef VolwardDeleteEntriesJson = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, bool);

typedef VolwardEmptyTrashJsonNative = Pointer<Utf8> Function(Pointer<Void>);
typedef VolwardEmptyTrashJson = Pointer<Utf8> Function(Pointer<Void>);

// ---------------------------------------------------------------------------
// Catalog index API typedefs (Design §5.3)
// ---------------------------------------------------------------------------

typedef VolwardQueryDirectoryJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Bool,
  Pointer<Utf8>,
);
typedef VolwardQueryDirectoryJson = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  bool,
  Pointer<Utf8>,
);

typedef VolwardRefreshDirectoryNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);
typedef VolwardRefreshDirectory = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);

typedef VolwardLoadIndexFromPathNative = Bool Function(
    Pointer<Void>, Pointer<Utf8>);
typedef VolwardLoadIndexFromPath = bool Function(Pointer<Void>, Pointer<Utf8>);

typedef VolwardStartLoadIndexFromPathAsyncNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);
typedef VolwardStartLoadIndexFromPathAsync = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);

typedef VolwardIsIndexLoadingNative = Bool Function(Pointer<Void>);
typedef VolwardIsIndexLoading = bool Function(Pointer<Void>);

typedef VolwardInvalidateIndexLoadNative = Void Function(Pointer<Void>);
typedef VolwardInvalidateIndexLoad = void Function(Pointer<Void>);

typedef VolwardGetLastIndexLoadErrorNative = Pointer<Utf8> Function(
    Pointer<Void>);
typedef VolwardGetLastIndexLoadError = Pointer<Utf8> Function(Pointer<Void>);

typedef VolwardWriteLastIndexToPathNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);
typedef VolwardWriteLastIndexToPath = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);

typedef VolwardGetIndexSummaryJsonNative = Pointer<Utf8> Function(
    Pointer<Void>);
typedef VolwardGetIndexSummaryJson = Pointer<Utf8> Function(Pointer<Void>);

typedef VolwardIndexVersionNative = Uint64 Function(Pointer<Void>);
typedef VolwardIndexVersion = int Function(Pointer<Void>);

abstract interface class VolwardBridge {
  bool get hasSnapshotFileApi;
  bool get hasSnapshotFilePbApi;
  bool get hasScanOptionsApi;
  bool get hasCheckpointApi;
  bool get hasQuickListApi;
  bool get hasIndexApi;
}

final class VolwardNativeBridge implements VolwardBridge {
  VolwardNativeBridge._(this._lib) {
    _create = _lib
        .lookup<NativeFunction<VolwardEngineCreateNative>>(
          'volward_engine_create',
        )
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
    _startScanAsync = _lib
        .lookup<NativeFunction<VolwardStartScanAsyncNative>>(
          'volward_start_scan_async',
        )
        .asFunction();
    _startScanAsyncWithOptions = _tryLookupStartScanAsyncWithOptions();
    _isScanRunning = _lib
        .lookup<NativeFunction<VolwardIsScanRunningNative>>(
          'volward_is_scan_running',
        )
        .asFunction();
    _cancelScan = _lib
        .lookup<NativeFunction<VolwardCancelScanNative>>('volward_cancel_scan')
        .asFunction();
    _getLastSnapshotJson = _lib
        .lookup<NativeFunction<VolwardGetLastSnapshotJsonNative>>(
          'volward_get_last_snapshot_json',
        )
        .asFunction();
    _getLastProgressJson = _lib
        .lookup<NativeFunction<VolwardGetLastProgressJsonNative>>(
          'volward_get_last_progress_json',
        )
        .asFunction();
    _setLastSnapshotJson = _lib
        .lookup<NativeFunction<VolwardSetLastSnapshotJsonNative>>(
          'volward_set_last_snapshot_json',
        )
        .asFunction();
    _writeLastSnapshotToPath = _tryLookupWriteSnapshot();
    _loadLastSnapshotFromPath = _tryLookupLoadSnapshot();
    _writeLastCheckpointToPath = _tryLookupWriteCheckpoint();
    _writeLastSnapshotToPathPb = _tryLookupWriteSnapshotPb();
    _writeLastCheckpointToPathPb = _tryLookupWriteCheckpointPb();
    _quickListDirJson = _tryLookupQuickListDirJson();
    _openPermissionSettings = _lib
        .lookup<NativeFunction<VolwardOpenPermissionSettingsNative>>(
          'volward_open_permission_settings',
        )
        .asFunction();
    _deleteEntriesJson = _lib
        .lookup<NativeFunction<VolwardDeleteEntriesJsonNative>>(
          'volward_delete_entries_json',
        )
        .asFunction();
    _emptyTrashJson = _tryLookupEmptyTrashJson();
    _queryDirectoryJson = _tryLookupQueryDirectoryJson();
    _refreshDirectory = _tryLookupRefreshDirectory();
    _loadIndexFromPath = _tryLookupLoadIndexFromPath();
    _startLoadIndexFromPathAsync = _tryLookupStartLoadIndexFromPathAsync();
    _isIndexLoading = _tryLookupIsIndexLoading();
    _invalidateIndexLoad = _tryLookupInvalidateIndexLoad();
    _getLastIndexLoadError = _tryLookupGetLastIndexLoadError();
    _writeLastIndexToPath = _tryLookupWriteLastIndexToPath();
    _getIndexSummaryJson = _tryLookupGetIndexSummaryJson();
    _indexVersion = _tryLookupIndexVersion();
  }

  VolwardStartScanAsyncWithOptions? _tryLookupStartScanAsyncWithOptions() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardStartScanAsyncWithOptionsNative>>(
            'volward_start_scan_async_with_options',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  VolwardWriteLastSnapshotToPath? _tryLookupWriteSnapshot() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardWriteLastSnapshotToPathNative>>(
            'volward_write_last_snapshot_to_path',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  VolwardLoadLastSnapshotFromPath? _tryLookupLoadSnapshot() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardLoadLastSnapshotFromPathNative>>(
            'volward_load_last_snapshot_from_path',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  VolwardWriteLastCheckpointToPath? _tryLookupWriteCheckpoint() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardWriteLastCheckpointToPathNative>>(
            'volward_write_last_checkpoint_to_path',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  VolwardQuickListDirJson? _tryLookupQuickListDirJson() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardQuickListDirJsonNative>>(
            'volward_quick_list_dir_json',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  VolwardWriteLastSnapshotToPathPb? _tryLookupWriteSnapshotPb() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardWriteLastSnapshotToPathPbNative>>(
            'volward_write_last_snapshot_to_path_pb',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  VolwardWriteLastCheckpointToPathPb? _tryLookupWriteCheckpointPb() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardWriteLastCheckpointToPathPbNative>>(
            'volward_write_last_checkpoint_to_path_pb',
          )
          .asFunction();
    } on Object {
      return null;
    }
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
  late final VolwardStartScanAsync _startScanAsync;
  late final VolwardStartScanAsyncWithOptions? _startScanAsyncWithOptions;
  late final VolwardIsScanRunning _isScanRunning;
  late final VolwardCancelScan _cancelScan;
  late final VolwardGetLastSnapshotJson _getLastSnapshotJson;
  late final VolwardGetLastProgressJson _getLastProgressJson;
  late final VolwardSetLastSnapshotJson _setLastSnapshotJson;
  late final VolwardWriteLastSnapshotToPath? _writeLastSnapshotToPath;
  late final VolwardLoadLastSnapshotFromPath? _loadLastSnapshotFromPath;
  late final VolwardWriteLastCheckpointToPath? _writeLastCheckpointToPath;
  late final VolwardWriteLastSnapshotToPathPb? _writeLastSnapshotToPathPb;
  late final VolwardWriteLastCheckpointToPathPb? _writeLastCheckpointToPathPb;
  late final VolwardQuickListDirJson? _quickListDirJson;
  late final VolwardOpenPermissionSettings _openPermissionSettings;
  late final VolwardDeleteEntriesJson _deleteEntriesJson;
  late final VolwardEmptyTrashJson? _emptyTrashJson;

  // Catalog index API fields
  late final VolwardQueryDirectoryJson? _queryDirectoryJson;
  late final VolwardRefreshDirectory? _refreshDirectory;
  late final VolwardLoadIndexFromPath? _loadIndexFromPath;
  late final VolwardStartLoadIndexFromPathAsync? _startLoadIndexFromPathAsync;
  late final VolwardIsIndexLoading? _isIndexLoading;
  late final VolwardInvalidateIndexLoad? _invalidateIndexLoad;
  late final VolwardGetLastIndexLoadError? _getLastIndexLoadError;
  late final VolwardWriteLastIndexToPath? _writeLastIndexToPath;
  late final VolwardGetIndexSummaryJson? _getIndexSummaryJson;
  late final VolwardIndexVersion? _indexVersion;

  /// True when the bundled dylib includes file-based snapshot FFI (post-2026-07-23).
  @override
  bool get hasSnapshotFileApi =>
      _writeLastSnapshotToPath != null && _loadLastSnapshotFromPath != null;

  /// True when the bundled dylib supports protobuf file-based snapshot I/O.
  /// Requires `volward_write_last_snapshot_to_path_pb` and
  /// `volward_write_last_checkpoint_to_path_pb` (both added 2026-07-27).
  @override
  bool get hasSnapshotFilePbApi =>
      _writeLastSnapshotToPathPb != null &&
      _writeLastCheckpointToPathPb != null;

  /// True when the bundled dylib accepts incremental scan options.
  @override
  bool get hasScanOptionsApi => _startScanAsyncWithOptions != null;

  /// True when the bundled dylib supports periodic scan checkpoints.
  @override
  bool get hasCheckpointApi => _writeLastCheckpointToPath != null;

  /// True when the bundled dylib supports instant, non-recursive directory
  /// listing (used for the pre-scan preview and click-priority peeks).
  @override
  bool get hasQuickListApi => _quickListDirJson != null;

  /// True when the bundled dylib supports catalog index query/refresh APIs
  /// (Design §5.3 — added 2026-07-31).
  @override
  bool get hasIndexApi =>
      _queryDirectoryJson != null &&
      _refreshDirectory != null &&
      _loadIndexFromPath != null &&
      _writeLastIndexToPath != null &&
      _getIndexSummaryJson != null;

  bool get hasAsyncIndexLoadApi =>
      _startLoadIndexFromPathAsync != null &&
      _isIndexLoading != null &&
      _invalidateIndexLoad != null &&
      _getLastIndexLoadError != null;

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

  String startScanAsync(
    Pointer<Void> engine,
    String jobId,
    List<String> roots,
  ) {
    return startScanAsyncWithOptions(engine, jobId, roots, incremental: false);
  }

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
      return out.toDartString();
    } finally {
      calloc.free(jobPtr);
      calloc.free(rootsPtr);
    }
  }

  bool isScanRunning(Pointer<Void> engine) => _isScanRunning(engine);

  Map<String, dynamic>? getLastProgress(Pointer<Void> engine) {
    final ptr = _getLastProgressJson(engine);
    if (ptr == nullptr) {
      return null;
    }
    return _decodeJsonPtr(ptr);
  }

  void cancelScan(Pointer<Void> engine) => _cancelScan(engine);

  Map<String, dynamic>? getLastSnapshot(Pointer<Void> engine) {
    final ptr = _getLastSnapshotJson(engine);
    if (ptr == nullptr) {
      return null;
    }
    return _decodeJsonPtr(ptr);
  }

  bool setLastSnapshot(Pointer<Void> engine, Map<String, dynamic> snapshot) {
    final jsonPtr = jsonEncode(snapshot).toNativeUtf8();
    try {
      return _setLastSnapshotJson(engine, jsonPtr);
    } finally {
      calloc.free(jsonPtr);
    }
  }

  /// Rust serializes snapshot directly to [path]; returns snapshot_id or `error:…`.
  String writeLastSnapshotToPath(Pointer<Void> engine, String path) {
    final write = _writeLastSnapshotToPath;
    if (write == null) {
      return 'error:native dylib missing volward_write_last_snapshot_to_path — rebuild Rust';
    }
    final pathPtr = path.toNativeUtf8();
    try {
      final out = write(engine, pathPtr);
      return out.toDartString();
    } finally {
      calloc.free(pathPtr);
    }
  }

  bool loadLastSnapshotFromPath(Pointer<Void> engine, String path) {
    final load = _loadLastSnapshotFromPath;
    if (load == null) return false;
    final pathPtr = path.toNativeUtf8();
    try {
      return load(engine, pathPtr);
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Writes the current in-progress scan checkpoint to [path]; returns the
  /// checkpoint's `snapshot_id`, or `null` if no checkpoint API/checkpoint
  /// is available yet.
  String? writeLastCheckpointToPath(Pointer<Void> engine, String path) {
    final write = _writeLastCheckpointToPath;
    if (write == null) return null;
    final pathPtr = path.toNativeUtf8();
    try {
      final out = write(engine, pathPtr);
      return out.toDartString();
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Protobuf variant — encodes the snapshot as proto3 bytes and writes it
  /// atomically to [path] (temp+rename). Returns snapshot_id or `error:…`.
  String writeLastSnapshotToPathPb(Pointer<Void> engine, String path) {
    final write = _writeLastSnapshotToPathPb;
    if (write == null) {
      return 'error:native dylib missing volward_write_last_snapshot_to_path_pb — rebuild Rust';
    }
    final pathPtr = path.toNativeUtf8();
    try {
      final out = write(engine, pathPtr);
      return out.toDartString();
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Protobuf variant — encodes the last checkpoint as proto3 bytes and writes
  /// it atomically to [path] (temp+rename). Returns snapshot_id or `null`.
  String? writeLastCheckpointToPathPb(Pointer<Void> engine, String path) {
    final write = _writeLastCheckpointToPathPb;
    if (write == null) return null;
    final pathPtr = path.toNativeUtf8();
    try {
      final out = write(engine, pathPtr);
      return out.toDartString();
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Single-level, non-recursive listing of [path]. Returns an empty list
  /// if the native dylib doesn't support it yet (old build) or on error.
  List<Map<String, dynamic>> quickListDir(Pointer<Void> engine, String path) {
    final lookup = _quickListDirJson;
    if (lookup == null) return const [];
    final pathPtr = path.toNativeUtf8();
    try {
      final out = lookup(engine, pathPtr);
      if (out == nullptr) return const [];
      try {
        final decoded = jsonDecode(out.toDartString());
        if (decoded is! List) return const [];
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } finally {
        _freeString(out);
      }
    } finally {
      calloc.free(pathPtr);
    }
  }

  bool openPermissionSettings(Pointer<Void> engine) =>
      _openPermissionSettings(engine);

  Map<String, dynamic> deleteEntries(
    Pointer<Void> engine,
    String snapshotId,
    List<String> entryIds, {
    bool dryRun = false,
  }) {
    final snapshotPtr = snapshotId.toNativeUtf8();
    final idsPtr = jsonEncode(entryIds).toNativeUtf8();
    try {
      final out = _deleteEntriesJson(engine, snapshotPtr, idsPtr, dryRun);
      return _decodeJsonPtr(out);
    } finally {
      calloc.free(snapshotPtr);
      calloc.free(idsPtr);
    }
  }

  Map<String, dynamic> emptyTrash(Pointer<Void> engine) {
    final lookup = _emptyTrashJson;
    if (lookup == null) {
      return const {
        'error': 'native dylib missing volward_empty_trash_json — rebuild Rust',
      };
    }
    final out = lookup(engine);
    return _decodeJsonPtr(out);
  }

  Map<String, dynamic> _decodeJsonPtr(Pointer<Utf8> ptr) {
    try {
      final raw = ptr.toDartString();
      return jsonDecode(raw) as Map<String, dynamic>;
    } finally {
      _freeString(ptr);
    }
  }

  String? _decodeStringPtr(Pointer<Utf8> ptr) {
    if (ptr == nullptr) return null;
    try {
      return ptr.toDartString();
    } finally {
      _freeString(ptr);
    }
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isMacOS) {
      final exe = Platform.resolvedExecutable;
      final libPath =
          '${File(exe).parent.path}/../Frameworks/libvolward_facade.dylib';
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

  VolwardEmptyTrashJson? _tryLookupEmptyTrashJson() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardEmptyTrashJsonNative>>(
            'volward_empty_trash_json',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Catalog index API — try-lookup helpers + public methods
  // ---------------------------------------------------------------------------

  VolwardQueryDirectoryJson? _tryLookupQueryDirectoryJson() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardQueryDirectoryJsonNative>>(
            'volward_query_directory_json',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  VolwardRefreshDirectory? _tryLookupRefreshDirectory() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardRefreshDirectoryNative>>(
            'volward_refresh_directory',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  VolwardLoadIndexFromPath? _tryLookupLoadIndexFromPath() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardLoadIndexFromPathNative>>(
            'volward_load_index_from_path',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  VolwardStartLoadIndexFromPathAsync? _tryLookupStartLoadIndexFromPathAsync() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardStartLoadIndexFromPathAsyncNative>>(
            'volward_start_load_index_from_path_async',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  VolwardIsIndexLoading? _tryLookupIsIndexLoading() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardIsIndexLoadingNative>>(
            'volward_is_index_loading',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  VolwardInvalidateIndexLoad? _tryLookupInvalidateIndexLoad() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardInvalidateIndexLoadNative>>(
            'volward_invalidate_index_load',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  VolwardGetLastIndexLoadError? _tryLookupGetLastIndexLoadError() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardGetLastIndexLoadErrorNative>>(
            'volward_get_last_index_load_error',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  VolwardWriteLastIndexToPath? _tryLookupWriteLastIndexToPath() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardWriteLastIndexToPathNative>>(
            'volward_write_last_index_to_path',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  VolwardGetIndexSummaryJson? _tryLookupGetIndexSummaryJson() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardGetIndexSummaryJsonNative>>(
            'volward_get_index_summary_json',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  VolwardIndexVersion? _tryLookupIndexVersion() {
    try {
      return _lib
          .lookup<NativeFunction<VolwardIndexVersionNative>>(
            'volward_index_version',
          )
          .asFunction();
    } on Object {
      return null;
    }
  }

  /// Query direct children of [path] from the Rust catalog index.
  /// Returns a parsed `SnapshotQueryResult` JSON map.
  /// Pure in-memory — does NOT trigger a file-system scan.
  /// Throws [UnsupportedError] if the dylib lacks the index API.
  Map<String, dynamic> queryDirectoryJson(
    Pointer<Void> engine,
    String path, {
    String? categoryFilter,
    bool deletableOnly = false,
    String sortMode = 'size_desc',
  }) {
    final fn = _queryDirectoryJson;
    if (fn == null) {
      throw UnsupportedError(
        'volward_query_directory_json not available — rebuild Rust',
      );
    }
    final pathPtr = path.toNativeUtf8();
    final catPtr = categoryFilter != null
        ? categoryFilter.toNativeUtf8()
        : Pointer<Utf8>.fromAddress(0);
    final sortPtr = sortMode.toNativeUtf8();
    try {
      final out = fn(engine, pathPtr, catPtr, deletableOnly, sortPtr);
      return _decodeJsonPtr(out);
    } finally {
      calloc.free(pathPtr);
      if (categoryFilter != null) calloc.free(catPtr);
      calloc.free(sortPtr);
    }
  }

  /// Re-query the existing catalog for [path] — pure in-memory, no scan.
  /// Returns a parsed `SnapshotQueryResult` JSON map.
  /// Throws [UnsupportedError] if the dylib lacks the index API.
  Map<String, dynamic> refreshDirectory(Pointer<Void> engine, String path) {
    final fn = _refreshDirectory;
    if (fn == null) {
      throw UnsupportedError(
        'volward_refresh_directory not available — rebuild Rust',
      );
    }
    final pathPtr = path.toNativeUtf8();
    try {
      final out = fn(engine, pathPtr);
      return _decodeJsonPtr(out);
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Load a persisted index file into the engine. Returns true on success.
  bool loadIndexFromPath(Pointer<Void> engine, String path) {
    final fn = _loadIndexFromPath;
    if (fn == null) return false;
    final pathPtr = path.toNativeUtf8();
    try {
      return fn(engine, pathPtr);
    } finally {
      calloc.free(pathPtr);
    }
  }

  String? startLoadIndexFromPathAsync(Pointer<Void> engine, String path) {
    final fn = _startLoadIndexFromPathAsync;
    if (fn == null) return null;
    final pathPtr = path.toNativeUtf8();
    try {
      final out = fn(engine, pathPtr);
      return _decodeStringPtr(out);
    } finally {
      calloc.free(pathPtr);
    }
  }

  bool isIndexLoading(Pointer<Void> engine) {
    final fn = _isIndexLoading;
    if (fn == null) return false;
    return fn(engine);
  }

  void invalidateIndexLoad(Pointer<Void> engine) {
    final fn = _invalidateIndexLoad;
    if (fn == null) return;
    fn(engine);
  }

  String? getLastIndexLoadError(Pointer<Void> engine) {
    final fn = _getLastIndexLoadError;
    if (fn == null) return null;
    final out = fn(engine);
    return _decodeStringPtr(out);
  }

  /// Persist the current index to [path]. Returns snapshot_id or `error:…`.
  String? writeLastIndexToPath(Pointer<Void> engine, String path) {
    final fn = _writeLastIndexToPath;
    if (fn == null) return null;
    final pathPtr = path.toNativeUtf8();
    try {
      final out = fn(engine, pathPtr);
      return out.toDartString();
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Current lightweight index summary from Rust.
  Map<String, dynamic>? getIndexSummaryJson(Pointer<Void> engine) {
    final fn = _getIndexSummaryJson;
    if (fn == null) return null;
    final out = fn(engine);
    return _decodeJsonPtr(out);
  }

  /// Current catalog version counter from Rust.
  /// Dart uses this as [SnapshotQueryKey.version] for cache alignment.
  int indexVersion(Pointer<Void> engine) {
    final fn = _indexVersion;
    if (fn == null) return 0;
    return fn(engine);
  }
}
