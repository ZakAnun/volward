import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../bridge/bindings/index.dart';
import 'runtime/native_library.dart';
import 'runtime/native_string.dart';

abstract interface class IndexBridge {
  bool get hasSnapshotFileApi;
  bool get hasSnapshotFilePbApi;
  bool get hasCheckpointApi;
  bool get hasIndexApi;
  bool get hasReplaceSubtreeApi;
  bool get hasAsyncIndexLoadApi;

  Map<String, dynamic>? getLastSnapshot(Pointer<Void> engine);

  bool setLastSnapshot(Pointer<Void> engine, Map<String, dynamic> snapshot);

  String writeLastSnapshotToPath(Pointer<Void> engine, String path);

  bool loadLastSnapshotFromPath(Pointer<Void> engine, String path);

  String? writeLastCheckpointToPath(Pointer<Void> engine, String path);

  String writeLastSnapshotToPathPb(Pointer<Void> engine, String path);

  String? writeLastCheckpointToPathPb(Pointer<Void> engine, String path);

  Map<String, dynamic> queryDirectoryJson(
    Pointer<Void> engine,
    String path, {
    String? categoryFilter,
    bool deletableOnly = false,
    String sortMode = 'size_desc',
  });

  Map<String, dynamic> refreshDirectory(Pointer<Void> engine, String path);

  bool loadIndexFromPath(Pointer<Void> engine, String path);

  int? replaceDirectoryWithSubtree(
    Pointer<Void> engine,
    String targetPath,
    String subtreeJson,
  );

  String? startLoadIndexFromPathAsync(Pointer<Void> engine, String path);

  bool isIndexLoading(Pointer<Void> engine);

  void invalidateIndexLoad(Pointer<Void> engine);

  String? getLastIndexLoadError(Pointer<Void> engine);

  String? writeLastIndexToPath(Pointer<Void> engine, String path);

  Map<String, dynamic>? getIndexSummaryJson(Pointer<Void> engine);

  int indexVersion(Pointer<Void> engine);
}

class IndexNativeBridge implements IndexBridge {
  IndexNativeBridge(NativeLibraryHandle library, this._codec)
    : _getLastSnapshotJson = library
          .lookup<NativeFunction<VolwardGetLastSnapshotJsonNative>>(
            'volward_get_last_snapshot_json',
          )
          .asFunction(),
      _setLastSnapshotJson = library
          .lookup<NativeFunction<VolwardSetLastSnapshotJsonNative>>(
            'volward_set_last_snapshot_json',
          )
          .asFunction(),
      _writeLastSnapshotToPath = _tryLookupWriteSnapshot(library),
      _loadLastSnapshotFromPath = _tryLookupLoadSnapshot(library),
      _writeLastCheckpointToPath = _tryLookupWriteCheckpoint(library),
      _writeLastSnapshotToPathPb = _tryLookupWriteSnapshotPb(library),
      _writeLastCheckpointToPathPb = _tryLookupWriteCheckpointPb(library),
      _queryDirectoryJson = _tryLookupQueryDirectoryJson(library),
      _refreshDirectory = _tryLookupRefreshDirectory(library),
      _loadIndexFromPath = _tryLookupLoadIndexFromPath(library),
      _startLoadIndexFromPathAsync = _tryLookupStartLoadIndexFromPathAsync(
        library,
      ),
      _isIndexLoading = _tryLookupIsIndexLoading(library),
      _invalidateIndexLoad = _tryLookupInvalidateIndexLoad(library),
      _getLastIndexLoadError = _tryLookupGetLastIndexLoadError(library),
      _writeLastIndexToPath = _tryLookupWriteLastIndexToPath(library),
      _getIndexSummaryJson = _tryLookupGetIndexSummaryJson(library),
      _indexVersion = _tryLookupIndexVersion(library),
      _replaceDirectoryWithSubtree = _tryLookupReplaceDirectoryWithSubtree(
        library,
      );

  final NativeStringCodec _codec;
  final VolwardGetLastSnapshotJson _getLastSnapshotJson;
  final VolwardSetLastSnapshotJson _setLastSnapshotJson;
  final VolwardWriteLastSnapshotToPath? _writeLastSnapshotToPath;
  final VolwardLoadLastSnapshotFromPath? _loadLastSnapshotFromPath;
  final VolwardWriteLastCheckpointToPath? _writeLastCheckpointToPath;
  final VolwardWriteLastSnapshotToPathPb? _writeLastSnapshotToPathPb;
  final VolwardWriteLastCheckpointToPathPb? _writeLastCheckpointToPathPb;
  final VolwardQueryDirectoryJson? _queryDirectoryJson;
  final VolwardRefreshDirectory? _refreshDirectory;
  final VolwardLoadIndexFromPath? _loadIndexFromPath;
  final VolwardStartLoadIndexFromPathAsync? _startLoadIndexFromPathAsync;
  final VolwardIsIndexLoading? _isIndexLoading;
  final VolwardInvalidateIndexLoad? _invalidateIndexLoad;
  final VolwardGetLastIndexLoadError? _getLastIndexLoadError;
  final VolwardWriteLastIndexToPath? _writeLastIndexToPath;
  final VolwardGetIndexSummaryJson? _getIndexSummaryJson;
  final VolwardIndexVersion? _indexVersion;
  final VolwardReplaceDirectoryWithSubtree? _replaceDirectoryWithSubtree;

  @override
  bool get hasSnapshotFileApi =>
      _writeLastSnapshotToPath != null && _loadLastSnapshotFromPath != null;

  @override
  bool get hasSnapshotFilePbApi =>
      _writeLastSnapshotToPathPb != null &&
      _writeLastCheckpointToPathPb != null;

  @override
  bool get hasCheckpointApi => _writeLastCheckpointToPath != null;

  @override
  bool get hasIndexApi =>
      _queryDirectoryJson != null &&
      _refreshDirectory != null &&
      _loadIndexFromPath != null &&
      _writeLastIndexToPath != null &&
      _getIndexSummaryJson != null;

  @override
  bool get hasReplaceSubtreeApi => _replaceDirectoryWithSubtree != null;

  @override
  bool get hasAsyncIndexLoadApi =>
      _startLoadIndexFromPathAsync != null &&
      _isIndexLoading != null &&
      _invalidateIndexLoad != null &&
      _getLastIndexLoadError != null;

  @override
  Map<String, dynamic>? getLastSnapshot(Pointer<Void> engine) {
    return _decodeNullableJson(_getLastSnapshotJson(engine));
  }

  @override
  bool setLastSnapshot(Pointer<Void> engine, Map<String, dynamic> snapshot) {
    final jsonPtr = jsonEncode(snapshot).toNativeUtf8();
    try {
      return _setLastSnapshotJson(engine, jsonPtr);
    } finally {
      calloc.free(jsonPtr);
    }
  }

  @override
  String writeLastSnapshotToPath(Pointer<Void> engine, String path) {
    final write = _writeLastSnapshotToPath;
    if (write == null) {
      return 'error:native dylib missing volward_write_last_snapshot_to_path — rebuild Rust';
    }
    final pathPtr = path.toNativeUtf8();
    try {
      return _codec.decodeAndFree(write(engine, pathPtr));
    } finally {
      calloc.free(pathPtr);
    }
  }

  @override
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

  @override
  String? writeLastCheckpointToPath(Pointer<Void> engine, String path) {
    final write = _writeLastCheckpointToPath;
    if (write == null) return null;
    final pathPtr = path.toNativeUtf8();
    try {
      return _codec.decodeAndFreeNullable(write(engine, pathPtr));
    } finally {
      calloc.free(pathPtr);
    }
  }

  @override
  String writeLastSnapshotToPathPb(Pointer<Void> engine, String path) {
    final write = _writeLastSnapshotToPathPb;
    if (write == null) {
      return 'error:native dylib missing volward_write_last_snapshot_to_path_pb — rebuild Rust';
    }
    final pathPtr = path.toNativeUtf8();
    try {
      return _codec.decodeAndFree(write(engine, pathPtr));
    } finally {
      calloc.free(pathPtr);
    }
  }

  @override
  String? writeLastCheckpointToPathPb(Pointer<Void> engine, String path) {
    final write = _writeLastCheckpointToPathPb;
    if (write == null) return null;
    final pathPtr = path.toNativeUtf8();
    try {
      return _codec.decodeAndFreeNullable(write(engine, pathPtr));
    } finally {
      calloc.free(pathPtr);
    }
  }

  @override
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
      return _decodeJson(fn(engine, pathPtr, catPtr, deletableOnly, sortPtr));
    } finally {
      calloc.free(pathPtr);
      if (categoryFilter != null) calloc.free(catPtr);
      calloc.free(sortPtr);
    }
  }

  @override
  Map<String, dynamic> refreshDirectory(Pointer<Void> engine, String path) {
    final fn = _refreshDirectory;
    if (fn == null) {
      throw UnsupportedError(
        'volward_refresh_directory not available — rebuild Rust',
      );
    }
    final pathPtr = path.toNativeUtf8();
    try {
      return _decodeJson(fn(engine, pathPtr));
    } finally {
      calloc.free(pathPtr);
    }
  }

  @override
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

  @override
  int? replaceDirectoryWithSubtree(
    Pointer<Void> engine,
    String targetPath,
    String subtreeJson,
  ) {
    final fn = _replaceDirectoryWithSubtree;
    if (fn == null) return null;
    final pathPtr = targetPath.toNativeUtf8();
    final jsonPtr = subtreeJson.toNativeUtf8();
    try {
      final raw = _codec.decodeAndFreeNullable(fn(engine, pathPtr, jsonPtr));
      if (raw == null || raw.startsWith('{')) return null;
      return int.tryParse(raw);
    } finally {
      calloc.free(pathPtr);
      calloc.free(jsonPtr);
    }
  }

  @override
  String? startLoadIndexFromPathAsync(Pointer<Void> engine, String path) {
    final fn = _startLoadIndexFromPathAsync;
    if (fn == null) return null;
    final pathPtr = path.toNativeUtf8();
    try {
      return _codec.decodeAndFreeNullable(fn(engine, pathPtr));
    } finally {
      calloc.free(pathPtr);
    }
  }

  @override
  bool isIndexLoading(Pointer<Void> engine) {
    final fn = _isIndexLoading;
    if (fn == null) return false;
    return fn(engine);
  }

  @override
  void invalidateIndexLoad(Pointer<Void> engine) {
    _invalidateIndexLoad?.call(engine);
  }

  @override
  String? getLastIndexLoadError(Pointer<Void> engine) {
    final fn = _getLastIndexLoadError;
    if (fn == null) return null;
    return _codec.decodeAndFreeNullable(fn(engine));
  }

  @override
  String? writeLastIndexToPath(Pointer<Void> engine, String path) {
    final fn = _writeLastIndexToPath;
    if (fn == null) return null;
    final pathPtr = path.toNativeUtf8();
    try {
      return _codec.decodeAndFree(fn(engine, pathPtr));
    } finally {
      calloc.free(pathPtr);
    }
  }

  @override
  Map<String, dynamic>? getIndexSummaryJson(Pointer<Void> engine) {
    final fn = _getIndexSummaryJson;
    if (fn == null) return null;
    return _decodeNullableJson(fn(engine));
  }

  @override
  int indexVersion(Pointer<Void> engine) {
    final fn = _indexVersion;
    if (fn == null) return 0;
    return fn(engine);
  }

  Map<String, dynamic> _decodeJson(Pointer<Utf8> ptr) {
    return jsonDecode(_codec.decodeAndFree(ptr)) as Map<String, dynamic>;
  }

  Map<String, dynamic>? _decodeNullableJson(Pointer<Utf8> ptr) {
    final raw = _codec.decodeAndFreeNullable(ptr);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static VolwardWriteLastSnapshotToPath? _tryLookupWriteSnapshot(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardWriteLastSnapshotToPathNative>>(
          'volward_write_last_snapshot_to_path',
        )
        ?.asFunction();
  }

  static VolwardLoadLastSnapshotFromPath? _tryLookupLoadSnapshot(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardLoadLastSnapshotFromPathNative>>(
          'volward_load_last_snapshot_from_path',
        )
        ?.asFunction();
  }

  static VolwardWriteLastCheckpointToPath? _tryLookupWriteCheckpoint(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardWriteLastCheckpointToPathNative>>(
          'volward_write_last_checkpoint_to_path',
        )
        ?.asFunction();
  }

  static VolwardWriteLastSnapshotToPathPb? _tryLookupWriteSnapshotPb(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardWriteLastSnapshotToPathPbNative>>(
          'volward_write_last_snapshot_to_path_pb',
        )
        ?.asFunction();
  }

  static VolwardWriteLastCheckpointToPathPb? _tryLookupWriteCheckpointPb(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardWriteLastCheckpointToPathPbNative>>(
          'volward_write_last_checkpoint_to_path_pb',
        )
        ?.asFunction();
  }

  static VolwardQueryDirectoryJson? _tryLookupQueryDirectoryJson(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardQueryDirectoryJsonNative>>(
          'volward_query_directory_json',
        )
        ?.asFunction();
  }

  static VolwardRefreshDirectory? _tryLookupRefreshDirectory(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardRefreshDirectoryNative>>(
          'volward_refresh_directory',
        )
        ?.asFunction();
  }

  static VolwardLoadIndexFromPath? _tryLookupLoadIndexFromPath(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardLoadIndexFromPathNative>>(
          'volward_load_index_from_path',
        )
        ?.asFunction();
  }

  static VolwardStartLoadIndexFromPathAsync?
  _tryLookupStartLoadIndexFromPathAsync(NativeLibraryHandle library) {
    return library
        .tryLookup<NativeFunction<VolwardStartLoadIndexFromPathAsyncNative>>(
          'volward_start_load_index_from_path_async',
        )
        ?.asFunction();
  }

  static VolwardIsIndexLoading? _tryLookupIsIndexLoading(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardIsIndexLoadingNative>>(
          'volward_is_index_loading',
        )
        ?.asFunction();
  }

  static VolwardInvalidateIndexLoad? _tryLookupInvalidateIndexLoad(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardInvalidateIndexLoadNative>>(
          'volward_invalidate_index_load',
        )
        ?.asFunction();
  }

  static VolwardGetLastIndexLoadError? _tryLookupGetLastIndexLoadError(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardGetLastIndexLoadErrorNative>>(
          'volward_get_last_index_load_error',
        )
        ?.asFunction();
  }

  static VolwardWriteLastIndexToPath? _tryLookupWriteLastIndexToPath(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardWriteLastIndexToPathNative>>(
          'volward_write_last_index_to_path',
        )
        ?.asFunction();
  }

  static VolwardGetIndexSummaryJson? _tryLookupGetIndexSummaryJson(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardGetIndexSummaryJsonNative>>(
          'volward_get_index_summary_json',
        )
        ?.asFunction();
  }

  static VolwardIndexVersion? _tryLookupIndexVersion(
    NativeLibraryHandle library,
  ) {
    return library
        .tryLookup<NativeFunction<VolwardIndexVersionNative>>(
          'volward_index_version',
        )
        ?.asFunction();
  }

  static VolwardReplaceDirectoryWithSubtree?
  _tryLookupReplaceDirectoryWithSubtree(NativeLibraryHandle library) {
    return library
        .tryLookup<NativeFunction<VolwardReplaceDirectoryWithSubtreeNative>>(
          'volward_replace_directory_with_subtree',
        )
        ?.asFunction();
  }
}
