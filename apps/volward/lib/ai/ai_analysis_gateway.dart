import '../capabilities/capability_models.dart';
import '../volward_session.dart';
import 'ai_provider.dart';
import 'ai_settings_store.dart';
import 'session_ai_contract.dart';

abstract interface class AiAnalysisGateway {
  Future<AiMode> getMode();
  Future<AiProvider?> resolveProvider();
  Future<bool> isPrivacyAccepted();
  Future<void> setPrivacyAccepted(bool value);
  Future<ByokTokenUsageTotals> recordByokTokenUsage({
    required int inputTokens,
    required int outputTokens,
    required int totalTokens,
    required bool estimated,
    required bool partial,
  });
  Future<String?> buildCandidates(String snapshotId);
  String? loadResult(String key);
  bool saveResult(String snapshotId, String resultJson);
  Future<CapabilityAnalysisResult> analyzeCapability({
    required String snapshotId,
    required Capability capability,
    AnalysisOptions? options,
  });
  Future<Map<String, dynamic>> deleteEntries(
    List<String> targets, {
    String? snapshotId,
    bool dryRun = false,
    bool rescanAfterDelete = false,
  });
}

/// Coverage reads used while rendering an AI analysis workspace.
abstract interface class AiWorkspaceCoverage {
  bool get sessionReady;
  bool get hasCoverageApi;
  Future<int> backfillLocalVerdicts(String snapshotId, String storeDirectory);
}

class ProductionAiAnalysisGateway
    implements AiAnalysisGateway, AiWorkspaceCoverage {
  const ProductionAiAnalysisGateway({this.session});

  final VolwardSession? session;
  VolwardSession? get _session => session ?? VolwardSession.instance;

  @override
  Future<AiMode> getMode() => AiSettingsStore.instance.getMode();

  @override
  Future<AiProvider?> resolveProvider() {
    final current = session;
    final store = AiSettingsStore.instance;
    if (current == null) return store.resolveProvider();
    return store.resolveProviderWithContract(() => SessionAiContract(current));
  }

  @override
  bool get sessionReady => _session?.ready ?? false;

  @override
  bool get hasCoverageApi => _session?.hasAiCoverageApi ?? false;

  @override
  Future<int> backfillLocalVerdicts(
    String snapshotId,
    String storeDirectory,
  ) async {
    final current = _session;
    final engine = current?.treeCoverageEngine ?? current?.coverageEngine;
    if (engine == null) return 0;
    return engine.backfillLocalVerdictsToStore(snapshotId, storeDirectory);
  }

  @override
  Future<bool> isPrivacyAccepted() =>
      AiSettingsStore.instance.isPrivacyAccepted();

  @override
  Future<void> setPrivacyAccepted(bool value) =>
      AiSettingsStore.instance.setPrivacyAccepted(value);

  @override
  Future<ByokTokenUsageTotals> recordByokTokenUsage({
    required int inputTokens,
    required int outputTokens,
    required int totalTokens,
    required bool estimated,
    required bool partial,
  }) => AiSettingsStore.instance.addByokTokenUsage(
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    totalTokens: totalTokens,
    estimated: estimated,
    partial: partial,
  );

  @override
  Future<String?> buildCandidates(String snapshotId) async =>
      _session?.buildAiCandidatesJsonAsync(snapshotId);

  @override
  String? loadResult(String key) => _session?.loadAiResultJson(key);

  @override
  bool saveResult(String snapshotId, String resultJson) =>
      _session?.saveAiResultJson(snapshotId, resultJson) ?? false;

  @override
  Future<CapabilityAnalysisResult> analyzeCapability({
    required String snapshotId,
    required Capability capability,
    AnalysisOptions? options,
  }) async {
    final current = _session;
    if (current == null) {
      throw StateError('Native session unavailable');
    }
    return current.analyzeCapability(
      snapshotId: snapshotId,
      capability: capability,
      options: options,
    );
  }

  @override
  Future<Map<String, dynamic>> deleteEntries(
    List<String> targets, {
    String? snapshotId,
    bool dryRun = false,
    bool rescanAfterDelete = false,
  }) {
    final current = _session;
    if (current == null) throw StateError('Native session unavailable');
    return current.deleteEntries(
      targets,
      expectedSnapshotId: snapshotId,
      dryRun: dryRun,
      rescanAfterDelete: rescanAfterDelete,
    );
  }
}
