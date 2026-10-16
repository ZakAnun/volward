import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Above this many bytes to decode, parsing runs on a short-lived isolate.
/// Full coverage writes millions of local verdict lines (hundreds of MB), and
/// decoding them on the UI isolate freezes frames for seconds.
const _isolateDecodeThresholdBytes = 1024 * 1024;

Future<List<CoverageVerdict>> _decodeVerdictFile(
  String path, {
  int byteOffset = 0,
  bool sortByPath = false,
}) async {
  final byPath = <String, CoverageVerdict>{};
  await for (final line
      in File(path)
          .openRead(byteOffset)
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    try {
      final verdict = CoverageVerdict.fromJson(
        Map<String, dynamic>.from(jsonDecode(line) as Map),
      );
      byPath[verdict.path] = verdict;
    } catch (_) {}
  }
  final merged = byPath.values.toList();
  if (sortByPath) merged.sort((a, b) => a.path.compareTo(b.path));
  return merged;
}

Future<List<CoverageVerdict>> Function() _sortedPrefixTask(
  String path,
  int limit,
) {
  return () async {
    final merged = await _decodeVerdictFile(path, sortByPath: true);
    return merged.length <= limit ? merged : merged.sublist(0, limit);
  };
}

Future<List<CoverageVerdict>> _decodeVerdictFileOffUi(
  String path, {
  required int bytesToRead,
  int byteOffset = 0,
  bool sortByPath = false,
}) {
  if (bytesToRead <= _isolateDecodeThresholdBytes) {
    return _decodeVerdictFile(
      path,
      byteOffset: byteOffset,
      sortByPath: sortByPath,
    );
  }
  return Isolate.run(
    () => _decodeVerdictFile(
      path,
      byteOffset: byteOffset,
      sortByPath: sortByPath,
    ),
    debugName: 'volward-verdict-decode',
  );
}

class CoverageVerdict {
  const CoverageVerdict({
    required this.path,
    required this.verdict,
    required this.confidence,
    required this.reason,
    required this.coverageSource,
    required this.sizeBytes,
    this.groupMemberCount,
  });

  factory CoverageVerdict.fromJson(Map<String, dynamic> json) =>
      CoverageVerdict(
        path: json['path'] as String,
        verdict: json['verdict'] as String,
        confidence: json['confidence'] as String,
        reason: json['reason'] as String,
        coverageSource: json['coverage_source'] as String,
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        groupMemberCount: (json['group_member_count'] as num?)?.toInt(),
      );

  final String path;
  final String verdict;
  final String confidence;
  final String reason;
  final String coverageSource;
  final int sizeBytes;
  final int? groupMemberCount;

  Map<String, dynamic> toJson() => {
    'path': path,
    'verdict': verdict,
    'confidence': confidence,
    'reason': reason,
    'coverage_source': coverageSource,
    'size_bytes': sizeBytes,
    if (groupMemberCount != null) 'group_member_count': groupMemberCount,
  };
}

class CoverageVerdictStore {
  CoverageVerdictStore(this.directory);

  final Directory directory;

  List<CoverageVerdict>? _mergedCache;
  String? _mergedCacheSnapshotId;
  int _mergedCacheFileLength = -1;

  void _invalidateMergedCache() {
    _mergedCache = null;
    _mergedCacheSnapshotId = null;
    _mergedCacheFileLength = -1;
  }

  File _fileFor(String snapshotId) =>
      File('${directory.path}/ai_coverage_verdicts_$snapshotId.jsonl');

  /// One append chain per verdict file path (worker, UI, and isolates may each
  /// construct their own [CoverageVerdictStore] for the same cache directory).
  static final Map<String, Future<void>> _globalAppendTailByFile = {};

  Future<T> _serializedAppend<T>(
    String snapshotId,
    Future<T> Function() write,
  ) {
    final key = _fileFor(snapshotId).path;
    final prior = _globalAppendTailByFile.putIfAbsent(
      key,
      () => Future<void>.value(),
    );
    final result = prior.then((_) => write());
    _globalAppendTailByFile[key] = result.then<void>(
      (_) {},
      onError: (Object _) {},
    );
    return result;
  }

  Future<void> appendAll(String snapshotId, List<CoverageVerdict> verdicts) {
    return _serializedAppend(snapshotId, () async {
      await directory.create(recursive: true);
      final file = _fileFor(snapshotId);
      final sink = file.openWrite(mode: FileMode.append);
      for (final verdict in verdicts) {
        sink.writeln(jsonEncode(verdict.toJson()));
      }
      await sink.flush();
      await sink.close();
      _invalidateMergedCache();
    });
  }

  /// Lets an external writer (e.g. native code) append JSONL rows to the
  /// snapshot's verdict file while holding the append lock.
  Future<T> appendWith<T>(
    String snapshotId,
    Future<T> Function(String filePath) write,
  ) {
    return _serializedAppend(snapshotId, () async {
      await directory.create(recursive: true);
      try {
        return await write(_fileFor(snapshotId).path);
      } finally {
        _invalidateMergedCache();
      }
    });
  }

  Future<void> clear(String snapshotId) {
    return _serializedAppend(snapshotId, () async {
      final file = _fileFor(snapshotId);
      if (await file.exists()) await file.delete();
      _invalidateMergedCache();
    });
  }

  Future<List<CoverageVerdict>> readAll(String snapshotId) async {
    final file = _fileFor(snapshotId);
    if (!await file.exists()) return const [];
    return _decodeVerdictFileOffUi(file.path, bytesToRead: await file.length());
  }

  /// Single-scan merge + stable path sort (Design §8 result paging).
  Future<List<CoverageVerdict>> readMergedSorted(String snapshotId) async {
    final fileLength = await fileByteLength(snapshotId);
    if (_mergedCacheSnapshotId == snapshotId &&
        _mergedCacheFileLength == fileLength &&
        _mergedCache != null) {
      return _mergedCache!;
    }
    final file = _fileFor(snapshotId);
    final merged = fileLength == 0
        ? <CoverageVerdict>[]
        : await _decodeVerdictFileOffUi(
            file.path,
            bytesToRead: fileLength,
            sortByPath: true,
          );
    _mergedCacheSnapshotId = snapshotId;
    _mergedCacheFileLength = fileLength;
    _mergedCache = merged;
    return merged;
  }

  /// Reads [pageCount] pages in one file scan.
  ///
  /// For large files only the requested prefix crosses back to this isolate,
  /// so the full merged list never lands on the UI heap.
  Future<List<CoverageVerdict>> readPages(
    String snapshotId, {
    required int pageCount,
    required int pageSize,
  }) async {
    if (pageCount <= 0 || pageSize <= 0) return const [];
    final fileLength = await fileByteLength(snapshotId);
    final cached =
        _mergedCacheSnapshotId == snapshotId &&
        _mergedCacheFileLength == fileLength &&
        _mergedCache != null;
    if (!cached && fileLength > _isolateDecodeThresholdBytes) {
      return Isolate.run(
        _sortedPrefixTask(_fileFor(snapshotId).path, pageCount * pageSize),
        debugName: 'volward-verdict-pages',
      );
    }
    final merged = await readMergedSorted(snapshotId);
    final end = (pageCount * pageSize).clamp(0, merged.length);
    return merged.sublist(0, end);
  }

  /// Reads verdict lines appended after [byteOffset] and returns merged rows
  /// plus the new file length (Design §8 incremental refresh).
  Future<({List<CoverageVerdict> appended, int fileLength})> readAppendedSince(
    String snapshotId,
    int byteOffset,
  ) async {
    final file = _fileFor(snapshotId);
    if (!await file.exists()) {
      return (appended: const <CoverageVerdict>[], fileLength: 0);
    }
    final length = await file.length();
    if (byteOffset >= length) {
      return (appended: const <CoverageVerdict>[], fileLength: length);
    }
    final appended = await _decodeVerdictFileOffUi(
      file.path,
      byteOffset: byteOffset,
      bytesToRead: length - byteOffset,
    );
    return (appended: appended, fileLength: length);
  }

  Future<int> fileByteLength(String snapshotId) async {
    final file = _fileFor(snapshotId);
    if (!await file.exists()) return 0;
    return file.length();
  }

  /// Returns a stable page of distinct verdicts sorted by path.
  Future<List<CoverageVerdict>> readPage(
    String snapshotId, {
    required int pageIndex,
    required int pageSize,
  }) async {
    if (pageSize <= 0 || pageIndex < 0) return const [];
    final merged = await readMergedSorted(snapshotId);
    final start = pageIndex * pageSize;
    if (start >= merged.length) return const [];
    final end = (start + pageSize).clamp(0, merged.length);
    return merged.sublist(start, end);
  }

  Future<int> countAnalyzedFiles(
    String snapshotId,
    Set<String> groupPaths,
  ) async {
    final verdicts = await readAll(snapshotId);
    return verdicts
        .where((v) => v.coverageSource == 'file' || groupPaths.contains(v.path))
        .length;
  }
}
