import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/cancel_token.dart';
import 'package:volward/ai/coverage_analyze_tree_batch.dart';
import 'package:volward/ai/coverage_models.dart';

class _FakeTreeProvider implements TreeAiProvider {
  _FakeTreeProvider({required this.verdicts, this.credits = 1});

  final List<AiVerdict> verdicts;
  final int credits;

  @override
  Future<AnalyzeResult> analyzeTreeNodes(
    List<CoverageTreeNode> nodes, {
    CancelToken? cancelToken,
  }) async {
    return AnalyzeResult(verdicts: verdicts, credits: credits);
  }
}

CoverageTreeNode _node({required String path, required String role}) =>
    CoverageTreeNode(
      path: path,
      sizeBytes: 100,
      fileCount: 10,
      subdirCount: 2,
      role: role,
    );

void main() {
  test('project_root safe_to_remove high coerces to drill_down', () async {
    const projectPath = '/Users/me/project';
    final batch = createCoverageAnalyzeTreeBatch(
      provider: _FakeTreeProvider(
        verdicts: const [
          AiVerdict(
            path: projectPath,
            verdict: 'safe_to_remove',
            confidence: 'high',
            reason: 'looks empty',
          ),
        ],
      ),
    );
    final outcome = await batch([
      _node(path: projectPath, role: 'project_root'),
    ]);
    expect(outcome.verdicts.single.verdict, 'drill_down');
    expect(outcome.verdicts.single.coverageSource, 'dir:$projectPath');
    expect(outcome.verdicts.single.reason, contains('coerced'));
  });

  test('non-project node keeps safe_to_remove', () async {
    const cachePath = '/Users/me/.cache/app';
    final batch = createCoverageAnalyzeTreeBatch(
      provider: _FakeTreeProvider(
        verdicts: const [
          AiVerdict(
            path: cachePath,
            verdict: 'safe_to_remove',
            confidence: 'high',
            reason: 'cache dir',
          ),
        ],
      ),
    );
    final outcome = await batch([_node(path: cachePath, role: 'cache_like')]);
    expect(outcome.verdicts.single.verdict, 'safe_to_remove');
    expect(outcome.verdicts.single.reason, 'cache dir');
  });
}
