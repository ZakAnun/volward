/// Scan and recovery actions used by the home page.
///
/// [ScanSession] owns the mutable implementation. Page code depends on this
/// interface rather than the legacy Session facade.
export '../../core/contracts/scan_contracts.dart' show ScanLifecycle;
