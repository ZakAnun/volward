import 'dart:ffi';

import 'native_engine_ports.dart';

/// Infrastructure composition required by [EngineHost].
///
/// The backend owns bridge details. EngineHost owns the native pointer and
/// exposes only pointer-free ports to session consumers.
abstract interface class EngineHostBackend {
  Pointer<Void> createEngine();
  void freeEngine(Pointer<Void> engine);
  Map<String, dynamic> probeCapabilities(Pointer<Void> engine);
  bool isDeepScanReady(Pointer<Void> engine);

  ScanEnginePort bindScan(Pointer<Void> engine, void Function() ensureOpen);
  IndexEnginePort bindIndex(Pointer<Void> engine, void Function() ensureOpen);
  DeleteEnginePort bindDelete(Pointer<Void> engine, void Function() ensureOpen);
  CapabilityEnginePort bindCapability(
    Pointer<Void> engine,
    void Function() ensureOpen,
  );
  AiEnginePort bindAi(Pointer<Void> engine, void Function() ensureOpen);
}
