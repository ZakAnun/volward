import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef VolwardProbeCapabilitiesJsonNative =
    Pointer<Utf8> Function(Pointer<Void>);
typedef VolwardProbeCapabilitiesJson = Pointer<Utf8> Function(Pointer<Void>);

typedef VolwardIsDeepScanReadyNative = Bool Function(Pointer<Void>);
typedef VolwardIsDeepScanReady = bool Function(Pointer<Void>);

typedef VolwardOpenPermissionSettingsNative = Bool Function(Pointer<Void>);
typedef VolwardOpenPermissionSettings = bool Function(Pointer<Void>);

typedef VolwardAnalyzeCapabilityJsonNative =
    Pointer<Utf8> Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef VolwardAnalyzeCapabilityJson =
    Pointer<Utf8> Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );

typedef VolwardStartCapabilityAnalysisJsonNative =
    Pointer<Utf8> Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef VolwardStartCapabilityAnalysisJson =
    Pointer<Utf8> Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );

typedef VolwardGetCapabilityJobStatusJsonNative =
    Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef VolwardGetCapabilityJobStatusJson =
    Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);

typedef VolwardCancelCapabilityAnalysisNative =
    Bool Function(Pointer<Void>, Pointer<Utf8>);
typedef VolwardCancelCapabilityAnalysis =
    bool Function(Pointer<Void>, Pointer<Utf8>);
