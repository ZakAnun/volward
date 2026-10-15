import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_analysis_gateway.dart';
import 'package:volward/ai/ai_coverage_coordinator.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/capabilities/capability_models.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/widgets/ai_analysis_workspace.dart';

const _candidatePayload = '''
{
  "pre_classified": [],
  "unknown_candidates": [
    {"path": "/tmp/x", "size_bytes": 1, "is_dir": false}
  ],
  "estimated_input_tokens": 1,
  "has_existing_result": false,
  "truncated": false,
  "candidates_total_before_cap": 1,
  "result_cache_key": "k",
  "root_path": "/home"
}
''';

class _CountingGateway implements AiAnalysisGateway {
  _CountingGateway(this.label);

  final String label;
  final candidateRequests = <String>[];
  String? candidatesJson = _candidatePayload;

  @override
  Future<String?> buildCandidates(String snapshotId) async {
    candidateRequests.add('$label:$snapshotId');
    return candidatesJson;
  }

  @override
  Future<Map<String, dynamic>> deleteEntries(
    List<String> targets, {
    String? snapshotId,
    bool dryRun = false,
    bool rescanAfterDelete = false,
    String? refreshPath,
    Map<String, String>? targetPathById,
  }) async => {'deleted_count': 0, 'freed_bytes': 0};

  @override
  Future<AiMode> getMode() async => AiMode.byok;

  @override
  Future<bool> isPrivacyAccepted() async => true;

  @override
  Future<ByokTokenUsageTotals> recordByokTokenUsage({
    required int inputTokens,
    required int outputTokens,
    required int totalTokens,
    required bool estimated,
    required bool partial,
  }) async => ByokTokenUsageTotals(
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    totalTokens: totalTokens,
    analysisCount: 1,
    estimatedAnalysisCount: 0,
    partialAnalysisCount: 0,
    updatedAtMs: 1,
  );

  @override
  Future<AiProvider?> resolveProvider() async => null;

  @override
  Future<void> setPrivacyAccepted(bool value) async {}

  @override
  String? loadResult(String key) => null;

  @override
  bool saveResult(String snapshotId, String resultJson) => true;

  @override
  Future<CapabilityAnalysisResult> analyzeCapability({
    required String snapshotId,
    required Capability capability,
    AnalysisOptions? options,
  }) async {
    throw UnimplementedError();
  }
}

class _GatewayHost extends StatefulWidget {
  const _GatewayHost({super.key, required this.gateway});

  final AiAnalysisGateway gateway;

  @override
  State<_GatewayHost> createState() => _GatewayHostState();
}

class _GatewayHostState extends State<_GatewayHost> {
  late AiAnalysisGateway _gateway;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway;
  }

  void swapGateway(AiAnalysisGateway gateway) {
    setState(() => _gateway = gateway);
  }

  @override
  Widget build(BuildContext context) {
    return AiAnalysisWorkspace(
      snapshotId: 'snapshot-1',
      targetLabel: 'Home',
      gateway: _gateway,
      onExit: () {},
      onOpenSettings: () {},
      onDeletingChanged: (_) {},
      onDeleteCompleted: () {},
    );
  }
}

Future<void> _pumpUntilBootstrapDone(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    if (find.textContaining('Start').evaluate().isNotEmpty) return;
  }
  fail('bootstrap timeout');
}

void main() {
  testWidgets('gateway swap does not request candidates again', (tester) async {
    AiCoverageCoordinator.instance.detach();
    final gatewayA = _CountingGateway('A');
    final gatewayB = _CountingGateway('B');

    final hostKey = GlobalKey<_GatewayHostState>();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: buildVolwardTheme(brightness: Brightness.light),
        home: Scaffold(
          body: _GatewayHost(key: hostKey, gateway: gatewayA),
        ),
      ),
    );

    await _pumpUntilBootstrapDone(tester);
    expect(gatewayA.candidateRequests, ['A:snapshot-1']);

    hostKey.currentState!.swapGateway(gatewayB);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(gatewayB.candidateRequests, isEmpty);
    expect(gatewayA.candidateRequests.length, 1);
  });
}
