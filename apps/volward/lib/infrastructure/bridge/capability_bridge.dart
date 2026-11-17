import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../bridge/bindings/capabilities.dart';
import 'runtime/native_library.dart';
import 'runtime/native_string.dart';

abstract interface class CapabilityBridge {
  bool get hasCapabilityApi;

  Map<String, dynamic> probeCapabilities(Pointer<Void> engine);

  bool isDeepScanReady(Pointer<Void> engine);

  bool openPermissionSettings(Pointer<Void> engine);

  String analyzeCapability(
    Pointer<Void> engine,
    String snapshotId,
    String capability,
    String optionsJson,
  );

  String startCapabilityAnalysis(
    Pointer<Void> engine,
    String snapshotId,
    String capability,
    String optionsJson,
  );

  String getCapabilityJobStatus(Pointer<Void> engine, String jobId);

  bool cancelCapabilityAnalysis(Pointer<Void> engine, String jobId);
}

class CapabilityNativeBridge implements CapabilityBridge {
  CapabilityNativeBridge(NativeLibraryHandle library, this._codec)
    : _probeCapabilitiesJson = library
          .lookup<NativeFunction<VolwardProbeCapabilitiesJsonNative>>(
            'volward_probe_capabilities_json',
          )
          .asFunction(),
      _isDeepScanReady = library
          .lookup<NativeFunction<VolwardIsDeepScanReadyNative>>(
            'volward_is_deep_scan_ready',
          )
          .asFunction(),
      _openPermissionSettings = library
          .lookup<NativeFunction<VolwardOpenPermissionSettingsNative>>(
            'volward_open_permission_settings',
          )
          .asFunction(),
      _analyzeCapabilityJson = library
          .tryLookup<NativeFunction<VolwardAnalyzeCapabilityJsonNative>>(
            'volward_analyze_capability_json',
          )
          ?.asFunction(),
      _startCapabilityAnalysisJson = library
          .tryLookup<NativeFunction<VolwardStartCapabilityAnalysisJsonNative>>(
            'volward_start_capability_analysis_json',
          )
          ?.asFunction(),
      _getCapabilityJobStatusJson = library
          .tryLookup<NativeFunction<VolwardGetCapabilityJobStatusJsonNative>>(
            'volward_get_capability_job_status_json',
          )
          ?.asFunction(),
      _cancelCapabilityAnalysis = library
          .tryLookup<NativeFunction<VolwardCancelCapabilityAnalysisNative>>(
            'volward_cancel_capability_analysis',
          )
          ?.asFunction();

  final NativeStringCodec _codec;
  final VolwardProbeCapabilitiesJson _probeCapabilitiesJson;
  final VolwardIsDeepScanReady _isDeepScanReady;
  final VolwardOpenPermissionSettings _openPermissionSettings;
  final VolwardAnalyzeCapabilityJson? _analyzeCapabilityJson;
  final VolwardStartCapabilityAnalysisJson? _startCapabilityAnalysisJson;
  final VolwardGetCapabilityJobStatusJson? _getCapabilityJobStatusJson;
  final VolwardCancelCapabilityAnalysis? _cancelCapabilityAnalysis;

  @override
  bool get hasCapabilityApi =>
      _analyzeCapabilityJson != null &&
      _startCapabilityAnalysisJson != null &&
      _getCapabilityJobStatusJson != null &&
      _cancelCapabilityAnalysis != null;

  @override
  Map<String, dynamic> probeCapabilities(Pointer<Void> engine) {
    final out = _probeCapabilitiesJson(engine);
    return jsonDecode(_codec.decodeAndFree(out)) as Map<String, dynamic>;
  }

  @override
  bool isDeepScanReady(Pointer<Void> engine) => _isDeepScanReady(engine);

  @override
  bool openPermissionSettings(Pointer<Void> engine) =>
      _openPermissionSettings(engine);

  @override
  String analyzeCapability(
    Pointer<Void> engine,
    String snapshotId,
    String capability,
    String optionsJson,
  ) {
    final fn = _analyzeCapabilityJson;
    if (fn == null) {
      return 'error:native dylib missing volward_analyze_capability_json — rebuild Rust';
    }
    final snapshotPtr = snapshotId.toNativeUtf8();
    final capabilityPtr = capability.toNativeUtf8();
    final optionsPtr = optionsJson.toNativeUtf8();
    try {
      final out = fn(engine, snapshotPtr, capabilityPtr, optionsPtr);
      return _codec.decodeAndFreeNullable(out) ??
          'error:null capability response';
    } finally {
      calloc.free(snapshotPtr);
      calloc.free(capabilityPtr);
      calloc.free(optionsPtr);
    }
  }

  @override
  String startCapabilityAnalysis(
    Pointer<Void> engine,
    String snapshotId,
    String capability,
    String optionsJson,
  ) {
    final fn = _startCapabilityAnalysisJson;
    if (fn == null) {
      return 'error:native dylib missing volward_start_capability_analysis_json — rebuild Rust';
    }
    final snapshotPtr = snapshotId.toNativeUtf8();
    final capabilityPtr = capability.toNativeUtf8();
    final optionsPtr = optionsJson.toNativeUtf8();
    try {
      final out = fn(engine, snapshotPtr, capabilityPtr, optionsPtr);
      return _codec.decodeAndFreeNullable(out) ??
          'error:null capability start response';
    } finally {
      calloc.free(snapshotPtr);
      calloc.free(capabilityPtr);
      calloc.free(optionsPtr);
    }
  }

  @override
  String getCapabilityJobStatus(Pointer<Void> engine, String jobId) {
    final fn = _getCapabilityJobStatusJson;
    if (fn == null) {
      return 'error:native dylib missing volward_get_capability_job_status_json — rebuild Rust';
    }
    final jobPtr = jobId.toNativeUtf8();
    try {
      final out = fn(engine, jobPtr);
      return _codec.decodeAndFreeNullable(out) ??
          'error:null capability status';
    } finally {
      calloc.free(jobPtr);
    }
  }

  @override
  bool cancelCapabilityAnalysis(Pointer<Void> engine, String jobId) {
    final fn = _cancelCapabilityAnalysis;
    if (fn == null) return false;
    final jobPtr = jobId.toNativeUtf8();
    try {
      return fn(engine, jobPtr);
    } finally {
      calloc.free(jobPtr);
    }
  }
}
