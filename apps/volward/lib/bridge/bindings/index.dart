import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef VolwardGetLastSnapshotJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
);
typedef VolwardGetLastSnapshotJson = Pointer<Utf8> Function(Pointer<Void>);

typedef VolwardSetLastSnapshotJsonNative = Bool Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardSetLastSnapshotJson = bool Function(
  Pointer<Void>,
  Pointer<Utf8>,
);

typedef VolwardWriteLastSnapshotToPathNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardWriteLastSnapshotToPath = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);

typedef VolwardLoadLastSnapshotFromPathNative = Bool Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardLoadLastSnapshotFromPath = bool Function(
  Pointer<Void>,
  Pointer<Utf8>,
);

typedef VolwardWriteLastCheckpointToPathNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardWriteLastCheckpointToPath = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);

typedef VolwardWriteLastSnapshotToPathPbNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardWriteLastSnapshotToPathPb = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);

typedef VolwardWriteLastCheckpointToPathPbNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardWriteLastCheckpointToPathPb = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);

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
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardRefreshDirectory = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);

typedef VolwardLoadIndexFromPathNative = Bool Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardLoadIndexFromPath = bool Function(Pointer<Void>, Pointer<Utf8>);

typedef VolwardStartLoadIndexFromPathAsyncNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardStartLoadIndexFromPathAsync = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);

typedef VolwardIsIndexLoadingNative = Bool Function(Pointer<Void>);
typedef VolwardIsIndexLoading = bool Function(Pointer<Void>);

typedef VolwardInvalidateIndexLoadNative = Void Function(Pointer<Void>);
typedef VolwardInvalidateIndexLoad = void Function(Pointer<Void>);

typedef VolwardGetLastIndexLoadErrorNative = Pointer<Utf8> Function(
  Pointer<Void>,
);
typedef VolwardGetLastIndexLoadError = Pointer<Utf8> Function(Pointer<Void>);

typedef VolwardWriteLastIndexToPathNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardWriteLastIndexToPath = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);

typedef VolwardGetIndexSummaryJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
);
typedef VolwardGetIndexSummaryJson = Pointer<Utf8> Function(Pointer<Void>);

typedef VolwardIndexVersionNative = Uint64 Function(Pointer<Void>);
typedef VolwardIndexVersion = int Function(Pointer<Void>);

typedef VolwardReplaceDirectoryWithSubtreeNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardReplaceDirectoryWithSubtree = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
