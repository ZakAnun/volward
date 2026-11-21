import '../../../ai/coverage_job_state.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Localization strings and UI effects the workspace controller needs, owned by
/// the presentation layer so controllers never touch [BuildContext].
abstract interface class AiAnalysisWorkspaceMessages {
  AppLocalizations get l10n;

  /// Resolves the localized failure reason for a paused coverage job.
  String coverageFailedReason(
    CoveragePauseDetail? detail, {
    String? pauseMessage,
  });

  Future<bool> confirmPrivacy();

  Future<bool> confirmLegacyResume();

  Future<bool> confirmFailedResume(CoverageJobState state);

  Future<bool> confirmRestartFull();

  /// Returns true when the user chose to restart from the billing-mode dialog.
  Future<bool> confirmBillingModeMismatch(CoverageJobState job);

  /// Returns the parsed new budget, or null when cancelled or invalid.
  Future<int?> promptCoverageBudget({
    required bool isTokenBudget,
    required int suggested,
  });

  Future<bool> confirmDelete({required int count, required String freedLabel});

  void toastCoverageBusyOtherSnapshot();

  void toastCoverageBudgetInvalid();
}
