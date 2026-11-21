import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../ai/ai_provider.dart';
import '../../../ai/ai_settings_store.dart';
import '../../../ai/ai_token_estimate.dart';
import '../../../proto/ai_payload_pb_decoder.dart';
import '../ai_analysis_workspace_config.dart';
import '../views/ai_analysis_workspace_view_state.dart';
import 'ai_analysis_workspace_controller.dart';

typedef CachedAnalysisLoader =
    Future<String?> Function({
      required String cacheKey,
      required String snapshotId,
    });
typedef UnknownCandidatesSpillLoader =
    Future<List<AiCandidate>> Function(String spillPath);
typedef SizeByPathSpillLoader =
    Future<Map<String, int>> Function(String spillPath);

/// Owns candidate bootstrap, provider context and previous-result lookup.
class AiAnalysisBootstrapController extends ChangeNotifier {
  factory AiAnalysisBootstrapController({
    required AiAnalysisWorkspaceConfig page,
    required AiAnalysisWorkspaceController owner,
    CachedAnalysisLoader? previousResultLoader,
    bool Function(String snapshotId)? hasSavedResult,
    UnknownCandidatesSpillLoader? unknownCandidatesSpillLoader,
    SizeByPathSpillLoader? sizeByPathSpillLoader,
  }) {
    return AiAnalysisBootstrapController._(
      page,
      owner,
      previousResultLoader,
      hasSavedResult,
      unknownCandidatesSpillLoader,
      sizeByPathSpillLoader,
    );
  }

  AiAnalysisBootstrapController._(
    this._page,
    this._owner,
    this._previousResultLoader,
    this._hasSavedResult,
    this._unknownCandidatesSpillLoader,
    this._sizeByPathSpillLoader,
  ) : _ownerId = _owner.activeOwnerId;

  AiAnalysisWorkspaceConfig _page;
  final AiAnalysisWorkspaceController _owner;
  final CachedAnalysisLoader? _previousResultLoader;
  final bool Function(String snapshotId)? _hasSavedResult;
  final UnknownCandidatesSpillLoader? _unknownCandidatesSpillLoader;
  final SizeByPathSpillLoader? _sizeByPathSpillLoader;

  String? _ownerId;
  int? _lastGeneration;
  bool _loading = false;
  bool _disposed = false;
  AiMode _mode = AiMode.off;
  bool _hasProvider = false;
  int? _platformCredits;
  String? _candidatesRaw;
  String? _previousResultRaw;
  String? _error;
  bool _loadedFromCache = false;
  List<Map<String, dynamic>> _preClassified = const [];
  int? _preClassifiedTotalCount;
  int? _unknownTotalCount;
  String? _unknownCandidatesSpillPath;
  String? _sizeByPathSpillPath;
  List<AiCandidate> _unknown = const [];
  Map<String, AiCandidate> _unknownByPath = const {};
  Map<String, int> _sizeByPath = const {};
  Map<String, String> _deleteTargetsByPath = const {};
  Set<String> _initialSelectedPaths = const {};
  int _estimatedTokens = 0;
  int _estimatedByokBatchTokens = 0;
  bool _hasExistingResult = false;
  bool _candidatesPending = true;
  bool _truncated = false;
  int _candidatesBeforeCap = 0;
  String _resultCacheKey = '';
  String _rootPath = '';
  AiWorkspaceBootstrapState _bootstrapState = const AiWorkspaceBootstrapState();
  AiWorkspacePrecheckState _precheckState = const AiWorkspacePrecheckState();

  AiWorkspaceBootstrapState get bootstrapState => _bootstrapState;
  AiWorkspacePrecheckState get precheckState => _precheckState;
  AiMode get mode => _mode;
  bool get hasProvider => _hasProvider;
  int? get platformCredits => _platformCredits;
  String? get candidatesRaw => _candidatesRaw;
  String? get previousResultRaw => _previousResultRaw;
  String? get error => _error;
  bool get loading => _loading;
  bool get loadedFromCache => _loadedFromCache;
  int? get lastGeneration => _lastGeneration;
  bool get candidatesPending => _candidatesPending;
  bool get hasExistingResult => _hasExistingResult;
  bool get truncated => _truncated;
  int get estimatedTokens => _estimatedTokens;
  int get estimatedByokBatchTokens => _estimatedByokBatchTokens;
  int get candidatesBeforeCap => _candidatesBeforeCap;
  String get resultCacheKey => _resultCacheKey;
  String get rootPath => _rootPath;
  int? get preClassifiedTotalCount => _preClassifiedTotalCount;
  int? get unknownTotalCount => _unknownTotalCount;
  String? get unknownCandidatesSpillPath => _unknownCandidatesSpillPath;

  List<Map<String, dynamic>> get preClassified => _preClassified;
  List<AiCandidate> get unknown => _unknown;
  Map<String, AiCandidate> get unknownByPath => _unknownByPath;
  Map<String, int> get sizeByPath => _sizeByPath;
  Map<String, String> get deleteTargetsByPath => _deleteTargetsByPath;
  Set<String> get initialSelectedPaths => _initialSelectedPaths;

  Future<void> initialize() async {
    final generation = _owner.beginOperation();
    _lastGeneration = generation;
    _candidatesRaw = null;
    _previousResultRaw = null;
    _loadedFromCache = false;
    _resetCandidateData();
    _loading = true;
    _error = null;
    _publishState();

    try {
      await _loadProviderContext(generation);
      if (!_isCurrent(generation)) return;

      final raw = await _page.gateway.buildCandidates(_page.snapshotId);
      if (!_isCurrent(generation)) return;
      _candidatesRaw = raw;
      if (raw == null || raw.isEmpty) {
        _error = 'native_unavailable';
        _candidatesPending = false;
        _loading = false;
        _publishState();
        return;
      }
      if (raw.startsWith('error:')) {
        _error = raw;
        _candidatesPending = false;
        _loading = false;
        _publishState();
        return;
      }

      final parsed = raw.startsWith('spill:')
          ? await compute(
              _parseAiCandidatesFromSpillFile,
              raw.substring('spill:'.length),
            )
          : await compute(_parseAndCompactCandidatesRaw, raw);
      if (!_isCurrent(generation)) return;

      _applyParsedCandidates(
        parsed,
        hasSavedResult: _hasSavedResult?.call(_page.snapshotId) ?? false,
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _candidatesPending = false;
      _loading = false;
      _error = error.toString();
      _publishState();
    }
  }

  Future<void> retry() => initialize();

  /// Refreshes mode, provider and platform quota without rebuilding candidates.
  Future<bool> refreshPrecheckContext({int? generation}) async {
    final operation = generation ?? _owner.beginOperation();
    if (generation == null) {
      _lastGeneration = operation;
    }
    if (_candidatesPending) return false;
    try {
      final refreshed = await _loadProviderContext(operation);
      if (!refreshed || !_isCurrent(operation)) return false;
      _error = null;
      _publishState();
      return true;
    } catch (error) {
      if (!_isCurrent(operation)) return false;
      _error = error.toString();
      _publishState();
      return false;
    }
  }

  Future<void> loadPreviousResult({int? generation}) async {
    final operation = generation ?? _owner.beginOperation();
    if (generation == null) {
      _lastGeneration = operation;
    }
    final cacheKey = _resultCacheKey.isNotEmpty
        ? _resultCacheKey
        : _page.snapshotId;
    try {
      final raw = await _loadPreviousResultRaw(
        cacheKey: cacheKey,
        snapshotId: _page.snapshotId,
      );
      if (!_isCurrent(operation)) return;
      _previousResultRaw = raw;
      _loadedFromCache = raw != null && raw.isNotEmpty;
      if (_loadedFromCache) {
        _hasExistingResult = true;
        _error = null;
      }
      _publishState();
    } catch (error) {
      if (!_isCurrent(operation)) return;
      _previousResultRaw = null;
      _loadedFromCache = false;
      _error = error.toString();
      _publishState();
    }
  }

  void updateConfig(AiAnalysisWorkspaceConfig page) {
    _page = page;
  }

  void rebind(String? ownerId, {required AiAnalysisWorkspaceConfig page}) {
    _page = page;
    _ownerId = ownerId;
    _owner.rebindOwner(ownerId);
    _lastGeneration = null;
    _loading = false;
    _candidatesRaw = null;
    _previousResultRaw = null;
    _error = null;
    _loadedFromCache = false;
    _resetCandidateData();
    _publishState();
  }

  void setProviderAvailable(bool value) {
    if (_hasProvider == value) return;
    _hasProvider = value;
    _publishState();
  }

  void updatePlatformCredits(int? value) {
    if (_platformCredits == value) return;
    _platformCredits = value;
    _publishState();
  }

  void markExistingResult(bool value) {
    if (_hasExistingResult == value) return;
    _hasExistingResult = value;
    _publishState();
  }

  void updateRootPath(String value) {
    if (value.isEmpty || value == _rootPath) return;
    _rootPath = value;
    _publishState();
  }

  void addSizes(Map<String, int> values) {
    if (values.isEmpty) return;
    _sizeByPath = Map<String, int>.unmodifiable({..._sizeByPath, ...values});
    _publishState();
  }

  void setSize(String path, int sizeBytes) {
    if (path.isEmpty || sizeBytes <= 0 || _sizeByPath[path] == sizeBytes) {
      return;
    }
    _sizeByPath = Map<String, int>.unmodifiable({
      ..._sizeByPath,
      path: sizeBytes,
    });
    _publishState();
  }

  Future<void> ensureUnknownCandidatesLoaded() async {
    final generation = _lastGeneration;
    final boundOwnerId = _ownerId;
    if (generation == null) return;
    final unknownSpill = _unknownCandidatesSpillPath;
    final sizeSpill = _sizeByPathSpillPath;
    if (unknownSpill == null && sizeSpill == null) return;
    List<AiCandidate> unknown;
    Map<String, int> extraSizes;
    try {
      unknown = unknownSpill == null
          ? _unknown
          : await (_unknownCandidatesSpillLoader?.call(unknownSpill) ??
                compute(_readUnknownCandidatesFromSpill, unknownSpill));
      if (!_isCurrentFor(generation, boundOwnerId)) return;
      extraSizes = sizeSpill == null
          ? const <String, int>{}
          : await (_sizeByPathSpillLoader?.call(sizeSpill) ??
                compute(_readSizeByPathSpill, sizeSpill));
    } catch (error, stackTrace) {
      if (!_isCurrentFor(generation, boundOwnerId)) return;
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (!_isCurrentFor(generation, boundOwnerId)) return;

    if (unknownSpill != null) {
      _unknown = _freezeCandidates(unknown);
      _unknownByPath = Map<String, AiCandidate>.unmodifiable({
        for (final candidate in _unknown) candidate.path: candidate,
      });
      final deleteTargets = <String, String>{};
      final sizes = <String, int>{..._sizeByPath};
      for (final candidate in unknown) {
        final deleteTarget = candidate.deleteTarget;
        if (deleteTarget != null && deleteTarget.isNotEmpty) {
          deleteTargets[candidate.path] = deleteTarget;
        }
        sizes[candidate.path] = candidate.sizeBytes;
      }
      _deleteTargetsByPath = Map<String, String>.unmodifiable(deleteTargets);
      _sizeByPath = Map<String, int>.unmodifiable(sizes);
      _unknownCandidatesSpillPath = null;
    }
    if (sizeSpill != null) {
      _sizeByPath = Map<String, int>.unmodifiable({
        ..._sizeByPath,
        ...extraSizes,
      });
      _sizeByPathSpillPath = null;
    }
    _publishState();
  }

  void removeCandidates(
    Iterable<String> paths, {
    int? decrementPreClassifiedBy,
  }) {
    final removed = paths.toSet();
    if (removed.isEmpty) return;
    final oldPreClassifiedCount =
        _preClassifiedTotalCount ?? _preClassified.length;
    final oldUnknownCount = _unknownTotalCount ?? _unknown.length;
    final removedPreClassified = _preClassified
        .where((entry) => removed.contains(entry['path']))
        .length;
    final removedUnknown = _unknown
        .where((candidate) => removed.contains(candidate.path))
        .length;

    _preClassified = List<Map<String, dynamic>>.unmodifiable(
      _preClassified.where((entry) => !removed.contains(entry['path'])),
    );
    _unknown = List<AiCandidate>.unmodifiable(
      _unknown.where((candidate) => !removed.contains(candidate.path)),
    );
    _unknownByPath = Map<String, AiCandidate>.unmodifiable({
      for (final candidate in _unknown) candidate.path: candidate,
    });
    _sizeByPath = Map<String, int>.unmodifiable({
      for (final entry in _sizeByPath.entries)
        if (!removed.contains(entry.key)) entry.key: entry.value,
    });
    _deleteTargetsByPath = Map<String, String>.unmodifiable({
      for (final entry in _deleteTargetsByPath.entries)
        if (!removed.contains(entry.key)) entry.key: entry.value,
    });
    _initialSelectedPaths = Set<String>.unmodifiable(
      _initialSelectedPaths.difference(removed),
    );
    if (_preClassifiedTotalCount != null) {
      _preClassifiedTotalCount =
          (oldPreClassifiedCount -
                  (decrementPreClassifiedBy ?? removedPreClassified))
              .clamp(0, oldPreClassifiedCount);
    }
    if (_unknownTotalCount != null) {
      _unknownTotalCount = (oldUnknownCount - removedUnknown).clamp(
        0,
        oldUnknownCount,
      );
    }
    _publishState();
  }

  void deleteCandidateSpillFiles() {
    for (final path in [_unknownCandidatesSpillPath, _sizeByPathSpillPath]) {
      if (path == null || path.isEmpty) continue;
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }

  Future<bool> _loadProviderContext(int generation) async {
    final mode = await _page.gateway.getMode();
    if (!_isCurrent(generation)) return false;
    final provider = await _page.gateway.resolveProvider();
    if (!_isCurrent(generation)) return false;

    int? platformCredits;
    if (mode == AiMode.platform && provider != null) {
      try {
        platformCredits = (await provider.queryQuota())?.creditsRemaining;
      } catch (_) {
        platformCredits = null;
      }
    }
    if (!_isCurrent(generation)) return false;
    _mode = mode;
    _hasProvider = provider != null;
    _platformCredits = platformCredits;
    return true;
  }

  Future<String?> _loadPreviousResultRaw({
    required String cacheKey,
    required String snapshotId,
  }) {
    final loader = _previousResultLoader;
    if (loader != null) {
      return loader(cacheKey: cacheKey, snapshotId: snapshotId);
    }
    return Future<String?>.value(_page.gateway.loadResult(cacheKey));
  }

  void _resetCandidateData() {
    deleteCandidateSpillFiles();
    _preClassified = const [];
    _preClassifiedTotalCount = null;
    _unknownTotalCount = null;
    _unknownCandidatesSpillPath = null;
    _sizeByPathSpillPath = null;
    _unknown = const [];
    _unknownByPath = const {};
    _sizeByPath = const {};
    _deleteTargetsByPath = const {};
    _initialSelectedPaths = const {};
    _estimatedTokens = 0;
    _estimatedByokBatchTokens = 0;
    _hasExistingResult = false;
    _candidatesPending = true;
    _truncated = false;
    _candidatesBeforeCap = 0;
    _resultCacheKey = '';
    _rootPath = '';
  }

  void _applyParsedCandidates(
    _ParsedCandidates parsed, {
    required bool hasSavedResult,
  }) {
    _preClassified = _freezePreClassified(parsed.preClassified);
    _preClassifiedTotalCount = parsed.preClassifiedTotal;
    _unknownTotalCount = parsed.unknownTotal;
    _unknownCandidatesSpillPath = parsed.unknownCandidatesSpillPath;
    _sizeByPathSpillPath = parsed.sizeByPathSpillPath;
    _unknown = _freezeCandidates(parsed.unknown);
    _unknownByPath = Map<String, AiCandidate>.unmodifiable({
      for (final candidate in _unknown) candidate.path: candidate,
    });
    _sizeByPath = Map<String, int>.unmodifiable(parsed.sizeByPath);
    _deleteTargetsByPath = Map<String, String>.unmodifiable(
      parsed.deleteTargetsByPath,
    );
    _initialSelectedPaths = Set<String>.unmodifiable(parsed.selected);
    _estimatedTokens = parsed.estimatedTokens;
    _estimatedByokBatchTokens = parsed.estimatedByokBatchTokens;
    _hasExistingResult = parsed.hasExistingResult || hasSavedResult;
    _truncated = parsed.truncated;
    _candidatesBeforeCap = parsed.candidatesBeforeCap;
    _resultCacheKey = parsed.resultCacheKey;
    _rootPath = parsed.rootPath;
    _candidatesPending = false;
    _loading = false;
    _publishState();
  }

  void _publishState() {
    if (_disposed) return;
    _bootstrapState = AiWorkspaceBootstrapState(
      candidatesPending: _candidatesPending,
      hasProvider: _hasProvider,
      hasExistingResult: _hasExistingResult,
      loadedFromCache: _loadedFromCache,
      truncated: _truncated,
      estimatedTokens: _estimatedTokens,
      rootPath: _rootPath,
      resultCacheKey: _resultCacheKey,
      error: _error,
    );
    _precheckState = AiWorkspacePrecheckState(
      snapshotId: _page.snapshotId,
      mode: _mode,
      platformCredits: _platformCredits,
    );
    notifyListeners();
  }

  bool _isCurrent(int generation) {
    final owned = _ownerId == null || _owner.activeOwnerId == _ownerId;
    return !_disposed && owned && _owner.isCurrent(generation);
  }

  bool _isCurrentFor(int generation, String? ownerId) {
    return !_disposed &&
        ownerId == _ownerId &&
        _owner.activeOwnerId == ownerId &&
        _owner.isCurrent(generation);
  }

  @override
  void dispose() {
    _disposed = true;
    deleteCandidateSpillFiles();
    super.dispose();
  }
}

List<Map<String, dynamic>> _freezePreClassified(
  Iterable<Map<String, dynamic>> values,
) {
  return List<Map<String, dynamic>>.unmodifiable(values.map(_freezeMap));
}

Map<String, dynamic> _freezeMap(Map<dynamic, dynamic> value) {
  return Map<String, dynamic>.unmodifiable({
    for (final entry in value.entries)
      entry.key.toString(): _freezeValue(entry.value),
  });
}

Object? _freezeValue(Object? value) {
  if (value is Map) return _freezeMap(value);
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeValue));
  }
  if (value is Set) {
    return Set<Object?>.unmodifiable(value.map(_freezeValue));
  }
  return value;
}

List<AiCandidate> _freezeCandidates(Iterable<AiCandidate> values) {
  return List<AiCandidate>.unmodifiable(values.map(_freezeCandidate));
}

AiCandidate _freezeCandidate(AiCandidate candidate) {
  return AiCandidate(
    path: candidate.path,
    sizeBytes: candidate.sizeBytes,
    isDir: candidate.isDir,
    childCount: candidate.childCount,
    extension: candidate.extension,
    cleanupSource: candidate.cleanupSource,
    cleanupHint: candidate.cleanupHint,
    retentionDays: candidate.retentionDays,
    memberPaths: List<String>.unmodifiable(candidate.memberPaths),
    deleteTarget: candidate.deleteTarget,
  );
}

final class _ParsedCandidates {
  const _ParsedCandidates({
    required this.preClassified,
    required this.unknown,
    required this.sizeByPath,
    required this.deleteTargetsByPath,
    required this.estimatedTokens,
    required this.estimatedByokBatchTokens,
    required this.hasExistingResult,
    required this.truncated,
    required this.candidatesBeforeCap,
    required this.selected,
    required this.resultCacheKey,
    required this.rootPath,
    this.preClassifiedTotal,
    this.unknownTotal,
    this.unknownCandidatesSpillPath,
    this.sizeByPathSpillPath,
  });

  final List<Map<String, dynamic>> preClassified;
  final List<AiCandidate> unknown;
  final Map<String, int> sizeByPath;
  final Map<String, String> deleteTargetsByPath;
  final int estimatedTokens;
  final int estimatedByokBatchTokens;
  final bool hasExistingResult;
  final bool truncated;
  final int candidatesBeforeCap;
  final Set<String> selected;
  final String resultCacheKey;
  final String rootPath;
  final int? preClassifiedTotal;
  final int? unknownTotal;
  final String? unknownCandidatesSpillPath;
  final String? sizeByPathSpillPath;
}

const _candidateHeavyListThreshold = 256;
const _candidateSpillPreviewCap = 32;

_ParsedCandidates _parseAiCandidatesFromSpillFile(String spillPath) {
  final file = File(spillPath);
  if (spillPath.endsWith('.pb')) {
    final map = decodeAiCandidatesPb(file.readAsBytesSync());
    if (map == null) {
      throw const FormatException('invalid candidates pb');
    }
    return _compactCandidatesBootstrap(
      _bootstrapFromCandidatesMap(map),
      sourcePath: spillPath,
    );
  }
  return _compactCandidatesBootstrap(
    _parseAiCandidatesPayload(file.readAsStringSync()),
    sourcePath: spillPath,
  );
}

_ParsedCandidates _parseAndCompactCandidatesRaw(String raw) {
  return _compactCandidatesBootstrap(
    _parseAiCandidatesPayload(raw),
    sourcePath:
        '${Directory.systemTemp.path}/volward-candidates-${DateTime.now().microsecondsSinceEpoch}',
  );
}

_ParsedCandidates _compactCandidatesBootstrap(
  _ParsedCandidates full, {
  required String sourcePath,
}) {
  final preTotal = full.preClassified.length;
  var preClassified = full.preClassified;
  if (preClassified.length > _candidateSpillPreviewCap) {
    preClassified = preClassified
        .take(_candidateSpillPreviewCap)
        .toList(growable: false);
  }

  final unknownTotal = full.candidatesBeforeCap > full.unknown.length
      ? full.candidatesBeforeCap
      : full.unknown.length;
  var unknown = full.unknown;
  String? unknownSpill;
  var deleteTargetsByPath = full.deleteTargetsByPath;
  if (unknown.length > _candidateHeavyListThreshold) {
    unknownSpill = '$sourcePath.unknown.json';
    File(unknownSpill).writeAsStringSync(
      jsonEncode(unknown.map((candidate) => candidate.toJson()).toList()),
    );
    unknown = const [];
    deleteTargetsByPath = const {};
  }

  var sizeByPath = full.sizeByPath;
  String? sizeSpill;
  if (sizeByPath.length > _candidateHeavyListThreshold) {
    sizeSpill = '$sourcePath.sizes.json';
    File(sizeSpill).writeAsStringSync(jsonEncode(sizeByPath));
    sizeByPath = Map.fromEntries(
      preClassified
          .map((entry) {
            final path = entry['path'] as String? ?? '';
            return MapEntry(path, _asInt(entry['size_bytes']));
          })
          .where((entry) => entry.key.isNotEmpty),
    );
  }

  return _ParsedCandidates(
    preClassified: preClassified,
    unknown: unknown,
    sizeByPath: sizeByPath,
    deleteTargetsByPath: deleteTargetsByPath,
    estimatedTokens: full.estimatedTokens,
    estimatedByokBatchTokens: full.estimatedByokBatchTokens,
    hasExistingResult: full.hasExistingResult,
    truncated: full.truncated,
    candidatesBeforeCap: full.candidatesBeforeCap,
    selected: _selectedPathsFromPreClassifiedMaps(preClassified),
    resultCacheKey: full.resultCacheKey,
    rootPath: full.rootPath,
    preClassifiedTotal: preTotal,
    unknownTotal: unknownTotal,
    unknownCandidatesSpillPath: unknownSpill,
    sizeByPathSpillPath: sizeSpill,
  );
}

List<AiCandidate> _readUnknownCandidatesFromSpill(String spillPath) {
  final file = File(spillPath);
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((raw) => AiCandidate.fromJson(Map<String, dynamic>.from(raw)))
        .toList(growable: false);
  } finally {
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}

Map<String, int> _readSizeByPathSpill(String spillPath) {
  final file = File(spillPath);
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) return const {};
    return decoded.map((key, value) => MapEntry('$key', _asInt(value)));
  } finally {
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}

Set<String> _selectedPathsFromPreClassifiedMaps(
  Iterable<Map<String, dynamic>> preClassified,
) {
  final selected = <String>{};
  for (final entry in preClassified) {
    if (entry['confidence'] != 'high' || entry['deletable'] != true) continue;
    final path = entry['path'] as String?;
    if (path != null && path.isNotEmpty) selected.add(path);
  }
  return selected;
}

_ParsedCandidates _bootstrapFromCandidatesMap(Map<String, dynamic> map) {
  final sizeByPath = <String, int>{};
  final deleteTargetsByPath = <String, String>{};
  final preClassified = <Map<String, dynamic>>[];
  final preRaw = map['pre_classified'];
  if (preRaw is List) {
    for (final rawEntry in preRaw) {
      if (rawEntry is Map) {
        final entry = Map<String, dynamic>.from(rawEntry);
        preClassified.add(entry);
        final path = entry['path'] as String?;
        if (path != null) sizeByPath[path] = _asInt(entry['size_bytes']);
      }
    }
  }

  final unknown = <AiCandidate>[];
  final unknownRaw = map['unknown_candidates'];
  if (unknownRaw is List) {
    for (final rawCandidate in unknownRaw) {
      if (rawCandidate is Map) {
        final candidate = AiCandidate.fromJson(
          Map<String, dynamic>.from(rawCandidate),
        );
        unknown.add(candidate);
        sizeByPath[candidate.path] = candidate.sizeBytes;
        final deleteTarget = candidate.deleteTarget;
        if (deleteTarget != null && deleteTarget.isNotEmpty) {
          deleteTargetsByPath[candidate.path] = deleteTarget;
        }
      }
    }
  }

  final estimatedTotal = _asInt(map['estimated_input_tokens']);
  final estimatedBatchRaw = _asInt(map['estimated_byok_batch_input_tokens']);
  final estimatedByokBatch = estimatedBatchRaw > 0
      ? estimatedBatchRaw
      : (unknown.isNotEmpty
            ? estimateByokBatchInputTokens(unknown, kByokAnalyzeBatchSize)
            : estimatedTotal);

  return _ParsedCandidates(
    preClassified: preClassified,
    unknown: unknown,
    sizeByPath: sizeByPath,
    deleteTargetsByPath: deleteTargetsByPath,
    estimatedTokens: estimatedTotal > 0
        ? estimatedTotal
        : (unknown.isNotEmpty
              ? estimateByokTotalInputTokens(unknown, kByokAnalyzeBatchSize)
              : 0),
    estimatedByokBatchTokens: estimatedByokBatch,
    hasExistingResult: map['has_existing_result'] == true,
    truncated: map['truncated'] == true,
    candidatesBeforeCap: _asInt(map['candidates_total_before_cap']),
    selected: _selectedPathsFromPreClassifiedMaps(preClassified),
    resultCacheKey: map['result_cache_key']?.toString() ?? '',
    rootPath: map['root_path']?.toString() ?? '',
  );
}

_ParsedCandidates _parseAiCandidatesPayload(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('ai candidates payload is not an object');
  }
  return _bootstrapFromCandidatesMap(Map<String, dynamic>.from(decoded));
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}
