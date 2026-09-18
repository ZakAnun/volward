import '../l10n/generated/app_localizations.dart';
import 'coverage_job_state.dart';

/// Localized failure category for [CoveragePauseReason.failed] (design §4.4).
String coverageFailedReasonCategory(
  AppLocalizations l10n,
  CoveragePauseDetail? detail,
) {
  return switch (detail) {
    CoveragePauseDetail.parse => l10n.aiCoverageFailedReasonParse,
    CoveragePauseDetail.network => l10n.aiCoverageFailedReasonNetwork,
    CoveragePauseDetail.api => l10n.aiCoverageFailedReasonApi,
    null => l10n.aiCoverageFailedReasonGeneric,
  };
}
