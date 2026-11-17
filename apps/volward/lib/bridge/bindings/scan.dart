import 'dart:ffi';

import 'package:ffi/ffi.dart';

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

typedef VolwardStartScanAsyncNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardStartScanAsync = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef VolwardStartScanAsyncWithOptionsNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Bool,
);
typedef VolwardStartScanAsyncWithOptions = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  bool,
);

typedef VolwardIsScanRunningNative = Bool Function(Pointer<Void>);
typedef VolwardIsScanRunning = bool Function(Pointer<Void>);

typedef VolwardGetLastProgressJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
);
typedef VolwardGetLastProgressJson = Pointer<Utf8> Function(Pointer<Void>);

typedef VolwardCancelScanNative = Void Function(Pointer<Void>);
typedef VolwardCancelScan = void Function(Pointer<Void>);

typedef VolwardRequestScanPauseNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardRequestScanPause = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef VolwardGetLastPauseErrorNative = Pointer<Utf8> Function(Pointer<Void>);
typedef VolwardGetLastPauseError = Pointer<Utf8> Function(Pointer<Void>);

typedef VolwardQuickListDirJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardQuickListDirJson = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
