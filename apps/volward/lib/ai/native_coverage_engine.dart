import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../bridge/native_bridge.dart';
import 'ai_debug_log.dart';
import 'coverage_engine.dart';
import 'coverage_models.dart';
import 'coverage_native_responses.dart';
import 'coverage_verdict_store.dart';

/// FFI-backed [CoverageEngine] that delegates to Rust coverage plan APIs.
class NativeCoverageEngine implements CoverageEngine {
  NativeCoverageEngine({
    required this.bridge,
    required this.engine,
    this.pageSize = 200,
    this.offloadHeavyCalls = true,
  });

  static final Map<String, Future<String>> _inFlightPlanJson = {};

  final VolwardNativeBridge bridge;
  final Pointer<Void> engine;
  final int pageSize;

  /// Run per-file native scans (and their JSON decode) on a short-lived isolate.
  /// On large indexes each call takes long enough to freeze the UI isolate; set
  /// `false` when this engine already lives on a background isolate.
  final bool offloadHeavyCalls;

  String _requireJson(String? raw, String operation) {
    if (raw == null || raw.isEmpty) {
      throw CoverageEngineException('error:native $operation unavailable');
    }
    return raw;
  }

  Future<String> _fetchCoveragePlanJson(
    String snapshotId, {
    required bool tree,
  }) {
    final key = '$snapshotId|tree=$tree';
    final existing = _inFlightPlanJson[key];
    if (existing != null) return existing;
    final load = _fetchCoveragePlanJsonImpl(snapshotId, tree: tree);
    _inFlightPlanJson[key] = load;
    return load.whenComplete(() => _inFlightPlanJson.remove(key));
  }

  Future<String> _fetchCoveragePlanJsonImpl(
    String snapshotId, {
    required bool tree,
  }) async {
    if (!bridge.hasAsyncAiCoveragePlanApi) {
      debugPrint(
        'Volward: sync coverage plan build (missing async FFI — rebuild Rust dylib)',
      );
      return _requireJson(
        tree
            ? bridge.buildAiTreeCoveragePlanJson(engine, snapshotId)
            : bridge.buildAiCoveragePlanJson(engine, snapshotId),
        'build coverage plan',
      );
    }

    final startedAt = DateTime.now();
    // Full cache build walks every unclassified file on large scans (70GB+).
    const timeout = Duration(minutes: 120);

    Future<void> waitForPlanBuild() async {
      var lastHeartbeat = startedAt;
      while (bridge.isAiCoveragePlanBuilding(engine)) {
        final now = DateTime.now();
        if (now.difference(startedAt) > timeout) {
          throw CoverageEngineException('error:coverage plan build timed out');
        }
        if (now.difference(lastHeartbeat) >= const Duration(seconds: 5)) {
          volwardAiDebugLog(
            'coverage plan build still running '
            '${now.difference(startedAt).inSeconds}s snapshot=$snapshotId tree=$tree',
          );
          lastHeartbeat = now;
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }

    String? startResult;
    while (startResult == null) {
      if (DateTime.now().difference(startedAt) > timeout) {
        throw CoverageEngineException('error:coverage plan build timed out');
      }
      final started = bridge.startBuildAiCoveragePlanAsync(
        engine,
        snapshotId,
        tree: tree,
      );
      if (started == null) {
        return _requireJson(
          tree
              ? bridge.buildAiTreeCoveragePlanJson(engine, snapshotId)
              : bridge.buildAiCoveragePlanJson(engine, snapshotId),
          'build coverage plan',
        );
      }
      if (started.startsWith('error:')) {
        throw CoverageEngineException(started);
      }
      if (started.startsWith('busy:')) {
        await waitForPlanBuild();
        startResult = 'joined';
        break;
      }
      if (started.startsWith('ok')) {
        startResult = started;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    if (startResult != 'joined') {
      await waitForPlanBuild();
    }
    return _requireJson(
      bridge.getAiCoveragePlanJson(engine),
      'get coverage plan',
    );
  }

  /// Reads a plan already materialized by a prior async build (no rebuild).
  ///
  /// Still runs on the UI isolate; large JSON parse can jank — prefer memory cache
  /// via [CoverageResumePlanLoader] when available.
  CoveragePlanSummary? tryReadMaterializedPlanSummary(
    String snapshotId, {
    required bool tree,
  }) {
    if (!bridge.hasAsyncAiCoveragePlanApi) return null;
    if (bridge.isAiCoveragePlanBuilding(engine)) return null;
    return parseMaterializedCoveragePlanJson(
      raw: bridge.getAiCoveragePlanJson(engine),
      snapshotId: snapshotId,
      tree: tree,
    );
  }

  @override
  Future<CoveragePlanSummary> buildPlan(String snapshotId) async {
    final raw = await _fetchCoveragePlanJson(snapshotId, tree: false);
    final summary = parseCoveragePlanSummary(raw);
    if (summary.snapshotId != snapshotId) {
      throw CoverageEngineException('error:coverage plan snapshot mismatch');
    }
    return summary;
  }

  @override
  Future<CoveragePage> nextPage(
    String snapshotId,
    int planVersion,
    int cursor,
  ) async {
    final raw = _requireJson(
      bridge.nextAiCoveragePageJson(
        engine,
        snapshotId,
        planVersion,
        cursor,
        pageSize: pageSize,
      ),
      'next coverage page',
    );
    final page = parseCoveragePage(raw);
    if (page.snapshotId != snapshotId || page.planVersion != planVersion) {
      throw CoverageEngineException('error:coverage page mismatch');
    }
    return page;
  }

  @override
  Future<CoveragePlanSummary> buildTreePlan(String snapshotId) async {
    final raw = await _fetchCoveragePlanJson(snapshotId, tree: true);
    final summary = parseCoveragePlanSummary(raw);
    if (summary.snapshotId != snapshotId) {
      throw CoverageEngineException(
        'error:tree coverage plan snapshot mismatch',
      );
    }
    return summary;
  }

  @override
  Future<CoverageTreePage> nextTreePage(
    String snapshotId,
    int planVersion,
    int cursor, {
    int? pageSize,
  }) async {
    final raw = _requireJson(
      bridge.nextAiTreeCoveragePageJson(
        engine,
        snapshotId,
        planVersion,
        cursor,
        pageSize: pageSize ?? this.pageSize,
      ),
      'next tree coverage page',
    );
    final page = parseCoverageTreePage(raw);
    if (page.snapshotId != snapshotId || page.planVersion != planVersion) {
      throw CoverageEngineException('error:tree coverage page mismatch');
    }
    return page;
  }

  @override
  Future<CoverageTailPage> nextTailPage(
    String snapshotId,
    int planVersion,
    int cursor, {
    int? pageSize,
  }) async {
    final raw = _requireJson(
      bridge.nextAiTailCoveragePageJson(
        engine,
        snapshotId,
        planVersion,
        cursor,
        pageSize: pageSize ?? this.pageSize,
      ),
      'next tail coverage page',
    );
    final page = parseCoverageTailPage(raw);
    if (page.snapshotId != snapshotId || page.planVersion != planVersion) {
      throw CoverageEngineException('error:tail coverage page mismatch');
    }
    return page;
  }

  @override
  Future<List<CoverageTreeNode>> expandTreeNode(
    String snapshotId,
    String dirPath,
  ) async {
    final raw = _requireJson(
      bridge.expandAiTreeNodeJson(engine, snapshotId, dirPath),
      'expand tree node',
    );
    return parseCoverageTreeExpandNodes(raw);
  }

  @override
  Future<List<CoverageVerdict>> applyDirVerdict(
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
  ) async {
    if (!offloadHeavyCalls) {
      return _applyDirVerdict(
        bridge,
        engine,
        snapshotId,
        dirPath,
        verdict,
        confidence,
        roleSnakeCase,
      );
    }
    return Isolate.run(
      _applyDirVerdictTask(
        engine.address,
        snapshotId,
        dirPath,
        verdict,
        confidence,
        roleSnakeCase,
      ),
      debugName: 'volward-apply-dir-verdict',
    );
  }

  @override
  Future<int?> applyDirVerdictToFile(
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
    String outPath,
  ) async {
    if (!bridge.hasApplyDirVerdictToFileApi) return null;
    if (!offloadHeavyCalls) {
      return _applyDirVerdictToFile(
        bridge,
        engine,
        snapshotId,
        dirPath,
        verdict,
        confidence,
        roleSnakeCase,
        outPath,
      );
    }
    return Isolate.run(
      _applyDirVerdictToFileTask(
        engine.address,
        snapshotId,
        dirPath,
        verdict,
        confidence,
        roleSnakeCase,
        outPath,
      ),
      debugName: 'volward-apply-dir-verdict-file',
    );
  }

  static int Function() _applyDirVerdictToFileTask(
    int engineAddress,
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
    String outPath,
  ) {
    return () => _applyDirVerdictToFile(
      VolwardNativeBridge.open(),
      Pointer<Void>.fromAddress(engineAddress),
      snapshotId,
      dirPath,
      verdict,
      confidence,
      roleSnakeCase,
      outPath,
    );
  }

  static int _applyDirVerdictToFile(
    VolwardNativeBridge bridge,
    Pointer<Void> engine,
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
    String outPath,
  ) {
    final raw = bridge.applyAiDirVerdictToFile(
      engine,
      snapshotId,
      dirPath,
      verdict,
      confidence,
      roleSnakeCase,
      outPath,
    );
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) {
      throw CoverageEngineException(
        raw == null || raw.isEmpty
            ? 'error:native apply dir verdict to file unavailable'
            : raw,
      );
    }
    final decoded = jsonDecode(raw);
    final count = decoded is Map ? decoded['count'] : null;
    if (count is! num) {
      throw CoverageEngineException('error:apply dir verdict to file: $raw');
    }
    return count.toInt();
  }

  static List<CoverageVerdict> Function() _applyDirVerdictTask(
    int engineAddress,
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
  ) {
    return () => _applyDirVerdict(
      VolwardNativeBridge.open(),
      Pointer<Void>.fromAddress(engineAddress),
      snapshotId,
      dirPath,
      verdict,
      confidence,
      roleSnakeCase,
    );
  }

  static List<CoverageVerdict> _applyDirVerdict(
    VolwardNativeBridge bridge,
    Pointer<Void> engine,
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
  ) {
    final raw = bridge.applyAiDirVerdictJson(
      engine,
      snapshotId,
      dirPath,
      verdict,
      confidence,
      roleSnakeCase,
    );
    if (raw == null || raw.isEmpty) {
      throw CoverageEngineException(
        'error:native apply dir verdict unavailable',
      );
    }
    return parseApplyDirVerdictResponse(raw);
  }

  @override
  Future<LocalCoverageVerdictPage> fetchLocalVerdictsPage(
    String snapshotId, {
    int cursor = 0,
    int limit = 5000,
  }) async {
    if (!offloadHeavyCalls) {
      return _fetchLocalVerdictsPage(bridge, engine, snapshotId, cursor, limit);
    }
    return Isolate.run(
      _localVerdictsPageTask(engine.address, snapshotId, cursor, limit),
      debugName: 'volward-local-verdicts',
    );
  }

  /// Writes every native local verdict page into the verdict store at
  /// [storeDirectory] without materializing them on the calling isolate.
  /// Returns how many verdicts were written.
  Future<int> backfillLocalVerdictsToStore(
    String snapshotId,
    String storeDirectory, {
    int pageLimit = 5000,
  }) {
    if (!offloadHeavyCalls) {
      return _backfillLocalVerdicts(
        bridge,
        engine,
        snapshotId,
        storeDirectory,
        pageLimit,
      );
    }
    return Isolate.run(
      _backfillTask(engine.address, snapshotId, storeDirectory, pageLimit),
      debugName: 'volward-local-verdict-backfill',
    );
  }

  static Future<int> Function() _backfillTask(
    int engineAddress,
    String snapshotId,
    String storeDirectory,
    int pageLimit,
  ) {
    return () => _backfillLocalVerdicts(
      VolwardNativeBridge.open(),
      Pointer<Void>.fromAddress(engineAddress),
      snapshotId,
      storeDirectory,
      pageLimit,
    );
  }

  static Future<int> _backfillLocalVerdicts(
    VolwardNativeBridge bridge,
    Pointer<Void> engine,
    String snapshotId,
    String storeDirectory,
    int pageLimit,
  ) async {
    final store = CoverageVerdictStore(Directory(storeDirectory));
    var written = 0;
    int? cursor = 0;
    while (cursor != null) {
      final page = _fetchLocalVerdictsPage(
        bridge,
        engine,
        snapshotId,
        cursor,
        pageLimit,
      );
      if (page.verdicts.isEmpty) break;
      await store.appendAll(snapshotId, page.verdicts);
      written += page.verdicts.length;
      final next = page.nextCursor;
      cursor = next != null && next > cursor ? next : null;
    }
    return written;
  }

  /// Built in a static scope so the isolate closure captures only sendable values.
  static LocalCoverageVerdictPage Function() _localVerdictsPageTask(
    int engineAddress,
    String snapshotId,
    int cursor,
    int limit,
  ) {
    return () => _fetchLocalVerdictsPage(
      VolwardNativeBridge.open(),
      Pointer<Void>.fromAddress(engineAddress),
      snapshotId,
      cursor,
      limit,
    );
  }

  static LocalCoverageVerdictPage _fetchLocalVerdictsPage(
    VolwardNativeBridge bridge,
    Pointer<Void> engine,
    String snapshotId,
    int cursor,
    int limit,
  ) {
    final raw = bridge.listLocalCoverageVerdictsJson(
      engine,
      snapshotId,
      cursor,
      limit: limit,
    );
    if (raw == null || raw.isEmpty) {
      throw CoverageEngineException(
        'error:native list local coverage verdicts unavailable',
      );
    }
    return parseLocalCoverageVerdictPage(raw);
  }

  @override
  Future<List<Map<String, dynamic>>> resolveGroupMembers(
    String snapshotId,
    String groupPath,
  ) async {
    final raw = _requireJson(
      bridge.resolveAiCoverageGroupJson(engine, snapshotId, groupPath),
      'resolve coverage group',
    );
    return parseCoverageGroupMembers(raw);
  }
}
