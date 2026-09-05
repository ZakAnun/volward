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
  });

  factory CoverageVerdict.fromJson(Map<String, dynamic> json) =>
      CoverageVerdict(
        path: json['path'] as String,
        verdict: json['verdict'] as String,
        confidence: json['confidence'] as String,
        reason: json['reason'] as String,
        coverageSource: json['coverage_source'] as String,
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      );

  final String path;
  final String verdict;
  final String confidence;
  final String reason;
  final String coverageSource;
  final int sizeBytes;

  Map<String, dynamic> toJson() => {
    'path': path,
    'verdict': verdict,
    'confidence': confidence,
    'reason': reason,
    'coverage_source': coverageSource,
    'size_bytes': sizeBytes,
  };
}

class CoverageVerdictStore {
  CoverageVerdictStore(this.directory);

  final Directory directory;

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
  }

  Future<List<CoverageVerdict>> readAll(String snapshotId) async {
    final file = _fileFor(snapshotId);
    if (!await file.exists()) return const [];
    final byPath = <String, CoverageVerdict>{};
    await for (final line
        in file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
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
