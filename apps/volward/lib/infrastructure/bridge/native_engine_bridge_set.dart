import 'ai_bridge.dart';
import 'capability_bridge.dart';
import 'delete_bridge.dart';
import 'engine_bridge.dart';
import 'index_bridge.dart';
import 'scan_bridge.dart';

export 'ai_bridge.dart';
export 'capability_bridge.dart';
export 'delete_bridge.dart';
export 'engine_bridge.dart';
export 'index_bridge.dart';
export 'scan_bridge.dart';

/// The single composition seam that supplies runtime bridge families to the
/// engine host. Feature and session ports never expose these implementations.
final class NativeEngineBridgeSet {
  const NativeEngineBridgeSet({
    required this.engine,
    required this.scan,
    required this.index,
    required this.delete,
    required this.capability,
    required this.ai,
  });

  final EngineBridge engine;
  final ScanBridge scan;
  final IndexBridge index;
  final DeleteBridge delete;
  final CapabilityBridge capability;
  final AiBridge ai;
}
