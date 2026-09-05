import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_coverage_job_controller.dart';
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

    await controller.resume();
    expect(buildPlanCalls, greaterThanOrEqualTo(2));
  });
}
