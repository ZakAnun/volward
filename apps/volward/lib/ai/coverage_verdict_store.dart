import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Above this many bytes to decode, parsing runs on a short-lived isolate.
/// Full coverage writes millions of local verdict lines (hundreds of MB), and
/// decoding them on the UI isolate freezes frames for seconds.
const _isolateDecodeThresholdBytes = 1024 * 1024;

Future<List<CoverageVerdict>> _decodeVerdictFile(
  String path, {
  int byteOffset = 0,
  required int end,
  bool sortByPath = false,
}) async {
  final byPath = <String, CoverageVerdict>{};
  await for (final line
      in File(path)
          .openRead(byteOffset, end)
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
      end: byteOffset + bytesToRead,
      sortByPath: sortByPath,
    );
  }
  return Isolate.run(
    () => _decodeVerdictFile(
      path,
      byteOffset: byteOffset,
      end: byteOffset + bytesToRead,
      sortByPath: sortByPath,
    ),
    debugName: 'volward-verdict-decode',
  );
}

Future<int> _buildVerdictPageIndex(
  ({String sourcePath, int end, String pathsPath, String metaPath}) input,
) async {
  final entries = <String, ({int offset, int length})>{};
  final pending = <int>[];
  var position = 0;
  var lineStart = 0;
  await for (final chunk in File(input.sourcePath).openRead(0, input.end)) {
    for (var index = 0; index < chunk.length; index++) {
      final byte = chunk[index];
      if (byte != 10) {
        pending.add(byte);
        continue;
      }
      if (pending.isNotEmpty) {
        try {
          final verdict = CoverageVerdict.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(utf8.decode(pending, allowMalformed: true)) as Map,
            ),
          );
          entries[verdict.path] = (
            offset: lineStart,
            length: position + index + 1 - lineStart,
          );
        } catch (_) {
          // Ignore malformed complete rows; incomplete tails never reach here.
        }
        pending.clear();
      }
      lineStart = position + index + 1;
    }
    position += chunk.length;
  }

  final paths = entries.keys.toList()..sort();
  final pathSink = File(input.pathsPath).openWrite();
  final metaSink = File(input.metaPath).openWrite();
  var pathOffset = 0;
  try {
    for (final path in paths) {
      final pathBytes = utf8.encode(path);
      final entry = entries[path]!;
      final meta = ByteData(24)
        ..setUint64(0, pathOffset, Endian.little)
        ..setUint32(8, pathBytes.length, Endian.little)
        ..setUint64(12, entry.offset, Endian.little)
        ..setUint32(20, entry.length, Endian.little);
      pathSink.add(pathBytes);
      metaSink.add(meta.buffer.asUint8List());
      pathOffset += pathBytes.length;
    }
    await Future.wait([pathSink.flush(), metaSink.flush()]);
  } finally {
    await pathSink.close();
    await metaSink.close();
  }
  return paths.length;
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
  String? _pageIndexSnapshotId;
  int _pageIndexFileLength = -1;
  int _pageIndexCount = 0;

  void _invalidateMergedCache() {
    _mergedCache = null;
    _mergedCacheSnapshotId = null;
    _mergedCacheFileLength = -1;
    _pageIndexSnapshotId = null;
    _pageIndexFileLength = -1;
    _pageIndexCount = 0;
  }

  File _fileFor(String snapshotId) =>
      File('${directory.path}/ai_coverage_verdicts_$snapshotId.jsonl');

  /// Full in-memory reads are only safe for modest JSONL files.
  static const inlineReadBudgetBytes = 2 * 1024 * 1024;

  Future<bool> fitsInlineReadBudget(String snapshotId) async {
    final length = await fileByteLength(snapshotId);
    return length > 0 && length <= inlineReadBudgetBytes;
  }

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
    final result = prior.then((_) => _withFileLock(key, snapshotId, write));
    _globalAppendTailByFile[key] = result.then<void>(
      (_) {},
      onError: (Object _) {},
    );
    return result;
  }

  Future<T> _withFileLock<T>(
    String filePath,
    String snapshotId,
    Future<T> Function() write,
  ) async {
    await directory.create(recursive: true);
    final lock = File('$filePath.lock');
    while (true) {
      try {
        await lock.create(exclusive: true);
        break;
      } on FileSystemException {
        if (await lock.exists()) {
          final age = DateTime.now().difference(await lock.lastModified());
          if (age > const Duration(minutes: 10)) {
            try {
              await lock.delete();
            } catch (_) {}
            continue;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    try {
      final file = _fileFor(snapshotId);
      if (await file.exists()) {
        final complete = await _completeLineEnd(snapshotId);
        final actual = await file.length();
        if (actual > complete) {
          final writer = await file.open(mode: FileMode.append);
          try {
            await writer.truncate(complete);
            await writer.flush();
          } finally {
            await writer.close();
          }
        }
      }
      return await write();
    } finally {
      try {
        await lock.delete();
      } catch (_) {}
    }
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
      await _ensurePageIndex(snapshotId, fileLength);
      return _readIndexedPage(snapshotId, pageCount * pageSize);
    }
    final merged = await readMergedSorted(snapshotId);
    final end = (pageCount * pageSize).clamp(0, merged.length);
    return merged.sublist(0, end);
  }

  /// Returns rows and the exact complete-line boundary used to decode them.
  Future<({List<CoverageVerdict> rows, int end})> readSnapshot(
    String snapshotId, {
    required int pageCount,
    required int pageSize,
    required bool preferAll,
  }) async {
    final end = await _completeLineEnd(snapshotId);
    if (end == 0) return (rows: <CoverageVerdict>[], end: 0);
    final path = _fileFor(snapshotId).path;
    final all = preferAll && end <= inlineReadBudgetBytes;
    late final List<CoverageVerdict> rows;
    if (all) {
      rows = await _decodeVerdictFileOffUi(path, bytesToRead: end);
    } else {
      await _ensurePageIndex(snapshotId, end);
      rows = await _readIndexedPage(snapshotId, pageCount * pageSize);
    }
    return (rows: rows, end: end);
  }

  Future<void> _ensurePageIndex(String snapshotId, int fileLength) async {
    if (_pageIndexSnapshotId == snapshotId &&
        _pageIndexFileLength == fileLength) {
      return;
    }
    final source = _fileFor(snapshotId);
    final paths = File('${source.path}.page_paths');
    final meta = File('${source.path}.page_meta');
    _pageIndexCount = await Isolate.run(
      () => _buildVerdictPageIndex((
        sourcePath: source.path,
        end: fileLength,
        pathsPath: paths.path,
        metaPath: meta.path,
      )),
      debugName: 'volward-verdict-page-index',
    );
    _pageIndexSnapshotId = snapshotId;
    _pageIndexFileLength = fileLength;
  }

  Future<List<CoverageVerdict>> _readIndexedPage(
    String snapshotId,
    int limit,
  ) async {
    if (limit <= 0 || _pageIndexCount == 0) return const [];
    final source = _fileFor(snapshotId);
    final paths = File('${source.path}.page_paths');
    final meta = File('${source.path}.page_meta');
    final metaFile = await meta.open();
    final sourceFile = await source.open();
    final pathsFile = await paths.open();
    const recordBytes = 24;
    final take = limit.clamp(0, _pageIndexCount).toInt();
    try {
      final records = await metaFile.read(take * recordBytes);
      final data = ByteData.sublistView(records);
      final rows = <CoverageVerdict>[];
      for (var index = 0; index < take; index++) {
        final base = index * recordBytes;
        final pathOffset = data.getUint64(base, Endian.little);
        final pathLength = data.getUint32(base + 8, Endian.little);
        final sourceOffset = data.getUint64(base + 12, Endian.little);
        final sourceLength = data.getUint32(base + 20, Endian.little);
        await pathsFile.setPosition(pathOffset);
        final path = utf8.decode(await pathsFile.read(pathLength));
        await sourceFile.setPosition(sourceOffset);
        final line = utf8.decode(
          await sourceFile.read(sourceLength),
          allowMalformed: true,
        );
        try {
          final verdict = CoverageVerdict.fromJson(
            Map<String, dynamic>.from(jsonDecode(line) as Map),
          );
          if (verdict.path == path) rows.add(verdict);
        } catch (_) {
          // The file-length key invalidates stale indexes before reuse.
        }
      }
      return List.unmodifiable(rows);
    } finally {
      await pathsFile.close();
      await sourceFile.close();
      await metaFile.close();
    }
  }

  Future<int> _completeLineEnd(String snapshotId) async {
    final file = _fileFor(snapshotId);
    if (!await file.exists()) return 0;
    final reader = await file.open();
    try {
      var end = await reader.length();
      while (end > 0) {
        final start = (end - 4096).clamp(0, end);
        await reader.setPosition(start);
        final buffer = await reader.read(end - start);
        final newline = buffer.lastIndexOf(10);
        if (newline >= 0) return start + newline + 1;
        end = start;
      }
      return 0;
    } finally {
      await reader.close();
    }
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
    final length = await _completeLineEnd(snapshotId);
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
