import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_coverage_job_controller.dart';
import 'package:volward/ai/cancel_token.dart';
import 'package:volward/ai/coverage_engine.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_models.dart';
import 'package:volward/ai/coverage_verdict_store.dart';

void main() {
  late Directory dir;
  late CoverageVerdictStore verdictStore;
  late CoverageJobStateStore stateStore;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('coverage-controller-');
    verdictStore = CoverageVerdictStore(dir);
    stateStore = CoverageJobStateStore(dir);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('controller analyzes every row and completes', () async {
    final rows = List.generate(
      80,
      (i) => CoverageRow(
        rowIndex: i,
        kind: CoverageRowKind.file,
        path: '/f$i',
        sizeBytes: 1,
      ),
    );
    final engine = FakeCoverageEngine(
      summary: const CoveragePlanSummary(
        snapshotId: 's1',
        planVersion: 1,
        rootPath: '/',
        totalUnclassified: 80,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 80,
        estimatedPages: 2,
      ),
      pages: [
        CoveragePage(
          snapshotId: 's1',
          planVersion: 1,
          nextCursor: 40,
          rows: rows.sublist(0, 40),
        ),
        CoveragePage(
          snapshotId: 's1',
          planVersion: 1,
          nextCursor: null,
          rows: rows.sublist(40),
        ),
      ],
    );
    var analyzed = 0;
    final controller = CoverageJobController(
      engine: engine,
      verdictStore: verdictStore,
      stateStore: stateStore,
      analyzeBatch: (batch) async {
        analyzed += batch.length;
        return BatchOutcome(
          usage: const BatchUsage(tokens: 100, credits: 0),
          verdicts: batch
              .map(
                (r) => CoverageVerdict(
                  path: r.path,
                  verdict: 'keep',
                  confidence: 'high',
                  reason: 'test',
                  coverageSource: r.kind == CoverageRowKind.group
                      ? 'group:${r.path}'
                      : 'file',
                  sizeBytes: r.sizeBytes,
                ),
              )
              .toList(),
        );
      },
    );

    final done = await controller.start(
      's1',
      budgetTokens: 100000,
      budgetCredits: 0,
    );
    expect(done.status, CoverageJobStatus.completed);
    expect(done.analyzedFiles, 80);
    expect(analyzed, 80);
    expect(await verdictStore.readAll('s1'), hasLength(80));
  });

  test('budget limit pauses with reason budget', () async {
    final rows = List.generate(
      80,
      (i) => CoverageRow(
        rowIndex: i,
        kind: CoverageRowKind.file,
        path: '/f$i',
        sizeBytes: 1,
      ),
    );
    final engine = FakeCoverageEngine(
      summary: const CoveragePlanSummary(
        snapshotId: 's2',
        planVersion: 1,
        rootPath: '/',
        totalUnclassified: 80,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 80,
        estimatedPages: 2,
      ),
      pages: [
        CoveragePage(
          snapshotId: 's2',
          planVersion: 1,
          nextCursor: 40,
          rows: rows.sublist(0, 40),
        ),
        CoveragePage(
          snapshotId: 's2',
          planVersion: 1,
          nextCursor: null,
          rows: rows.sublist(40),
        ),
      ],
    );
    final controller = CoverageJobController(
      engine: engine,
      verdictStore: verdictStore,
      stateStore: stateStore,
      analyzeBatch: (batch) async => BatchOutcome(
        usage: BatchUsage(tokens: batch.length * 100, credits: 0),
        verdicts: batch
            .map(
              (r) => CoverageVerdict(
                path: r.path,
                verdict: 'keep',
                confidence: 'high',
                reason: 'test',
                coverageSource: 'file',
                sizeBytes: r.sizeBytes,
              ),
            )
            .toList(),
      ),
    );

    final paused = await controller.start(
      's2',
      budgetTokens: 3000,
      budgetCredits: 0,
    );
    expect(paused.status, CoverageJobStatus.paused);
    expect(paused.pauseReason, CoveragePauseReason.budget);
  });

  test('resume rebuilds plan when continuing a paused job', () async {
    var buildPlanCalls = 0;
    final rows = List.generate(
      80,
      (i) => CoverageRow(
        rowIndex: i,
        kind: CoverageRowKind.file,
        path: '/f$i',
        sizeBytes: 1,
      ),
    );
    final engine = FakeCoverageEngine(
      onBuildPlan: () => buildPlanCalls++,
      summary: const CoveragePlanSummary(
        snapshotId: 's3',
        planVersion: 1,
        rootPath: '/',
        totalUnclassified: 80,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 80,
        estimatedPages: 2,
      ),
      pages: [
        CoveragePage(
          snapshotId: 's3',
          planVersion: 1,
          nextCursor: 40,
          rows: rows.sublist(0, 40),
        ),
        CoveragePage(
          snapshotId: 's3',
          planVersion: 1,
          nextCursor: null,
          rows: rows.sublist(40),
        ),
      ],
    );
    final controller = CoverageJobController(
      engine: engine,
      verdictStore: verdictStore,
      stateStore: stateStore,
      analyzeBatch: (batch) async => BatchOutcome(
        usage: BatchUsage(tokens: batch.length * 100, credits: 0),
        verdicts: batch
            .map(
              (r) => CoverageVerdict(
                path: r.path,
                verdict: 'keep',
                confidence: 'high',
                reason: 'test',
                coverageSource: 'file',
                sizeBytes: r.sizeBytes,
              ),
            )
            .toList(),
      ),
    );

    final paused = await controller.start(
      's3',
      budgetTokens: 3000,
      budgetCredits: 0,
    );
    expect(paused.status, CoverageJobStatus.paused);
    expect(buildPlanCalls, 1);

    await controller.resume('s3');
    expect(buildPlanCalls, greaterThanOrEqualTo(2));
  });

  test('manual pause persists paused(manual) to store', () async {
    final rows = List.generate(
      80,
      (i) => CoverageRow(
        rowIndex: i,
        kind: CoverageRowKind.file,
        path: '/f$i',
        sizeBytes: 1,
      ),
    );
    final engine = FakeCoverageEngine(
      summary: const CoveragePlanSummary(
        snapshotId: 's4',
        planVersion: 1,
        rootPath: '/',
        totalUnclassified: 80,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 80,
        estimatedPages: 2,
      ),
      pages: [
        CoveragePage(
          snapshotId: 's4',
          planVersion: 1,
          nextCursor: 40,
          rows: rows.sublist(0, 40),
        ),
        CoveragePage(
          snapshotId: 's4',
          planVersion: 1,
          nextCursor: null,
          rows: rows.sublist(40),
        ),
      ],
    );
    var batches = 0;
    late CoverageJobController controller;
    controller = CoverageJobController(
      engine: engine,
      verdictStore: verdictStore,
      stateStore: stateStore,
      analyzeBatch: (batch) async {
        batches++;
        if (batches == 1) {
          unawaited(Future<void>(() => controller.pause()));
        }
        return BatchOutcome(
          usage: const BatchUsage(tokens: 100, credits: 0),
          verdicts: batch
              .map(
                (r) => CoverageVerdict(
                  path: r.path,
                  verdict: 'keep',
                  confidence: 'high',
                  reason: 'test',
                  coverageSource: 'file',
                  sizeBytes: r.sizeBytes,
                ),
              )
              .toList(),
        );
      },
    );

    final paused = await controller.start(
      's4',
      budgetTokens: 100000,
      budgetCredits: 0,
    );

    expect(batches, 1);
    expect(paused.status, CoverageJobStatus.paused);
    expect(paused.pauseReason, CoveragePauseReason.manual);
    final loaded = await stateStore.load('s4');
    expect(loaded?.status, CoverageJobStatus.paused);
    expect(loaded?.pauseReason, CoveragePauseReason.manual);
  });

  test('processes all chunks on a page with maxInFlight waves', () async {
    final rows = List.generate(
      80,
      (i) => CoverageRow(
        rowIndex: i,
        kind: CoverageRowKind.file,
        path: '/f$i',
        sizeBytes: 1,
      ),
    );
    final engine = FakeCoverageEngine(
      summary: const CoveragePlanSummary(
        snapshotId: 's-wave',
        planVersion: 1,
        rootPath: '/',
        totalUnclassified: 80,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 80,
        estimatedPages: 1,
      ),
      pages: [
        CoveragePage(
          snapshotId: 's-wave',
          planVersion: 1,
          nextCursor: null,
          rows: rows,
        ),
      ],
    );
    var maxConcurrent = 0;
    var currentConcurrent = 0;
    final controller = CoverageJobController(
      engine: engine,
      verdictStore: verdictStore,
      stateStore: stateStore,
      batchSize: 40,
      maxInFlight: 2,
      analyzeBatch: (batch) async {
        currentConcurrent++;
        if (currentConcurrent > maxConcurrent) {
          maxConcurrent = currentConcurrent;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        currentConcurrent--;
        return BatchOutcome(
          usage: const BatchUsage(tokens: 10, credits: 0),
          verdicts: batch
              .map(
                (r) => CoverageVerdict(
                  path: r.path,
                  verdict: 'keep',
                  confidence: 'high',
                  reason: 'test',
                  coverageSource: 'file',
                  sizeBytes: r.sizeBytes,
                ),
              )
              .toList(),
        );
      },
    );

    final done = await controller.start(
      's-wave',
      budgetTokens: 100000,
      budgetCredits: 0,
    );

    expect(done.status, CoverageJobStatus.completed);
    expect(done.analyzedFiles, 80);
    expect(maxConcurrent, 2);
  });

  test(
    'wave usage accumulation pauses when budget exceeded mid-page',
    () async {
      final rows = List.generate(
        80,
        (i) => CoverageRow(
          rowIndex: i,
          kind: CoverageRowKind.file,
          path: '/f$i',
          sizeBytes: 1,
        ),
      );
      final engine = FakeCoverageEngine(
        summary: const CoveragePlanSummary(
          snapshotId: 's-wave-budget',
          planVersion: 1,
          rootPath: '/',
          totalUnclassified: 80,
          preClassifiedCount: 0,
          groupRows: 0,
          fileRows: 80,
          estimatedPages: 1,
        ),
        pages: [
          CoveragePage(
            snapshotId: 's-wave-budget',
            planVersion: 1,
            nextCursor: null,
            rows: rows,
          ),
        ],
      );
      final controller = CoverageJobController(
        engine: engine,
        verdictStore: verdictStore,
        stateStore: stateStore,
        batchSize: 40,
        maxInFlight: 2,
        analyzeBatch: (batch) async => BatchOutcome(
          usage: const BatchUsage(tokens: 600, credits: 0),
          verdicts: batch
              .map(
                (r) => CoverageVerdict(
                  path: r.path,
                  verdict: 'keep',
                  confidence: 'high',
                  reason: 'test',
                  coverageSource: 'file',
                  sizeBytes: r.sizeBytes,
                ),
              )
              .toList(),
        ),
      );

      final paused = await controller.start(
        's-wave-budget',
        budgetTokens: 1000,
        budgetCredits: 0,
      );

      expect(paused.status, CoverageJobStatus.paused);
      expect(paused.pauseReason, CoveragePauseReason.budget);
      expect(paused.usedTokens, 1200);
    },
  );

  test('resume while same snapshot is running is a no-op', () async {
    final gate = Completer<void>();
    final rows = List.generate(
      40,
      (i) => CoverageRow(
        rowIndex: i,
        kind: CoverageRowKind.file,
        path: '/f$i',
        sizeBytes: 1,
      ),
    );
    final engine = FakeCoverageEngine(
      summary: const CoveragePlanSummary(
        snapshotId: 's-same',
        planVersion: 1,
        rootPath: '/',
        totalUnclassified: 40,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 40,
        estimatedPages: 1,
      ),
      pages: [
        CoveragePage(
          snapshotId: 's-same',
          planVersion: 1,
          nextCursor: null,
          rows: rows,
        ),
      ],
    );
    var resumeCalls = 0;
    late CoverageJobController controller;
    controller = CoverageJobController(
      engine: engine,
      verdictStore: verdictStore,
      stateStore: stateStore,
      analyzeBatch: (batch) async {
        resumeCalls++;
        if (resumeCalls == 1) {
          unawaited(
            controller.resume('s-same').then((state) {
              expect(state.status, CoverageJobStatus.running);
              expect(state.snapshotId, 's-same');
            }),
          );
          await gate.future;
        }
        return BatchOutcome(
          usage: const BatchUsage(tokens: 1, credits: 0),
          verdicts: batch
              .map(
                (r) => CoverageVerdict(
                  path: r.path,
                  verdict: 'keep',
                  confidence: 'high',
                  reason: 'test',
                  coverageSource: 'file',
                  sizeBytes: r.sizeBytes,
                ),
              )
              .toList(),
        );
      },
    );

    final started = controller.start(
      's-same',
      budgetTokens: 100000,
      budgetCredits: 0,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    gate.complete();
    final done = await started;

    expect(done.status, CoverageJobStatus.completed);
    expect(resumeCalls, 1);
  });

  test('cancel marks paused job cancelled', () async {
    final rows = List.generate(
      80,
      (i) => CoverageRow(
        rowIndex: i,
        kind: CoverageRowKind.file,
        path: '/f$i',
        sizeBytes: 1,
      ),
    );
    final engine = FakeCoverageEngine(
      summary: const CoveragePlanSummary(
        snapshotId: 's-cancel',
        planVersion: 1,
        rootPath: '/',
        totalUnclassified: 80,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 80,
        estimatedPages: 2,
      ),
      pages: [
        CoveragePage(
          snapshotId: 's-cancel',
          planVersion: 1,
          nextCursor: 40,
          rows: rows.sublist(0, 40),
        ),
        CoveragePage(
          snapshotId: 's-cancel',
          planVersion: 1,
          nextCursor: null,
          rows: rows.sublist(40),
        ),
      ],
    );
    var batches = 0;
    late CoverageJobController controller;
    controller = CoverageJobController(
      engine: engine,
      verdictStore: verdictStore,
      stateStore: stateStore,
      analyzeBatch: (batch) async {
        batches++;
        if (batches == 1) {
          unawaited(Future<void>(() => controller.pause()));
        }
        return BatchOutcome(
          usage: const BatchUsage(tokens: 1, credits: 0),
          verdicts: batch
              .map(
                (r) => CoverageVerdict(
                  path: r.path,
                  verdict: 'keep',
                  confidence: 'high',
                  reason: 'test',
                  coverageSource: 'file',
                  sizeBytes: r.sizeBytes,
                ),
              )
              .toList(),
        );
      },
    );

    final paused = await controller.start(
      's-cancel',
      budgetTokens: 100000,
      budgetCredits: 0,
    );
    expect(paused.status, CoverageJobStatus.paused);

    final cancelled = await controller.cancel('s-cancel');

    expect(cancelled.status, CoverageJobStatus.cancelled);
    final loaded = await stateStore.load('s-cancel');
    expect(loaded?.status, CoverageJobStatus.cancelled);
  });

  test('group rows store a single group verdict with member count', () async {
    const groupPath = '/Users/x/Library/Caches/cursor';
    final engine = FakeCoverageEngine(
      summary: const CoveragePlanSummary(
        snapshotId: 's5',
        planVersion: 1,
        rootPath: '/Users/x',
        totalUnclassified: 2,
        preClassifiedCount: 0,
        groupRows: 1,
        fileRows: 0,
        estimatedPages: 1,
      ),
      pages: const [
        CoveragePage(
          snapshotId: 's5',
          planVersion: 1,
          nextCursor: null,
          rows: [
            CoverageRow(
              rowIndex: 0,
              kind: CoverageRowKind.group,
              path: groupPath,
              sizeBytes: 30,
              memberCount: 2,
            ),
          ],
        ),
      ],
    );
    final controller = CoverageJobController(
      engine: engine,
      verdictStore: verdictStore,
      stateStore: stateStore,
      analyzeBatch: (batch) async => BatchOutcome(
        usage: const BatchUsage(tokens: 100, credits: 0),
        verdicts: batch
            .map(
              (r) => CoverageVerdict(
                path: r.path,
                verdict: 'safe_to_remove',
                confidence: 'high',
                reason: 'cache',
                coverageSource: 'group:${r.path}',
                sizeBytes: r.sizeBytes,
                groupMemberCount: r.memberCount,
              ),
            )
            .toList(),
      ),
    );

    await controller.start('s5', budgetTokens: 100000, budgetCredits: 0);
    final verdicts = await verdictStore.readAll('s5');

    expect(verdicts, hasLength(1));
    final group = verdicts.single;
    expect(group.path, groupPath);
    expect(group.coverageSource, 'group:$groupPath');
    expect(group.groupMemberCount, 2);
    expect(group.verdict, 'safe_to_remove');
  });

  test('markAppQuit pauses a running job with appQuit reason', () async {
    final rows = List.generate(
      80,
      (i) => CoverageRow(
        rowIndex: i,
        kind: CoverageRowKind.file,
        path: '/f$i',
        sizeBytes: 1,
      ),
    );
    final engine = FakeCoverageEngine(
      summary: const CoveragePlanSummary(
        snapshotId: 's-quit',
        planVersion: 1,
        rootPath: '/',
        totalUnclassified: 80,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 80,
        estimatedPages: 1,
      ),
      pages: [
        CoveragePage(
          snapshotId: 's-quit',
          planVersion: 1,
          nextCursor: null,
          rows: rows,
        ),
      ],
    );
    final firstBatchStarted = Completer<void>();
    final releaseBatch = Completer<void>();
    var batchesStarted = 0;
    final controller = CoverageJobController(
      engine: engine,
      verdictStore: verdictStore,
      stateStore: stateStore,
      batchSize: 40,
      maxInFlight: 1,
      analyzeBatch: (batch) async {
        batchesStarted++;
        if (batchesStarted == 1) {
          firstBatchStarted.complete();
          await releaseBatch.future;
        }
        return BatchOutcome(
          usage: const BatchUsage(tokens: 10, credits: 0),
          verdicts: batch
              .map(
                (r) => CoverageVerdict(
                  path: r.path,
                  verdict: 'keep',
                  confidence: 'high',
                  reason: 'test',
                  coverageSource: 'file',
                  sizeBytes: r.sizeBytes,
                ),
              )
              .toList(),
        );
      },
    );

    final startFuture = controller.start(
      's-quit',
      budgetTokens: 100000,
      budgetCredits: 0,
    );
    await firstBatchStarted.future;
    final quitFuture = controller.markAppQuit();
    releaseBatch.complete();
    await quitFuture;

    expect(controller.state?.status, CoverageJobStatus.paused);
    expect(controller.state?.pauseReason, CoveragePauseReason.appQuit);
    expect(batchesStarted, 1);

    await startFuture;
  });

  test('pause cancels an in-flight batch and returns promptly', () async {
    final rows = List.generate(
      80,
      (i) => CoverageRow(
        rowIndex: i,
        kind: CoverageRowKind.file,
        path: '/f$i',
        sizeBytes: 1,
      ),
    );
    final engine = FakeCoverageEngine(
      summary: const CoveragePlanSummary(
        snapshotId: 's-cancel-inflight',
        planVersion: 1,
        rootPath: '/',
        totalUnclassified: 80,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 80,
        estimatedPages: 1,
      ),
      pages: [
        CoveragePage(
          snapshotId: 's-cancel-inflight',
          planVersion: 1,
          nextCursor: null,
          rows: rows,
        ),
      ],
    );
    final cancelToken = CancelToken();
    final firstBatchStarted = Completer<void>();
    var batchesStarted = 0;
    final controller = CoverageJobController(
      engine: engine,
      verdictStore: verdictStore,
      stateStore: stateStore,
      batchSize: 40,
      maxInFlight: 1,
      cancelToken: cancelToken,
      analyzeBatch: (batch) async {
        batchesStarted++;
        if (batchesStarted == 1) {
          firstBatchStarted.complete();
          await cancelToken.whenCancelled;
          throw const CoverageCancelledException();
        }
        return BatchOutcome(
          usage: const BatchUsage(tokens: 10, credits: 0),
          verdicts: batch
              .map(
                (r) => CoverageVerdict(
                  path: r.path,
                  verdict: 'keep',
                  confidence: 'high',
                  reason: 'test',
                  coverageSource: 'file',
                  sizeBytes: r.sizeBytes,
                ),
              )
              .toList(),
        );
      },
    );

    final startFuture = controller.start(
      's-cancel-inflight',
      budgetTokens: 100000,
      budgetCredits: 0,
    );
    await firstBatchStarted.future;
    final pauseFuture = controller.pause();
    await pauseFuture;

    expect(controller.state?.status, CoverageJobStatus.paused);
    expect(controller.state?.pauseReason, CoveragePauseReason.manual);
    expect(batchesStarted, 1);
    expect(await verdictStore.readAll('s-cancel-inflight'), isEmpty);

    await startFuture;
  });

  test('cursor advances past persisted batches when a sibling fails', () async {
    final rows = List.generate(
      80,
      (i) => CoverageRow(
        rowIndex: i,
        kind: CoverageRowKind.file,
        path: '/f$i',
        sizeBytes: 1,
      ),
    );
    final engine = FakeCoverageEngine(
      summary: const CoveragePlanSummary(
        snapshotId: 's-partial-fail',
        planVersion: 1,
        rootPath: '/',
        totalUnclassified: 80,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 80,
        estimatedPages: 1,
      ),
      pages: [
        CoveragePage(
          snapshotId: 's-partial-fail',
          planVersion: 1,
          nextCursor: null,
          rows: rows,
        ),
      ],
    );
    final controller = CoverageJobController(
      engine: engine,
      verdictStore: verdictStore,
      stateStore: stateStore,
      batchSize: 40,
      maxInFlight: 2,
      analyzeBatch: (batch) async {
        if (batch.first.rowIndex >= 40) {
          throw Exception('boom');
        }
        return BatchOutcome(
          usage: const BatchUsage(tokens: 10, credits: 0),
          verdicts: batch
              .map(
                (r) => CoverageVerdict(
                  path: r.path,
                  verdict: 'keep',
                  confidence: 'high',
                  reason: 'test',
                  coverageSource: 'file',
                  sizeBytes: r.sizeBytes,
                ),
              )
              .toList(),
        );
      },
    );

    final state = await controller.start(
      's-partial-fail',
      budgetTokens: 100000,
      budgetCredits: 0,
    );

    expect(state.status, CoverageJobStatus.paused);
    expect(state.pauseReason, CoveragePauseReason.failed);
    // The successful first chunk (rows 0-39) was persisted and its cursor
    // advanced; only the failed chunk (rows 40-79) remains to re-send.
    expect(state.cursor, 40);
    expect(await verdictStore.readAll('s-partial-fail'), hasLength(40));
  });

  test('resume rejects root_path mismatch as failed', () async {
    await stateStore.save(
      const CoverageJobState(
        snapshotId: 's6',
        rootPath: '/old',
        planVersion: 1,
        cursor: 0,
        totalUnclassified: 1,
        analyzedFiles: 0,
        preClassifiedCount: 0,
        status: CoverageJobStatus.paused,
        pauseReason: CoveragePauseReason.budget,
        usedTokens: 0,
        usedCredits: 0,
        budgetTokens: 100000,
        budgetCredits: 0,
        updatedAtMs: 1,
      ),
    );
    final engine = FakeCoverageEngine(
      summary: const CoveragePlanSummary(
        snapshotId: 's6',
        planVersion: 1,
        rootPath: '/new',
        totalUnclassified: 1,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 1,
        estimatedPages: 1,
      ),
      pages: const [
        CoveragePage(
          snapshotId: 's6',
          planVersion: 1,
          nextCursor: null,
          rows: [
            CoverageRow(
              rowIndex: 0,
              kind: CoverageRowKind.file,
              path: '/new/file.bin',
              sizeBytes: 1,
            ),
          ],
        ),
      ],
    );
    final controller = CoverageJobController(
      engine: engine,
      verdictStore: verdictStore,
      stateStore: stateStore,
      analyzeBatch: (_) async => throw StateError('should not analyze'),
    );

    final failed = await controller.resume('s6');

    expect(failed.status, CoverageJobStatus.paused);
    expect(failed.pauseReason, CoveragePauseReason.failed);
  });

  test('start creates a fresh state and clears old verdicts', () async {
    await stateStore.save(
      const CoverageJobState(
        snapshotId: 's-restart',
        rootPath: '/',
        planVersion: 1,
        cursor: 40,
        totalUnclassified: 80,
        analyzedFiles: 40,
        preClassifiedCount: 0,
        status: CoverageJobStatus.paused,
        pauseReason: CoveragePauseReason.budget,
        usedTokens: 999,
        usedCredits: 7,
        budgetTokens: 1000,
        budgetCredits: 8,
        updatedAtMs: 1,
      ),
    );
    await verdictStore.appendAll('s-restart', const [
      CoverageVerdict(
        path: '/old',
        verdict: 'keep',
        confidence: 'high',
        reason: 'old run',
        coverageSource: 'file',
        sizeBytes: 1,
      ),
    ]);
    final controller = CoverageJobController(
      engine: FakeCoverageEngine(
        summary: const CoveragePlanSummary(
          snapshotId: 's-restart',
          planVersion: 1,
          rootPath: '/',
          totalUnclassified: 1,
          preClassifiedCount: 0,
          groupRows: 0,
          fileRows: 1,
          estimatedPages: 1,
        ),
        pages: const [
          CoveragePage(
            snapshotId: 's-restart',
            planVersion: 1,
            nextCursor: null,
            rows: [
              CoverageRow(
                rowIndex: 0,
                kind: CoverageRowKind.file,
                path: '/new',
                sizeBytes: 2,
              ),
            ],
          ),
        ],
      ),
      verdictStore: verdictStore,
      stateStore: stateStore,
      analyzeBatch: (batch) async => BatchOutcome(
        usage: const BatchUsage(tokens: 10, credits: 1),
        verdicts: batch
            .map(
              (row) => CoverageVerdict(
                path: row.path,
                verdict: 'review_needed',
                confidence: 'high',
                reason: 'new run',
                coverageSource: 'file',
                sizeBytes: row.sizeBytes,
              ),
            )
            .toList(),
      ),
    );

    final restarted = await controller.start(
      's-restart',
      budgetTokens: 200,
      budgetCredits: 3,
    );

    expect(restarted.status, CoverageJobStatus.completed);
    expect(restarted.cursor, 1);
    expect(restarted.analyzedFiles, 1);
    expect(restarted.usedTokens, 10);
    expect(restarted.usedCredits, 1);
    expect(restarted.budgetTokens, 200);
    expect(restarted.budgetCredits, 3);
    expect((await verdictStore.readAll('s-restart')).map((v) => v.path), [
      '/new',
    ]);
  });

  test('resume hydrates paused job from store on fresh controller', () async {
    await stateStore.save(
      const CoverageJobState(
        snapshotId: 's-hydrate',
        rootPath: '/',
        planVersion: 1,
        cursor: 40,
        totalUnclassified: 80,
        analyzedFiles: 40,
        preClassifiedCount: 0,
        status: CoverageJobStatus.paused,
        pauseReason: CoveragePauseReason.manual,
        usedTokens: 0,
        usedCredits: 0,
        budgetTokens: 100000,
        budgetCredits: 0,
        updatedAtMs: 1,
      ),
    );
    final rows = List.generate(
      80,
      (i) => CoverageRow(
        rowIndex: i,
        kind: CoverageRowKind.file,
        path: '/f$i',
        sizeBytes: 1,
      ),
    );
    final engine = FakeCoverageEngine(
      summary: const CoveragePlanSummary(
        snapshotId: 's-hydrate',
        planVersion: 1,
        rootPath: '/',
        totalUnclassified: 80,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 80,
        estimatedPages: 2,
      ),
      pages: [
        CoveragePage(
          snapshotId: 's-hydrate',
          planVersion: 1,
          nextCursor: null,
          rows: rows.sublist(40),
        ),
      ],
    );
    final controller = CoverageJobController(
      engine: engine,
      verdictStore: verdictStore,
      stateStore: stateStore,
      analyzeBatch: (batch) async => BatchOutcome(
        usage: const BatchUsage(tokens: 1, credits: 0),
        verdicts: batch
            .map(
              (r) => CoverageVerdict(
                path: r.path,
                verdict: 'keep',
                confidence: 'high',
                reason: 'test',
                coverageSource: 'file',
                sizeBytes: r.sizeBytes,
              ),
            )
            .toList(),
      ),
    );

    final resumed = await controller.resume('s-hydrate');

    expect(resumed.status, CoverageJobStatus.completed);
    expect(resumed.analyzedFiles, 80);
  });

  test('raiseBudgetAndResume hydrates budget-paused job from store', () async {
    await stateStore.save(
      const CoverageJobState(
        snapshotId: 's-budget',
        rootPath: '/',
        planVersion: 1,
        cursor: 40,
        totalUnclassified: 80,
        analyzedFiles: 40,
        preClassifiedCount: 0,
        status: CoverageJobStatus.paused,
        pauseReason: CoveragePauseReason.budget,
        usedTokens: 100000,
        usedCredits: 0,
        budgetTokens: 100000,
        budgetCredits: 0,
        updatedAtMs: 1,
      ),
    );
    final rows = List.generate(
      80,
      (i) => CoverageRow(
        rowIndex: i,
        kind: CoverageRowKind.file,
        path: '/f$i',
        sizeBytes: 1,
      ),
    );
    final engine = FakeCoverageEngine(
      summary: const CoveragePlanSummary(
        snapshotId: 's-budget',
        planVersion: 1,
        rootPath: '/',
        totalUnclassified: 80,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 80,
        estimatedPages: 2,
      ),
      pages: [
        CoveragePage(
          snapshotId: 's-budget',
          planVersion: 1,
          nextCursor: null,
          rows: rows.sublist(40),
        ),
      ],
    );
    final controller = CoverageJobController(
      engine: engine,
      verdictStore: verdictStore,
      stateStore: stateStore,
      analyzeBatch: (batch) async => BatchOutcome(
        usage: const BatchUsage(tokens: 1, credits: 0),
        verdicts: batch
            .map(
              (r) => CoverageVerdict(
                path: r.path,
                verdict: 'keep',
                confidence: 'high',
                reason: 'test',
                coverageSource: 'file',
                sizeBytes: r.sizeBytes,
              ),
            )
            .toList(),
      ),
    );

    final resumed = await controller.raiseBudgetAndResume(
      snapshotId: 's-budget',
      budgetTokens: 200000,
      budgetCredits: 0,
    );

    expect(resumed.status, CoverageJobStatus.completed);
    expect(resumed.budgetTokens, 200000);
    expect(resumed.analyzedFiles, 80);
  });

  test('cancel hydrates paused job from store on fresh controller', () async {
    await stateStore.save(
      const CoverageJobState(
        snapshotId: 's-cancel-store',
        rootPath: '/',
        planVersion: 1,
        cursor: 40,
        totalUnclassified: 80,
        analyzedFiles: 40,
        preClassifiedCount: 0,
        status: CoverageJobStatus.paused,
        pauseReason: CoveragePauseReason.manual,
        usedTokens: 0,
        usedCredits: 0,
        budgetTokens: 100000,
        budgetCredits: 0,
        updatedAtMs: 1,
      ),
    );
    final controller = CoverageJobController(
      engine: FakeCoverageEngine(
        summary: const CoveragePlanSummary(
          snapshotId: 's-cancel-store',
          planVersion: 1,
          rootPath: '/',
          totalUnclassified: 80,
          preClassifiedCount: 0,
          groupRows: 0,
          fileRows: 80,
          estimatedPages: 2,
        ),
        pages: const [],
      ),
      verdictStore: verdictStore,
      stateStore: stateStore,
      analyzeBatch: (_) async => throw StateError('should not analyze'),
    );

    final cancelled = await controller.cancel('s-cancel-store');

    expect(cancelled.status, CoverageJobStatus.cancelled);
    final loaded = await stateStore.load('s-cancel-store');
    expect(loaded?.status, CoverageJobStatus.cancelled);
  });

  test(
    'resume for another missing snapshot does not reuse current state',
    () async {
      await stateStore.save(
        const CoverageJobState(
          snapshotId: 's-current',
          rootPath: '/',
          planVersion: 1,
          cursor: 0,
          totalUnclassified: 0,
          analyzedFiles: 0,
          preClassifiedCount: 0,
          status: CoverageJobStatus.paused,
          pauseReason: CoveragePauseReason.manual,
          usedTokens: 0,
          usedCredits: 0,
          budgetTokens: 100,
          budgetCredits: 0,
          updatedAtMs: 1,
        ),
      );
      final controller = CoverageJobController(
        engine: FakeCoverageEngine(
          summary: const CoveragePlanSummary(
            snapshotId: 's-current',
            planVersion: 1,
            rootPath: '/',
            totalUnclassified: 0,
            preClassifiedCount: 0,
            groupRows: 0,
            fileRows: 0,
            estimatedPages: 0,
          ),
          pages: const [],
        ),
        verdictStore: verdictStore,
        stateStore: stateStore,
        analyzeBatch: (_) async => throw StateError('should not analyze'),
      );

      expect(
        (await controller.resume('missing')).status,
        CoverageJobStatus.idle,
      );
      expect(controller.state, isNull);
    },
  );

  test('resume rejects a changed snapshot fingerprint', () async {
    const savedFingerprint = CoverageSnapshotFingerprint(
      rootSizeBytes: 10,
      scannedAtMs: 100,
      pathsSeen: 3,
      dirsSeen: 1,
      filesSeen: 2,
      filesInSnapshot: 2,
      pathsSkipped: 0,
      truncated: false,
      incompleteReason: null,
    );
    await stateStore.save(
      const CoverageJobState(
        snapshotId: 's-fingerprint',
        rootPath: '/',
        planVersion: 1,
        cursor: 1,
        totalUnclassified: 1,
        analyzedFiles: 1,
        preClassifiedCount: 0,
        status: CoverageJobStatus.paused,
        pauseReason: CoveragePauseReason.appQuit,
        usedTokens: 1,
        usedCredits: 0,
        budgetTokens: 100,
        budgetCredits: 0,
        updatedAtMs: 1,
        fingerprint: savedFingerprint,
      ),
    );
    final controller = CoverageJobController(
      engine: FakeCoverageEngine(
        summary: const CoveragePlanSummary(
          snapshotId: 's-fingerprint',
          planVersion: 1,
          rootPath: '/',
          totalUnclassified: 1,
          preClassifiedCount: 0,
          groupRows: 0,
          fileRows: 1,
          estimatedPages: 1,
          fingerprint: CoverageSnapshotFingerprint(
            rootSizeBytes: 11,
            scannedAtMs: 100,
            pathsSeen: 3,
            dirsSeen: 1,
            filesSeen: 2,
            filesInSnapshot: 2,
            pathsSkipped: 0,
            truncated: false,
            incompleteReason: null,
          ),
        ),
        pages: const [],
      ),
      verdictStore: verdictStore,
      stateStore: stateStore,
      analyzeBatch: (_) async => throw StateError('should not analyze'),
    );

    final failed = await controller.resume('s-fingerprint');

    expect(failed.status, CoverageJobStatus.paused);
    expect(failed.pauseReason, CoveragePauseReason.failed);
  });
}
