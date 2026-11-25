import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_engine.dart';
import 'package:volward/ai/coverage_models.dart';
import 'package:volward/ai/coverage_reconciliation.dart';
import 'package:volward/ai/coverage_verdict_store.dart';

void main() {
  test(
    'reconciliation counts scope paths once and preserves pending work',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'volward-reconcile-',
      );
      addTearDown(() => directory.delete(recursive: true));
      const snapshotId = 'scope-snapshot';
      final engine = FakeCoverageEngine(
        summary: _summary(snapshotId),
        pages: const [],
        scopePagesByCursor: {
          0: const CoverageScopePage(
            snapshotId: snapshotId,
            planVersion: 3,
            fingerprint: 'scope-fingerprint',
            nextCursor: null,
            rows: [
              CoverageScopeRow(
                path: '/root/local-safe.cache',
                sizeBytes: 10,
                resolution: CoverageScopeResolution.localSafe,
              ),
              CoverageScopeRow(
                path: '/root/local-keep.db',
                sizeBytes: 20,
                resolution: CoverageScopeResolution.localKeep,
              ),
              CoverageScopeRow(
                path: '/root/pending.bin',
                sizeBytes: 30,
                resolution: CoverageScopeResolution.treeCandidate,
              ),
              CoverageScopeRow(
                path: '/root/ai-keep.bin',
                sizeBytes: 40,
                resolution: CoverageScopeResolution.treeCandidate,
              ),
              CoverageScopeRow(
                path: '/root/group-target',
                sizeBytes: 50,
                resolution: CoverageScopeResolution.treeCandidate,
              ),
            ],
          ),
        },
      );
      await CoverageVerdictStore(directory).appendAll(snapshotId, const [
        CoverageVerdict(
          path: '/root/local-safe.cache',
          verdict: 'keep',
          confidence: 'high',
          reason: 'protection wins',
          coverageSource: 'file',
          sizeBytes: 10,
        ),
        CoverageVerdict(
          path: '/root/pending.bin',
          verdict: 'review_needed',
          confidence: 'low',
          reason: 'AI omitted this path',
          coverageSource: 'file:incomplete',
          sizeBytes: 30,
        ),
        CoverageVerdict(
          path: '/root/ai-keep.bin',
          verdict: 'keep',
          confidence: 'high',
          reason: 'database',
          coverageSource: 'file',
          sizeBytes: 40,
        ),
        CoverageVerdict(
          path: '/root/directory-only',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'directory verdict',
          coverageSource: 'dir:/root/directory-only',
          sizeBytes: 50,
        ),
        CoverageVerdict(
          path: '/root/group-target',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'aggregate only',
          coverageSource: 'group:/root/group-target',
          sizeBytes: 50,
          groupMemberCount: 5,
        ),
      ]);

      final reconciliation =
          await CoverageReconciler(
            engine: engine,
            directory: directory,
            bucketCount: 2,
          ).reconcile(
            snapshotId: snapshotId,
            planVersion: 3,
            expectedFingerprint: 'scope-fingerprint',
          );

      expect(reconciliation.counts.total, 5);
      expect(reconciliation.counts.resolved, 3);
      expect(reconciliation.counts.pending, 2);
      expect(reconciliation.counts.failed, 1);
      expect(
        await reconciliation.pendingRows().map((row) => row.path).toList(),
        unorderedEquals(['/root/pending.bin', '/root/group-target']),
      );
      final effective = await reconciliation.resolvedRows().toList();
      final safeConflict = effective.singleWhere(
        (row) => row.path == '/root/local-safe.cache',
      );
      expect(safeConflict.verdict, 'keep');
      expect(safeConflict.deletionSafe, isFalse);
    },
  );

  test('reconciliation streams bounded scope pages', () async {
    final directory = await Directory.systemTemp.createTemp(
      'volward-reconcile-pages-',
    );
    addTearDown(() => directory.delete(recursive: true));
    const snapshotId = 'paged-scope';
    final reconciliation =
        await CoverageReconciler(
          engine: _GeneratedScopeEngine(total: 20000),
          directory: directory,
          bucketCount: 16,
          scopePageSize: 1000,
        ).reconcile(
          snapshotId: snapshotId,
          planVersion: 3,
          expectedFingerprint: 'generated-scope',
        );

    expect(reconciliation.counts.total, 20000);
    expect(reconciliation.counts.resolved, 0);
    expect(reconciliation.counts.pending, 20000);
    final pendingSample = await reconciliation
        .pendingRows()
        .take(2)
        .map((row) => row.path)
        .toList();
    expect(pendingSample, hasLength(2));
    expect(pendingSample.toSet(), hasLength(2));
  });

  test('reconciliation rejects a scope fingerprint mismatch', () async {
    final directory = await Directory.systemTemp.createTemp(
      'volward-reconcile-mismatch-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final reconciler = CoverageReconciler(
      engine: _GeneratedScopeEngine(total: 1),
      directory: directory,
      bucketCount: 1,
    );

    await expectLater(
      reconciler.reconcile(
        snapshotId: 'paged-scope',
        planVersion: 3,
        expectedFingerprint: 'different-plan',
      ),
      throwsStateError,
    );
  });

  test('reconciliation publishes one current build and reopens it', () async {
    final directory = await Directory.systemTemp.createTemp(
      'volward-reconcile-publish-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final reconciler = CoverageReconciler(
      engine: _GeneratedScopeEngine(total: 2),
      directory: directory,
      bucketCount: 2,
    );
    final root = Directory('${directory.path}/reconciliation_paged-scope');
    await root.create(recursive: true);
    await File('${root.path}/current.json').writeAsString('stale-build');
    await reconciler.reconcile(
      snapshotId: 'paged-scope',
      planVersion: 3,
      expectedFingerprint: 'generated-scope',
    );
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await reconciler.reconcile(
      snapshotId: 'paged-scope',
      planVersion: 3,
      expectedFingerprint: 'generated-scope',
    );

    final builds = await root
        .list()
        .where((entry) => entry is Directory)
        .cast<Directory>()
        .toList();
    expect(builds, hasLength(1));
    final current = await reconciler.loadCurrent('paged-scope');
    expect(current, isNotNull);
    expect(current!.counts.total, 2);
  });
}

CoveragePlanSummary _summary(String snapshotId) => CoveragePlanSummary(
  snapshotId: snapshotId,
  planVersion: 3,
  rootPath: '/root',
  totalUnclassified: 4,
  preClassifiedCount: 2,
  groupRows: 0,
  fileRows: 4,
  estimatedPages: 1,
);

class _GeneratedScopeEngine extends FakeCoverageEngine {
  _GeneratedScopeEngine({required this.total})
    : super(summary: _summary('paged-scope'), pages: const []);

  final int total;

  @override
  Future<CoverageScopePage> nextScopePage(
    String snapshotId,
    int planVersion,
    int cursor, {
    int? pageSize,
  }) async {
    final limit = pageSize ?? 1000;
    final end = (cursor + limit).clamp(0, total).toInt();
    return CoverageScopePage(
      snapshotId: snapshotId,
      planVersion: planVersion,
      fingerprint: 'generated-scope',
      nextCursor: end < total ? end : null,
      rows: [
        for (var index = cursor; index < end; index++)
          CoverageScopeRow(
            path: '/root/file_$index.bin',
            sizeBytes: index + 1,
            resolution: CoverageScopeResolution.treeCandidate,
          ),
      ],
    );
  }
}
