import 'dart:convert';
import 'capability_models.dart';
import 'capability_result_cache.dart';

typedef CapabilityCall =
    String Function({
      required String mode,
      String? snapshotId,
      Capability? capability,
      AnalysisOptions? options,
      String? jobId,
    });

/// Capability request/response orchestration. Session owns cache invalidation,
/// native engine lifetime, test hooks, and job polling.
class CapabilityAnalysis {
  CapabilityAnalysis({
    required this.cache,
    required this.call,
    required this.cancel,
  });
  final CapabilityAnalysisCache cache;
  final CapabilityCall call;
  final bool Function(String jobId) cancel;

  Future<CapabilityAnalysisResult> analyzeCapability({
    required String snapshotId,
    required Capability capability,
    AnalysisOptions? options,
  }) async {
    final resolved = options ?? const AnalysisOptions(rootPath: '');
    // Paginated requests carry a cursor and must always hit the analyzer;
    // only terminal (cursor-less) results are cached.
    if (resolved.cursor == null) {
      final cached = cache.get(snapshotId, capability, resolved);
      if (cached != null) {
        return cached;
      }
    }
    final raw = call(
      mode: 'analyze',
      snapshotId: snapshotId,
      capability: capability,
      options: resolved,
    );
    final result = _decodeCapabilityResult(raw, capability);
    if (resolved.cursor == null) {
      cache.put(snapshotId, capability, resolved, result);
    }
    return result;
  }

  /// Starts an async capability job and returns its job id.
  String startCapabilityAnalysis({
    required String snapshotId,
    required Capability capability,
    AnalysisOptions? options,
  }) {
    final resolved = options ?? const AnalysisOptions(rootPath: '');
    final raw = call(
      mode: 'start',
      snapshotId: snapshotId,
      capability: capability,
      options: resolved,
    );
    final decoded = _decodeCapabilityJson(raw, capability, 'start');
    final error = decoded['error'];
    if (error != null) {
      throw StateError(
        'capability ${capability.wireValue} start failed: '
        '${error is Map<String, dynamic> ? '${error['code']}: ${error['message']}' : error}',
      );
    }
    final jobId = decoded['job_id'];
    if (jobId is! String || jobId.isEmpty) {
      throw FormatException(
        'capability ${capability.wireValue} start response missing job_id',
      );
    }
    return jobId;
  }

  Map<String, dynamic> _decodeCapabilityJson(
    String raw,
    Capability capability,
    String context,
  ) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw FormatException(
        'invalid capability $context response for ${capability.wireValue}: $raw',
      );
    }
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw FormatException(
      'invalid capability $context response for ${capability.wireValue}: $raw',
    );
  }

  CapabilityAnalysisResult _decodeCapabilityResult(
    String raw,
    Capability capability,
  ) {
    final decoded = _decodeCapabilityJson(raw, capability, 'analyze');
    final error = decoded['error'];
    if (error != null) {
      throw StateError(
        'capability ${capability.wireValue} failed: '
        '${error is Map<String, dynamic> ? '${error['code']}: ${error['message']}' : error}',
      );
    }
    final result = decoded['result'];
    if (result is! Map<String, dynamic>) {
      throw FormatException(
        'capability ${capability.wireValue} analyze response missing result',
      );
    }
    return CapabilityAnalysisResult.fromJson(result);
  }

  CapabilityJobStatus getJobStatus(String jobId) {
    final raw = call(mode: 'status', jobId: jobId);
    final decoded = _decodeCapabilityJson(
      raw,
      Capability.spaceAnalysis,
      'status',
    );
    final error = decoded['error'];
    if (error != null) {
      throw StateError(
        'capability job failed: ${error is Map<String, dynamic> ? '${error['code']}: ${error['message']}' : error}',
      );
    }
    return CapabilityJobStatus.fromJson(decoded);
  }
}
