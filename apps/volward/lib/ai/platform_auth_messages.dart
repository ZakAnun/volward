import '../l10n/generated/app_localizations.dart';

/// Maps platform auth / billing error codes to localized user-facing text.
String platformAuthErrorMessage(AppLocalizations l10n, Object error) {
  final code = _extractErrorCode(error);
  return switch (code) {
    'otp_resend_too_soon' => l10n.aiErrorOtpResendTooSoon,
    'otp_request_failed' => l10n.aiErrorOtpRequestFailed,
    'otp_verify_failed' => l10n.aiErrorOtpVerifyFailed,
    'device_register_failed' => l10n.aiErrorDeviceRegisterFailed,
    'session_expired' => l10n.aiSettingsSessionExpired,
    'link_account_required' => l10n.aiErrorLinkAccountRequired,
    'platform_api_unconfigured' => l10n.aiErrorPlatformApiUnconfigured,
    'device_not_found' => l10n.aiErrorDeviceNotFound,
    'refresh_rate_limited' => l10n.aiErrorRefreshRateLimited,
    'checkout_failed' => l10n.aiErrorCheckoutFailed,
    'packs_failed' => l10n.aiErrorPacksFailed,
    _ => l10n.aiErrorPlatformGeneric,
  };
}

String _extractErrorCode(Object error) {
  final text = error.toString();
  const exceptionPrefix = 'Exception: ';
  const statePrefix = 'Bad state: ';
  if (text.startsWith(exceptionPrefix)) {
    return text.substring(exceptionPrefix.length).split(':').first;
  }
  if (text.startsWith(statePrefix)) {
    return text.substring(statePrefix.length).split(':').first;
  }
  return text.split(':').first;
}
