import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../bridge/bindings/delete.dart';
import 'runtime/native_library.dart';
import 'runtime/native_string.dart';

abstract interface class DeleteBridge {
  Map<String, dynamic> deleteEntries(
    Pointer<Void> engine,
    String snapshotId,
    List<String> entryIds, {
    bool dryRun = false,
  });

  Map<String, dynamic> emptyTrash(Pointer<Void> engine);
}

class DeleteNativeBridge implements DeleteBridge {
  DeleteNativeBridge(NativeLibraryHandle library, this._codec)
    : _deleteEntriesJson = library
          .lookup<NativeFunction<VolwardDeleteEntriesJsonNative>>(
            'volward_delete_entries_json',
          )
          .asFunction(),
      _emptyTrashJson = library
          .tryLookup<NativeFunction<VolwardEmptyTrashJsonNative>>(
            'volward_empty_trash_json',
          )
          ?.asFunction();

  final NativeStringCodec _codec;
  final VolwardDeleteEntriesJson _deleteEntriesJson;
  final VolwardEmptyTrashJson? _emptyTrashJson;

  @override
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
      return jsonDecode(_codec.decodeAndFree(out)) as Map<String, dynamic>;
    } finally {
      calloc.free(snapshotPtr);
      calloc.free(idsPtr);
    }
  }

  @override
  Map<String, dynamic> emptyTrash(Pointer<Void> engine) {
    final fn = _emptyTrashJson;
    if (fn == null) {
      return const {
        'error': 'native dylib missing volward_empty_trash_json — rebuild Rust',
      };
    }
    return jsonDecode(_codec.decodeAndFree(fn(engine))) as Map<String, dynamic>;
  }
}
