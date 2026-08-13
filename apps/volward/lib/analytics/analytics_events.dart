/// Canonical event names for Aptabase product analytics.
abstract final class AnalyticsEvents {
  static const appOpen = 'app_open';
  static const scanStarted = 'scan_started';
  static const scanCompleted = 'scan_completed';
  static const refreshTriggered = 'refresh_triggered';
  static const scanRootSelected = 'scan_root_selected';
  static const moveToTrash = 'move_to_trash';
  static const emptyTrash = 'empty_trash';

  static const aiAnalysisStarted = 'ai_analysis_started';
  static const aiAnalysisCompleted = 'ai_analysis_completed';
  static const aiAnalysisFailed = 'ai_analysis_failed';
  static const aiDeletionConfirmed = 'ai_deletion_confirmed';
  static const aiModeChanged = 'ai_mode_changed';
  static const aiAccountLinked = 'ai_account_linked';
  static const aiCreditsPurchased = 'ai_credits_purchased';
}
