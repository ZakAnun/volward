import 'package:flutter/foundation.dart';

/// Debug-only tracing for Quick vs Full coverage diagnostics (stripped in release).
void volwardAiDebugLog(String message) {
  if (kDebugMode) {
    debugPrint('Volward AI: $message');
  }
}
