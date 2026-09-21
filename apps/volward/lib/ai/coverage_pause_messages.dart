import '../l10n/generated/app_localizations.dart';
import 'coverage_job_state.dart';

/// Localized failure category for [CoveragePauseReason.failed] (design §4.4).
String coverageFailedReasonCategory(
  AppLocalizations l10n,
  CoveragePauseDetail? detail, {
  String? pauseMessage,
}) {
  if (detail == null &&
      pauseMessage != null &&
      pauseMessage.trim().isNotEmpty) {
    return _humanizePauseMessage(pauseMessage.trim());
  }
  return switch (detail) {
    CoveragePauseDetail.parse => l10n.aiCoverageFailedReasonParse,
    CoveragePauseDetail.network => l10n.aiCoverageFailedReasonNetwork,
    CoveragePauseDetail.api => l10n.aiCoverageFailedReasonApi,
    null => l10n.aiCoverageFailedReasonGeneric,
  };
}

String _humanizePauseMessage(String message) {
  var text = message.startsWith('error:') ? message.substring(6) : message;
  if (text.length > 160) {
    text = '${text.substring(0, 160)}…';
  }
  return text;
}

String formatFailedBatchPathPreview(AppLocalizations l10n, List<String> paths) {
  const maxShown = 3;
  if (paths.isEmpty) return '';
  final head = paths.take(maxShown).join(', ');
  if (paths.length <= maxShown) {
    return l10n.aiCoverageFailedBatchPathsPreview(head);
  }
  return '${l10n.aiCoverageFailedBatchPathsPreview(head)} '
      '${l10n.aiCoverageFailedBatchPathsOverflow(paths.length - maxShown)}';
}
