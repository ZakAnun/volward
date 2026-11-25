import 'dart:convert';
import 'dart:io';

import 'coverage_engine.dart';
import 'coverage_models.dart';
import 'coverage_verdict_store.dart';

class CoverageCounts {
  const CoverageCounts({
    required this.total,
    required this.resolved,
    required this.pending,
    required this.failed,
  });

  final int total;
  final int resolved;
  final int pending;
  final int failed;

  bool get complete => total == resolved && pending == 0;

  Map<String, dynamic> toJson() => {
    'total': total,
    'resolved': resolved,
    'pending': pending,
    'failed': failed,
  };
}

class CoverageClassification {
  const CoverageClassification({
    required this.path,
    required this.sizeBytes,
    required this.verdict,
    required this.confidence,
    required this.reason,
    required this.coverageSource,
  });

  static CoverageClassification? fromScope(
    CoverageScopeRow row,
    CoverageVerdict? verdict,
  ) {
    final scopeVerdict = switch (row.resolution) {
      CoverageScopeResolution.localSafe => 'safe_to_remove',
      CoverageScopeResolution.localKeep => 'keep',
      CoverageScopeResolution.tailCandidate ||
      CoverageScopeResolution.treeCandidate => null,
    };
    final base = scopeVerdict == null
        ? null
        : CoverageClassification(
            path: row.path,
            sizeBytes: row.sizeBytes,
            verdict: scopeVerdict,
            confidence: 'high',
            reason: 'Local coverage rule.',
            coverageSource: 'local:scope',
          );
    if (verdict == null) return base;
    final direct = _fromVerdict(verdict);
    if (base == null) return direct;
    return _compareVerdict(direct, base) >= 0 ? direct : base;
  }

  factory CoverageClassification.fromJson(Map<String, dynamic> json) =>
      CoverageClassification(
        path: json['path'] as String,
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        verdict: json['verdict'] as String,
        confidence: json['confidence'] as String,
        reason: json['reason'] as String? ?? '',
        coverageSource: json['coverage_source'] as String? ?? '',
      );

  factory CoverageClassification._fromVerdict(CoverageVerdict verdict) =>
      CoverageClassification(
        path: verdict.path,
        sizeBytes: verdict.sizeBytes,
        verdict: verdict.verdict,
        confidence: verdict.confidence,
        reason: verdict.reason,
        coverageSource: verdict.coverageSource,
      );

  final String path;
  final int sizeBytes;
  final String verdict;
  final String confidence;
  final String reason;
  final String coverageSource;

  bool get deletionSafe => verdict == 'safe_to_remove' && confidence == 'high';

  Map<String, dynamic> toJson() => {
    'path': path,
    'size_bytes': sizeBytes,
    'verdict': verdict,
    'confidence': confidence,
    'reason': reason,
    'coverage_source': coverageSource,
  };
}

class CoverageReconciliation {
  const CoverageReconciliation({
    required this.snapshotId,
    required this.planVersion,
    required this.fingerprint,
    required this.counts,
    required this.directory,
    required this.pendingFile,
    required this.resolvedFile,
    required this.failedFile,
  });

  final String snapshotId;
  final int planVersion;
  final String fingerprint;
  final CoverageCounts counts;
  final Directory directory;
  final File pendingFile;
  final File resolvedFile;
  final File failedFile;

  Stream<CoverageScopeRow> pendingRows() => _readJsonLines(
    pendingFile,
  ).map((json) => CoverageScopeRow.fromJson(json));

  Stream<CoverageClassification> resolvedRows() => _readJsonLines(
    resolvedFile,
  ).map((json) => CoverageClassification.fromJson(json));

  Stream<CoverageScopeRow> failedRows() =>
      _readJsonLines(failedFile).map((json) => CoverageScopeRow.fromJson(json));
}

class CoverageReconciler {
  CoverageReconciler({
    required this.engine,
    required this.directory,
    this.bucketCount = 64,
    this.scopePageSize = 1000,
  }) : assert(bucketCount > 0);

  final CoverageEngine engine;
  final Directory directory;
  final int bucketCount;
  final int scopePageSize;

  static const _manifestName = 'manifest.json';

  Future<CoverageReconciliation?> loadCurrent(String snapshotId) async {
    final root = Directory(
      '${directory.path}/reconciliation_${_safeName(snapshotId)}',
    );
    final pointer = File('${root.path}/current.json');
    if (!await pointer.exists()) return null;
    final buildName = (await pointer.readAsString()).trim();
    if (!buildName.startsWith('build_')) return null;
    final build = Directory('${root.path}/$buildName');
    final manifestFile = File('${build.path}/$_manifestName');
    if (!await manifestFile.exists()) return null;
    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    final counts = manifest['counts'] as Map?;
    if (counts == null) return null;
    return CoverageReconciliation(
      snapshotId: manifest['snapshot_id'] as String,
      planVersion: (manifest['plan_version'] as num).toInt(),
      fingerprint: manifest['fingerprint'] as String,
      counts: CoverageCounts(
        total: (counts['total'] as num).toInt(),
        resolved: (counts['resolved'] as num).toInt(),
        pending: (counts['pending'] as num).toInt(),
        failed: (counts['failed'] as num).toInt(),
      ),
      directory: build,
      pendingFile: File('${build.path}/pending.jsonl'),
      resolvedFile: File('${build.path}/resolved.jsonl'),
      failedFile: File('${build.path}/failed.jsonl'),
    );
  }

  Future<CoverageReconciliation> reconcile({
    required String snapshotId,
    required int planVersion,
    required String expectedFingerprint,
  }) async {
    if (expectedFingerprint.isEmpty) {
      throw StateError('scope fingerprint is required');
    }
    await directory.create(recursive: true);
    final root = Directory(
      '${directory.path}/reconciliation_${_safeName(snapshotId)}',
    );
    await root.create(recursive: true);
    final build = Directory(
      '${root.path}/build_${DateTime.now().microsecondsSinceEpoch}',
    );
    await build.create(recursive: true);

    final scopeBuckets = List<File>.generate(
      bucketCount,
      (bucket) => File('${build.path}/scope_$bucket.jsonl'),
    );
    final verdictBuckets = List<File>.generate(
      bucketCount,
      (bucket) => File('${build.path}/verdict_$bucket.jsonl'),
    );
    final scopeSinks = [for (final file in scopeBuckets) file.openWrite()];
    final verdictSinks = [for (final file in verdictBuckets) file.openWrite()];

    var fingerprint = expectedFingerprint;
    var cursor = 0;
    try {
      while (true) {
        final page = await engine.nextScopePage(
          snapshotId,
          planVersion,
          cursor,
          pageSize: scopePageSize,
        );
        if (page.snapshotId != snapshotId || page.planVersion != planVersion) {
          throw StateError('scope page binding mismatch');
        }
        if (fingerprint != page.fingerprint) {
          throw StateError(
            'scope page fingerprint does not match the coverage plan',
          );
        }
        for (final row in page.rows) {
          scopeSinks[_bucketForPath(row.path)].write(
            '${jsonEncode(_scopeJson(row))}\n',
          );
        }
        final next = page.nextCursor;
        if (next == null) break;
        if (next <= cursor) throw StateError('scope cursor did not advance');
        cursor = next;
      }

      final verdictFile = File(
        '${directory.path}/ai_coverage_verdicts_$snapshotId.jsonl',
      );
      if (await verdictFile.exists()) {
        await for (final line
            in verdictFile
                .openRead()
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          if (line.trim().isEmpty) continue;
          try {
            final verdict = CoverageVerdict.fromJson(
              Map<String, dynamic>.from(jsonDecode(line) as Map),
            );
            verdictSinks[_bucketForPath(verdict.path)].write(
              '${jsonEncode(verdict.toJson())}\n',
            );
          } catch (_) {
            // A truncated final row is retried after the next complete append.
          }
        }
      }
    } finally {
      await Future.wait([
        ...scopeSinks.map((sink) => sink.close()),
        ...verdictSinks.map((sink) => sink.close()),
      ]);
    }

    final pending = File('${build.path}/pending.jsonl');
    final resolved = File('${build.path}/resolved.jsonl');
    final failed = File('${build.path}/failed.jsonl');
    final pendingSink = pending.openWrite();
    final resolvedSink = resolved.openWrite();
    final failedSink = failed.openWrite();
    var total = 0;
    var resolvedCount = 0;
    var pendingCount = 0;
    var failedCount = 0;
    try {
      for (var bucket = 0; bucket < bucketCount; bucket++) {
        final scopeByPath = <String, CoverageScopeRow>{};
        await for (final line
            in scopeBuckets[bucket]
                .openRead()
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          if (line.isEmpty) continue;
          final row = CoverageScopeRow.fromJson(
            Map<String, dynamic>.from(jsonDecode(line) as Map),
          );
          scopeByPath[row.path] = row;
        }
        final verdictByPath = <String, CoverageVerdict>{};
        final incompletePaths = <String>{};
        await for (final line
            in verdictBuckets[bucket]
                .openRead()
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          if (line.isEmpty) continue;
          final verdict = CoverageVerdict.fromJson(
            Map<String, dynamic>.from(jsonDecode(line) as Map),
          );
          if (verdict.coverageSource == 'file:incomplete') {
            incompletePaths.add(verdict.path);
            continue;
          }
          if (!_isDirectFileVerdict(verdict)) continue;
          final current = verdictByPath[verdict.path];
          if (current == null ||
              _compareVerdict(_fromVerdict(verdict), _fromVerdict(current)) >
                  0) {
            verdictByPath[verdict.path] = verdict;
          }
        }

        for (final row in scopeByPath.values) {
          total++;
          final classification = CoverageClassification.fromScope(
            row,
            verdictByPath[row.path],
          );
          final hasScopeResolution =
              row.resolution == CoverageScopeResolution.localSafe ||
              row.resolution == CoverageScopeResolution.localKeep;
          if (classification != null || hasScopeResolution) {
            resolvedCount++;
            resolvedSink.write('${jsonEncode(classification!.toJson())}\n');
          } else {
            pendingCount++;
            if (incompletePaths.contains(row.path)) {
              failedCount++;
              failedSink.write('${jsonEncode(_scopeJson(row))}\n');
            }
            pendingSink.write('${jsonEncode(_scopeJson(row))}\n');
          }
        }
      }
    } finally {
      await pendingSink.close();
      await resolvedSink.close();
      await failedSink.close();
    }

    final counts = CoverageCounts(
      total: total,
      resolved: resolvedCount,
      pending: pendingCount,
      failed: failedCount,
    );
    final manifest = {
      'snapshot_id': snapshotId,
      'plan_version': planVersion,
      'fingerprint': fingerprint,
      'counts': counts.toJson(),
      'pending_file': 'pending.jsonl',
      'resolved_file': 'resolved.jsonl',
      'failed_file': 'failed.jsonl',
    };
    await File(
      '${build.path}/$_manifestName',
    ).writeAsString(jsonEncode(manifest), flush: true);
    await _publish(root, build);
    return CoverageReconciliation(
      snapshotId: snapshotId,
      planVersion: planVersion,
      fingerprint: fingerprint,
      counts: counts,
      directory: build,
      pendingFile: pending,
      resolvedFile: resolved,
      failedFile: failed,
    );
  }

  Future<void> _publish(Directory root, Directory build) async {
    final pointer = File('${root.path}/current.json.tmp');
    final buildName = build.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    await pointer.writeAsString(buildName, flush: true);
    final target = File('${root.path}/current.json');
    try {
      await pointer.rename(target.path);
    } on FileSystemException {
      // Windows cannot replace an existing file with rename.
      if (await target.exists()) await target.delete();
      await pointer.rename(target.path);
    }
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory) {
        final entityName = entity.uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .last;
        if (entityName == buildName) continue;
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // A later successful reconciliation will retry cleanup.
        }
      }
    }
  }

  int _bucketForPath(String path) {
    var hash = 0x811c9dc5;
    for (final codeUnit in path.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash % bucketCount;
  }
}

Map<String, dynamic> _scopeJson(CoverageScopeRow row) => {
  'path': row.path,
  'size_bytes': row.sizeBytes,
  'resolution': switch (row.resolution) {
    CoverageScopeResolution.localSafe => 'local_safe',
    CoverageScopeResolution.localKeep => 'local_keep',
    CoverageScopeResolution.tailCandidate => 'tail_candidate',
    CoverageScopeResolution.treeCandidate => 'tree_candidate',
  },
};

bool _isDirectFileVerdict(CoverageVerdict verdict) {
  final source = verdict.coverageSource;
  return source == 'file' ||
      source.startsWith('local:') ||
      source.startsWith('dir_propagate:');
}

CoverageClassification _fromVerdict(CoverageVerdict verdict) =>
    CoverageClassification._fromVerdict(verdict);

int _compareVerdict(CoverageClassification left, CoverageClassification right) {
  final category = _verdictRank(
    left.verdict,
  ).compareTo(_verdictRank(right.verdict));
  if (category != 0) return category;
  final source = _sourceRank(
    left.coverageSource,
  ).compareTo(_sourceRank(right.coverageSource));
  if (source != 0) return source;
  return _confidenceRank(
    left.confidence,
  ).compareTo(_confidenceRank(right.confidence));
}

int _verdictRank(String verdict) => switch (verdict) {
  'keep' => 3,
  'review_needed' => 2,
  'safe_to_remove' => 1,
  _ => 0,
};

int _sourceRank(String source) => switch (source) {
  final value when value.startsWith('local:') => 3,
  'file' => 2,
  final value when value.startsWith('dir_propagate:') => 1,
  _ => 0,
};

int _confidenceRank(String confidence) => switch (confidence) {
  'high' => 3,
  'medium' => 2,
  'low' => 1,
  _ => 0,
};

Stream<Map<String, dynamic>> _readJsonLines(File file) async* {
  if (!await file.exists()) return;
  await for (final line
      in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    if (line.isEmpty) continue;
    yield Map<String, dynamic>.from(jsonDecode(line) as Map);
  }
}

String _safeName(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
