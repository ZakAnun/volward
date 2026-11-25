import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../../ai/ai_debug_log.dart';
import '../../bridge/bindings/ai.dart';
import 'ai_bridge_symbols.dart';
import 'runtime/native_library.dart';
import 'runtime/native_string.dart';

abstract interface class AiBridge {
  bool get hasApplyDirVerdictToFileApi;
  bool get hasAsyncAiCandidatesApi;
  bool get hasAsyncAiCoveragePlanApi;
  bool get hasAiSessionApi;
  bool get hasAiContractApi;
  bool get hasAiTreeContractApi;
  bool get hasAiCoverageApi;
  bool get hasAiTreeCoverageApi;

  String? buildAiCandidatesJson(Pointer<Void> engine, String snapshotId);
  String? startBuildAiCandidatesAsync(Pointer<Void> engine, String snapshotId);
  bool isAiCandidatesBuilding(Pointer<Void> engine);
  String? getAiCandidatesJson(Pointer<Void> engine);
  String? takeAiCandidatesSpillPath(Pointer<Void> engine);
  String? startBuildAiCoveragePlanAsync(
    Pointer<Void> engine,
    String snapshotId, {
    required bool tree,
  });
  bool isAiCoveragePlanBuilding(Pointer<Void> engine);
  String? getAiCoveragePlanJson(Pointer<Void> engine);
  String? buildAiCoveragePlanJson(Pointer<Void> engine, String snapshotId);
  String? listLocalCoverageVerdictsJson(
    Pointer<Void> engine,
    String snapshotId,
    int cursor, {
    int limit = 5000,
  });
  String? nextAiCoveragePageJson(
    Pointer<Void> engine,
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 40,
  });
  String? resolveAiCoverageGroupJson(
    Pointer<Void> engine,
    String snapshotId,
    String groupPath,
  );
  String? buildAiTreeCoveragePlanJson(Pointer<Void> engine, String snapshotId);
  String? nextAiTreeCoveragePageJson(
    Pointer<Void> engine,
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 80,
  });
  String? nextAiTailCoveragePageJson(
    Pointer<Void> engine,
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 40,
  });
  String? nextAiScopeCoveragePageJson(
    Pointer<Void> engine,
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 1000,
  });
  String? expandAiTreeNodeJson(
    Pointer<Void> engine,
    String snapshotId,
    String dirPath,
  );
  String? applyAiDirVerdictJson(
    Pointer<Void> engine,
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
  );
  String? applyAiDirVerdictToFile(
    Pointer<Void> engine,
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
    String outPath,
  );
  bool saveAiResultJson(
    Pointer<Void> engine,
    String snapshotId,
    String resultJson,
  );
  String? loadAiResultJson(Pointer<Void> engine, String snapshotId);
  String? aiUpstreamEndpoint();
  int? aiBatchSize();
  String? aiBuildRequestJson(String candidatesJson);
  String? aiBuildConclusionSynthesisJson(String userJson);
  String? aiParseResponseJson(String upstreamBody, String batchJson);
  int? aiTreeBatchSize();
  String? aiBuildTreeRequestJson(String nodesJson);
  String? aiParseTreeResponseJson(String upstreamBody, String batchJson);
}

class AiNativeBridge implements AiBridge {
  AiNativeBridge(NativeLibraryHandle library, this._codec)
    : _symbols = AiNativeSymbols(library) {
    _logMissingSymbols();
  }

  final NativeStringCodec _codec;
  final AiNativeSymbols _symbols;

  @override
  bool get hasApplyDirVerdictToFileApi =>
      _symbols.applyDirVerdictToFile != null;

  @override
  bool get hasAsyncAiCandidatesApi =>
      _symbols.startBuildCandidatesAsync != null &&
      _symbols.isCandidatesBuilding != null &&
      _symbols.getCandidatesJson != null;

  @override
  bool get hasAsyncAiCoveragePlanApi =>
      _symbols.startBuildCoveragePlanAsync != null &&
      _symbols.isCoveragePlanBuilding != null &&
      _symbols.getCoveragePlanJson != null;

  @override
  bool get hasAiSessionApi =>
      _symbols.buildCandidatesJson != null && _symbols.saveResultJson != null;

  @override
  bool get hasAiContractApi =>
      _symbols.upstreamEndpoint != null &&
      _symbols.batchSize != null &&
      _symbols.buildRequestJson != null &&
      _symbols.parseResponseJson != null;

  @override
  bool get hasAiTreeContractApi =>
      hasAiContractApi &&
      _symbols.treeBatchSize != null &&
      _symbols.buildTreeRequestJson != null &&
      _symbols.parseTreeResponseJson != null;

  @override
  bool get hasAiCoverageApi =>
      _symbols.buildCoveragePlanJson != null &&
      _symbols.nextCoveragePageJson != null &&
      _symbols.resolveCoverageGroupJson != null;

  @override
  bool get hasAiTreeCoverageApi =>
      _symbols.buildTreeCoveragePlanJson != null &&
      _symbols.nextTreeCoveragePageJson != null &&
      _symbols.nextTailCoveragePageJson != null &&
      _symbols.nextScopeCoveragePageJson != null &&
      _symbols.expandTreeNodeJson != null &&
      _symbols.applyDirVerdictJson != null &&
      _symbols.listLocalCoverageVerdictsJson != null;

  @override
  String? buildAiCandidatesJson(Pointer<Void> engine, String snapshotId) =>
      _callWithSnapshot(engine, snapshotId, _symbols.buildCandidatesJson);

  @override
  String? startBuildAiCandidatesAsync(
    Pointer<Void> engine,
    String snapshotId,
  ) =>
      _callWithSnapshot(engine, snapshotId, _symbols.startBuildCandidatesAsync);

  @override
  bool isAiCandidatesBuilding(Pointer<Void> engine) =>
      _symbols.isCandidatesBuilding?.call(engine) ?? false;

  @override
  String? getAiCandidatesJson(Pointer<Void> engine) =>
      _callEngineString(engine, _symbols.getCandidatesJson);

  @override
  String? takeAiCandidatesSpillPath(Pointer<Void> engine) =>
      _callEngineString(engine, _symbols.takeCandidatesSpillPath);

  @override
  String? startBuildAiCoveragePlanAsync(
    Pointer<Void> engine,
    String snapshotId, {
    required bool tree,
  }) {
    final fn = _symbols.startBuildCoveragePlanAsync;
    if (fn == null) return null;
    final snapshotPtr = snapshotId.toNativeUtf8();
    try {
      return _codec.decodeAndFreeNullable(fn(engine, snapshotPtr, tree));
    } finally {
      calloc.free(snapshotPtr);
    }
  }

  @override
  bool isAiCoveragePlanBuilding(Pointer<Void> engine) =>
      _symbols.isCoveragePlanBuilding?.call(engine) ?? false;

  @override
  String? getAiCoveragePlanJson(Pointer<Void> engine) =>
      _callEngineString(engine, _symbols.getCoveragePlanJson);

  @override
  String? buildAiCoveragePlanJson(Pointer<Void> engine, String snapshotId) =>
      _callWithSnapshot(engine, snapshotId, _symbols.buildCoveragePlanJson);

  @override
  String? listLocalCoverageVerdictsJson(
    Pointer<Void> engine,
    String snapshotId,
    int cursor, {
    int limit = 5000,
  }) {
    final fn = _symbols.listLocalCoverageVerdictsJson;
    if (fn == null) return null;
    final snapshotPtr = snapshotId.toNativeUtf8();
    try {
      return _codec.decodeAndFreeNullable(
        fn(engine, snapshotPtr, cursor, limit),
      );
    } finally {
      calloc.free(snapshotPtr);
    }
  }

  @override
  String? nextAiCoveragePageJson(
    Pointer<Void> engine,
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 40,
  }) => _callPage(
    engine,
    snapshotId,
    planVersion,
    cursor,
    pageSize,
    _symbols.nextCoveragePageJson,
  );

  @override
  String? resolveAiCoverageGroupJson(
    Pointer<Void> engine,
    String snapshotId,
    String groupPath,
  ) => _callTwoStrings(
    engine,
    snapshotId,
    groupPath,
    _symbols.resolveCoverageGroupJson,
  );

  @override
  String? buildAiTreeCoveragePlanJson(
    Pointer<Void> engine,
    String snapshotId,
  ) =>
      _callWithSnapshot(engine, snapshotId, _symbols.buildTreeCoveragePlanJson);

  @override
  String? nextAiTreeCoveragePageJson(
    Pointer<Void> engine,
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 80,
  }) => _callPage(
    engine,
    snapshotId,
    planVersion,
    cursor,
    pageSize,
    _symbols.nextTreeCoveragePageJson,
  );

  @override
  String? nextAiTailCoveragePageJson(
    Pointer<Void> engine,
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 40,
  }) => _callPage(
    engine,
    snapshotId,
    planVersion,
    cursor,
    pageSize,
    _symbols.nextTailCoveragePageJson,
  );

  @override
  String? nextAiScopeCoveragePageJson(
    Pointer<Void> engine,
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 1000,
  }) => _callPage(
    engine,
    snapshotId,
    planVersion,
    cursor,
    pageSize,
    _symbols.nextScopeCoveragePageJson,
  );

  @override
  String? expandAiTreeNodeJson(
    Pointer<Void> engine,
    String snapshotId,
    String dirPath,
  ) =>
      _callTwoStrings(engine, snapshotId, dirPath, _symbols.expandTreeNodeJson);

  @override
  String? applyAiDirVerdictJson(
    Pointer<Void> engine,
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
  ) => _callApplyVerdict(
    engine,
    snapshotId,
    dirPath,
    verdict,
    confidence,
    roleSnakeCase,
    null,
    _symbols.applyDirVerdictJson,
  );

  @override
  String? applyAiDirVerdictToFile(
    Pointer<Void> engine,
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
    String outPath,
  ) => _callApplyVerdict(
    engine,
    snapshotId,
    dirPath,
    verdict,
    confidence,
    roleSnakeCase,
    outPath,
    _symbols.applyDirVerdictToFile,
  );

  @override
  bool saveAiResultJson(
    Pointer<Void> engine,
    String snapshotId,
    String resultJson,
  ) {
    final fn = _symbols.saveResultJson;
    if (fn == null) return false;
    final snapshotPtr = snapshotId.toNativeUtf8();
    final jsonPtr = resultJson.toNativeUtf8();
    try {
      return fn(engine, snapshotPtr, jsonPtr);
    } finally {
      calloc.free(snapshotPtr);
      calloc.free(jsonPtr);
    }
  }

  @override
  String? loadAiResultJson(Pointer<Void> engine, String snapshotId) =>
      _callWithSnapshot(engine, snapshotId, _symbols.loadResultJson);

  @override
  String? aiUpstreamEndpoint() {
    final fn = _symbols.upstreamEndpoint;
    if (fn == null) return null;
    return _codec.decodeAndFreeNullable(fn());
  }

  @override
  int? aiBatchSize() => _symbols.batchSize?.call();

  @override
  String? aiBuildRequestJson(String candidatesJson) =>
      _callInputString(candidatesJson, _symbols.buildRequestJson);

  @override
  String? aiBuildConclusionSynthesisJson(String userJson) =>
      _callInputString(userJson, _symbols.buildConclusionSynthesisJson);

  @override
  String? aiParseResponseJson(String upstreamBody, String batchJson) =>
      _callInputStrings(upstreamBody, batchJson, _symbols.parseResponseJson);

  @override
  int? aiTreeBatchSize() => _symbols.treeBatchSize?.call();

  @override
  String? aiBuildTreeRequestJson(String nodesJson) =>
      _callInputString(nodesJson, _symbols.buildTreeRequestJson);

  @override
  String? aiParseTreeResponseJson(String upstreamBody, String batchJson) =>
      _callInputStrings(
        upstreamBody,
        batchJson,
        _symbols.parseTreeResponseJson,
      );

  String? _callWithSnapshot(
    Pointer<Void> engine,
    String snapshotId,
    Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)? fn,
  ) {
    if (fn == null) return null;
    final snapshotPtr = snapshotId.toNativeUtf8();
    try {
      return _codec.decodeAndFreeNullable(fn(engine, snapshotPtr));
    } finally {
      calloc.free(snapshotPtr);
    }
  }

  String? _callEngineString(
    Pointer<Void> engine,
    Pointer<Utf8> Function(Pointer<Void>)? fn,
  ) => fn == null ? null : _codec.decodeAndFreeNullable(fn(engine));

  String? _callTwoStrings(
    Pointer<Void> engine,
    String first,
    String second,
    Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)? fn,
  ) {
    if (fn == null) return null;
    final firstPtr = first.toNativeUtf8();
    final secondPtr = second.toNativeUtf8();
    try {
      return _codec.decodeAndFreeNullable(fn(engine, firstPtr, secondPtr));
    } finally {
      calloc.free(firstPtr);
      calloc.free(secondPtr);
    }
  }

  String? _callPage(
    Pointer<Void> engine,
    String snapshotId,
    int planVersion,
    int cursor,
    int pageSize,
    Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, int, int, int)? fn,
  ) {
    if (fn == null) return null;
    final snapshotPtr = snapshotId.toNativeUtf8();
    try {
      return _codec.decodeAndFreeNullable(
        fn(engine, snapshotPtr, planVersion, cursor, pageSize),
      );
    } finally {
      calloc.free(snapshotPtr);
    }
  }

  String? _callApplyVerdict(
    Pointer<Void> engine,
    String snapshotId,
    String dirPath,
    String verdict,
    String confidence,
    String roleSnakeCase,
    String? outPath,
    Function? fn,
  ) {
    if (fn == null) return null;
    final snapshotPtr = snapshotId.toNativeUtf8();
    final dirPtr = dirPath.toNativeUtf8();
    final verdictPtr = verdict.toNativeUtf8();
    final confidencePtr = confidence.toNativeUtf8();
    final rolePtr = roleSnakeCase.toNativeUtf8();
    final outPtr = outPath?.toNativeUtf8();
    try {
      final Pointer<Utf8> out = outPath == null
          ? (fn as VolwardAiApplyDirVerdictJson)(
              engine,
              snapshotPtr,
              dirPtr,
              verdictPtr,
              confidencePtr,
              rolePtr,
            )
          : (fn as VolwardAiApplyDirVerdictToFile)(
              engine,
              snapshotPtr,
              dirPtr,
              verdictPtr,
              confidencePtr,
              rolePtr,
              outPtr!,
            );
      return _codec.decodeAndFreeNullable(out);
    } finally {
      calloc.free(snapshotPtr);
      calloc.free(dirPtr);
      calloc.free(verdictPtr);
      calloc.free(confidencePtr);
      calloc.free(rolePtr);
      if (outPtr != null) calloc.free(outPtr);
    }
  }

  String? _callInputString(
    String input,
    Pointer<Utf8> Function(Pointer<Utf8>)? fn,
  ) {
    if (fn == null) return null;
    final inputPtr = input.toNativeUtf8();
    try {
      return _codec.decodeAndFreeNullable(fn(inputPtr));
    } finally {
      calloc.free(inputPtr);
    }
  }

  String? _callInputStrings(
    String first,
    String second,
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)? fn,
  ) {
    if (fn == null) return null;
    final firstPtr = first.toNativeUtf8();
    final secondPtr = second.toNativeUtf8();
    try {
      return _codec.decodeAndFreeNullable(fn(firstPtr, secondPtr));
    } finally {
      calloc.free(firstPtr);
      calloc.free(secondPtr);
    }
  }

  void _logMissingSymbols() {
    if (!kDebugMode) return;
    final missing = <String>[
      if (_symbols.buildCoveragePlanJson == null)
        'volward_ai_build_coverage_plan_json',
      if (_symbols.nextCoveragePageJson == null)
        'volward_ai_next_coverage_page_json',
      if (_symbols.resolveCoverageGroupJson == null)
        'volward_ai_resolve_coverage_group_json',
      if (_symbols.buildTreeCoveragePlanJson == null)
        'volward_ai_build_tree_coverage_plan_json',
      if (_symbols.nextTreeCoveragePageJson == null)
        'volward_ai_next_tree_coverage_page_json',
      if (_symbols.nextTailCoveragePageJson == null)
        'volward_ai_next_tail_coverage_page_json',
      if (_symbols.nextScopeCoveragePageJson == null)
        'volward_ai_next_scope_coverage_page_json',
      if (_symbols.expandTreeNodeJson == null)
        'volward_ai_expand_tree_node_json',
      if (_symbols.applyDirVerdictJson == null)
        'volward_ai_apply_dir_verdict_json',
      if (_symbols.listLocalCoverageVerdictsJson == null)
        'volward_ai_list_local_coverage_verdicts_json',
    ];
    if (missing.isNotEmpty) {
      volwardAiDebugLog(
        'native FFI coverage=$hasAiCoverageApi '
        'tree=$hasAiTreeCoverageApi session=$hasAiSessionApi '
        'asyncCandidates=$hasAsyncAiCandidatesApi '
        'missing=${missing.join(", ")}',
      );
    }
  }
}
