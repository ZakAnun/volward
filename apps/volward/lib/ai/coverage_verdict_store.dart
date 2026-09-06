import 'dart:convert';
import 'dart:io';

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

  Future<void> appendAll(
    String snapshotId,
    List<CoverageVerdict> verdicts,
  ) async {
    await directory.create(recursive: true);
    final file = _fileFor(snapshotId);
    final sink = file.openWrite(mode: FileMode.append);
    for (final verdict in verdicts) {
      sink.writeln(jsonEncode(verdict.toJson()));
    }
    await sink.flush();
    await sink.close();
    _invalidateMergedCache();
  }

  Future<void> clear(String snapshotId) async {
    final file = _fileFor(snapshotId);
    if (await file.exists()) await file.delete();
    _invalidateMergedCache();
  }

  Future<List<CoverageVerdict>> readAll(String snapshotId) async {
    final file = _fileFor(snapshotId);
    if (!await file.exists()) return const [];
    return _mergeLines(await _readLines(file));
  }

  /// Single-scan merge + stable path sort (Design §8 result paging).
  Future<List<CoverageVerdict>> readMergedSorted(String snapshotId) async {
    final fileLength = await fileByteLength(snapshotId);
    if (_mergedCacheSnapshotId == snapshotId &&
        _mergedCacheFileLength == fileLength &&
        _mergedCache != null) {
      return _mergedCache!;
    }
    final merged = await readAll(snapshotId);
    merged.sort((a, b) => a.path.compareTo(b.path));
    _mergedCacheSnapshotId = snapshotId;
    _mergedCacheFileLength = fileLength;
    _mergedCache = merged;
    return merged;
  }

  /// Reads [pageCount] pages in one file scan.
  Future<List<CoverageVerdict>> readPages(
    String snapshotId, {
    required int pageCount,
    required int pageSize,
  }) async {
    if (pageCount <= 0 || pageSize <= 0) return const [];
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
    final lines = await _readLinesFromOffset(file, byteOffset);
    return (appended: _mergeLines(lines), fileLength: length);
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

  Future<List<String>> _readLines(File file) async {
    final lines = <String>[];
    await for (final line
        in file
            .openRead()
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())) {
      if (line.trim().isNotEmpty) lines.add(line);
    }
    return lines;
  }

  Future<List<String>> _readLinesFromOffset(File file, int byteOffset) async {
    final lines = <String>[];
    await for (final line
        in file
            .openRead(byteOffset)
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())) {
      if (line.trim().isNotEmpty) lines.add(line);
    }
    return lines;
  }

  List<CoverageVerdict> _mergeLines(Iterable<String> lines) {
    final byPath = <String, CoverageVerdict>{};
    for (final line in lines) {
      try {
        final verdict = CoverageVerdict.fromJson(
          Map<String, dynamic>.from(jsonDecode(line) as Map),
        );
        byPath[verdict.path] = verdict;
      } catch (_) {}
    }
    return byPath.values.toList(growable: false);
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
