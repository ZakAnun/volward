import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../capabilities/capability_analysis.dart';
import '../../capabilities/capability_models.dart';
import '../../capabilities/capability_result_cache.dart';
import '../contracts/native_engine_ports.dart';

typedef CapabilityEngineProvider = CapabilityEnginePort? Function();

/// Owns capability cache, dispatch and job polling.
class CapabilitySession {
  CapabilitySession(this._engineProvider, this._ready, this._initError) {
    _analysis = CapabilityAnalysis(cache: _cache, call: _call, cancel: _cancel);
  }

  final CapabilityEngineProvider _engineProvider;
  final bool Function() _ready;
  final String? Function() _initError;
  final CapabilityAnalysisCache _cache = CapabilityAnalysisCache();
  late final CapabilityAnalysis _analysis;

  @visibleForTesting
  String Function(String snapshotId, String capability, String optionsJson)?
  capabilityAnalyzeRunnerForTest;
  @visibleForTesting
  String Function(String snapshotId, String capability, String optionsJson)?
  capabilityStartRunnerForTest;
  @visibleForTesting
  String Function(String jobId)? capabilityStatusReaderForTest;
  @visibleForTesting
  bool Function(String jobId)? capabilityCancelRunnerForTest;

  bool get hasCapabilityApi =>
      _ready() && (_engineProvider()?.hasCapabilityApi ?? false);

  Future<CapabilityAnalysisResult> analyzeCapability({
    required String snapshotId,
    required Capability capability,
    AnalysisOptions? options,
  }) => _analysis.analyzeCapability(
    snapshotId: snapshotId,
    capability: capability,
    options: options,
  );

  String startCapabilityAnalysis({
    required String snapshotId,
    required Capability capability,
    AnalysisOptions? options,
  }) => _analysis.startCapabilityAnalysis(
    snapshotId: snapshotId,
    capability: capability,
    options: options,
  );

  CapabilityJobStatus getCapabilityJobStatus(String jobId) =>
      _analysis.getJobStatus(jobId);

  bool cancelCapabilityAnalysis(String jobId) => _analysis.cancel(jobId);

  Stream<CapabilityAnalysisProgress> watchCapabilityJob(
    String jobId, {
    Duration pollInterval = const Duration(milliseconds: 300),
  }) async* {
    while (true) {
      final status = getCapabilityJobStatus(jobId);
      yield status.progress;
      if (status.isTerminal) return;
      await Future<void>.delayed(pollInterval);
    }
  }

  void invalidateForSnapshot(String? snapshotId) {
    if (snapshotId != null && snapshotId.isNotEmpty) {
      _cache.invalidateForSnapshot(snapshotId);
    }
  }

  String _call({
    required String mode,
    String? snapshotId,
    Capability? capability,
    AnalysisOptions? options,
    String? jobId,
  }) {
    if (mode == 'status') {
      final runner = capabilityStatusReaderForTest;
      if (runner != null) return runner(jobId!);
    }
    final runner = switch (mode) {
      'analyze' => capabilityAnalyzeRunnerForTest,
      'start' => capabilityStartRunnerForTest,
      _ => null,
    };
    if (runner != null) {
      return runner(
        snapshotId!,
        capability!.wireValue,
        jsonEncode(options!.toJson()),
      );
    }
    final engine = _requireEngine();
    return switch (mode) {
      'analyze' => engine.analyzeCapability(
        snapshotId!,
        capability!.wireValue,
        jsonEncode(options!.toJson()),
      ),
      'start' => engine.startCapabilityAnalysis(
        snapshotId!,
        capability!.wireValue,
        jsonEncode(options!.toJson()),
      ),
      'status' => engine.getCapabilityJobStatus(jobId!),
      _ => throw ArgumentError('unknown capability mode $mode'),
    };
  }

  bool _cancel(String jobId) {
    final runner = capabilityCancelRunnerForTest;
    if (runner != null) return runner(jobId);
    return _requireEngine().cancelCapabilityAnalysis(jobId);
  }

  CapabilityEnginePort _requireEngine() {
    if (!_ready()) {
      throw StateError(_initError() ?? 'Native engine not ready');
    }
    final engine = _engineProvider();
    if (engine == null) {
      throw StateError(_initError() ?? 'Native engine not ready');
    }
    return engine;
  }
}
