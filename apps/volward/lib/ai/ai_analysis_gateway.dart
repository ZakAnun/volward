import '../volward_session.dart';
import 'ai_provider.dart';
import 'ai_settings_store.dart';

abstract interface class AiAnalysisGateway {
  Future<AiMode> getMode();
  Future<AiProvider?> resolveProvider();
  Future<bool> isPrivacyAccepted();
  Future<void> setPrivacyAccepted(bool value);
  Future<String?> buildCandidates(String snapshotId);
  String? loadResult(String key);
  bool saveResult(String snapshotId, String resultJson);
  Future<Map<String, dynamic>> deleteEntries(
    List<String> targets, {
    bool dryRun = false,
    bool rescanAfterDelete = false,
  });
}

class ProductionAiAnalysisGateway implements AiAnalysisGateway {
  const ProductionAiAnalysisGateway({this.session});

  final VolwardSession? session;
  VolwardSession? get _session => session ?? VolwardSession.instance;

  @override
  Future<AiMode> getMode() => AiSettingsStore.instance.getMode();

  @override
  Future<AiProvider?> resolveProvider() =>
      AiSettingsStore.instance.resolveProvider();

  @override
  Future<bool> isPrivacyAccepted() =>
      AiSettingsStore.instance.isPrivacyAccepted();

  @override
  Future<void> setPrivacyAccepted(bool value) =>
      AiSettingsStore.instance.setPrivacyAccepted(value);

  @override
  Future<String?> buildCandidates(String snapshotId) async =>
      _session?.buildAiCandidatesJsonAsync(snapshotId);

  @override
  String? loadResult(String key) => _session?.loadAiResultJson(key);

  @override
  bool saveResult(String snapshotId, String resultJson) =>
      _session?.saveAiResultJson(snapshotId, resultJson) ?? false;

  @override
  Future<Map<String, dynamic>> deleteEntries(
    List<String> targets, {
    bool dryRun = false,
    bool rescanAfterDelete = false,
  }) {
    final current = _session;
    if (current == null) throw StateError('Native session unavailable');
    return current.deleteEntries(
      targets,
      dryRun: dryRun,
      rescanAfterDelete: rescanAfterDelete,
    );
  }
}
