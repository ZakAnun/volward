import '../../../ai/coverage_job_state.dart';
import '../../../ai/coverage_pause_messages.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/generated/app_localizations_en.dart';
import 'ai_analysis_workspace_messages.dart';

/// Context-free fallback messages used when no presenter adapter supplies
/// localized UI effects.
final class AiAnalysisWorkspaceFallbackMessages
    implements AiAnalysisWorkspaceMessages {
  const AiAnalysisWorkspaceFallbackMessages();

  @override
  AppLocalizations get l10n => AppLocalizationsEn();

  @override
  String coverageFailedReason(
    CoveragePauseDetail? detail, {
    String? pauseMessage,
  }) {
    return coverageFailedReasonCategory(
      l10n,
      detail,
      pauseMessage: pauseMessage,
    );
  }

  @override
  Future<bool> confirmPrivacy() async => true;

  @override
  Future<bool> confirmLegacyResume() async => true;

  @override
  Future<bool> confirmFailedResume(CoverageJobState state) async => true;

  @override
  Future<bool> confirmRestartFull() async => true;

  @override
  Future<bool> confirmBillingModeMismatch(CoverageJobState job) async => true;

  @override
  Future<int?> promptCoverageBudget({
    required bool isTokenBudget,
    required int suggested,
  }) async => suggested;

  @override
  Future<bool> confirmDelete({
    required int count,
    required String freedLabel,
  }) async => true;

  @override
  void toastCoverageBusyOtherSnapshot() {}

  @override
  void toastCoverageBudgetInvalid() {}
}
