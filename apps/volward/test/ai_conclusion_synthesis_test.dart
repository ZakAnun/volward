import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_conclusion_synthesis.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/ai_result_overview.dart';

void main() {
  test('conclusionContentHash changes when verdict reason changes', () {
    const overview = AiAnalysisConclusionOverview(
      targetLabel: 'Home',
      rootPath: '/home',
      safeBytes: 100,
      reviewCount: 0,
      keepCount: 0,
      analyzedItemCount: 1,
      analyzedTotalBytes: 100,
      rootSizeBytes: 1000,
      shareOfRootPct: 10,
      truncated: false,
      fullCoverage: true,
      directories: [
        AiDirectoryConclusion(
          path: '/home/Library',
          displayLabel: 'Library',
          safeBytes: 100,
          reviewCount: 0,
          keepCount: 0,
          shareOfSafePct: 100,
          reasonHighlights: ['Cache A'],
        ),
      ],
    );
    const verdictsA = [
      AiVerdict(
        path: '/home/Library/Caches/foo',
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: 'Application cache',
      ),
    ];
    const verdictsB = [
      AiVerdict(
        path: '/home/Library/Caches/foo',
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: 'Different reason',
      ),
    ];

    final hashA = conclusionContentHash(overview, verdictsA);
    final hashB = conclusionContentHash(overview, verdictsB);

    expect(hashA, isNot(equals(hashB)));
  });

  test('conclusionContentHash is stable for identical inputs', () {
    const verdicts = [
      AiVerdict(
        path: '/home/a',
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: 'Cache',
      ),
    ];
    final overview = buildAiAnalysisConclusionOverview(
      const AiResultOverviewBuildInput(
        targetLabel: 'Home',
        rootPath: '/home',
        verdicts: verdicts,
        sizeByPath: {'/home/a': 50},
        rootSizeBytesHint: 500,
      ),
    );

    expect(
      conclusionContentHash(overview, verdicts),
      conclusionContentHash(overview, verdicts),
    );
  });

  test('buildConclusionSynthesisRequest emits schema_version 2 JSON', () {
    const verdicts = [
      AiVerdict(
        path: '/home/Library/Caches/foo',
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: 'Application cache',
      ),
    ];
    const buildInput = AiResultOverviewBuildInput(
      targetLabel: 'Home',
      rootPath: '/home',
      verdicts: verdicts,
      sizeByPath: {'/home/Library/Caches/foo': 200},
      rootSizeBytesHint: 1000,
      truncated: true,
      fullCoverage: false,
    );
    final overview = buildAiAnalysisConclusionOverview(buildInput);
    final request = buildConclusionSynthesisRequest(
      overview: overview,
      buildInput: buildInput,
      analysisSessionId: 'session-abc',
      locale: 'zh',
    );

    final json = request.toJson();
    expect(json['schema_version'], 2);
    expect(json['analysis_session_id'], 'session-abc');
    expect(json['locale'], 'zh');
    expect(json['root_label'], 'Home');
    expect(json['scan'], {
      'root_path': '/home',
      'truncated': true,
      'full_coverage': false,
    });
    expect(json['totals'], isA<Map<String, dynamic>>());
    expect(json['totals']['safe_bytes'], 200);

    final directories = json['directories'] as List<dynamic>;
    expect(directories, isNotEmpty);
    final first = directories.first as Map<String, dynamic>;
    expect(first['reason_highlights'], contains('Application cache'));
    expect(first['display_label'], isNotEmpty);
  });

  test('AiConclusionSynthesisResponse parses text from JSON', () {
    final response = AiConclusionSynthesisResponse.fromJson({
      'text': 'Most reclaimable space is under Library caches.',
    });
    expect(response.text, 'Most reclaimable space is under Library caches.');
  });
}
