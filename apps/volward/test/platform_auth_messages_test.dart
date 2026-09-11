import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/platform_auth_messages.dart';
import 'package:volward/l10n/generated/app_localizations.dart';

void main() {
  late AppLocalizations l10n;

  setUp(() {
    l10n = lookupAppLocalizations(const Locale('en'));
  });

  test('maps otp_resend_too_soon', () {
    expect(
      platformAuthErrorMessage(l10n, Exception('otp_resend_too_soon')),
      l10n.aiErrorOtpResendTooSoon,
    );
  });

  test('maps otp_request_failed with status suffix', () {
    expect(
      platformAuthErrorMessage(l10n, Exception('otp_request_failed:500')),
      l10n.aiErrorOtpRequestFailed,
    );
  });

  test('maps otp_verify_failed', () {
    expect(
      platformAuthErrorMessage(l10n, Exception('otp_verify_failed:401')),
      l10n.aiErrorOtpVerifyFailed,
    );
  });

  test('maps device_register_failed', () {
    expect(
      platformAuthErrorMessage(l10n, Exception('device_register_failed:503')),
      l10n.aiErrorDeviceRegisterFailed,
    );
  });

  test('maps session_expired', () {
    expect(
      platformAuthErrorMessage(l10n, Exception('session_expired')),
      l10n.aiSettingsSessionExpired,
    );
  });

  test('maps link_account_required', () {
    expect(
      platformAuthErrorMessage(l10n, Exception('link_account_required')),
      l10n.aiErrorLinkAccountRequired,
    );
  });

  test('maps platform_api_unconfigured from StateError', () {
    expect(
      platformAuthErrorMessage(l10n, StateError('platform_api_unconfigured')),
      l10n.aiErrorPlatformApiUnconfigured,
    );
  });

  test('maps device_not_found', () {
    expect(
      platformAuthErrorMessage(l10n, Exception('device_not_found')),
      l10n.aiErrorDeviceNotFound,
    );
  });

  test('maps refresh_rate_limited', () {
    expect(
      platformAuthErrorMessage(l10n, Exception('refresh_rate_limited')),
      l10n.aiErrorRefreshRateLimited,
    );
  });

  test('maps checkout_failed', () {
    expect(
      platformAuthErrorMessage(l10n, Exception('checkout_failed:502')),
      l10n.aiErrorCheckoutFailed,
    );
  });

  test('maps packs_failed', () {
    expect(
      platformAuthErrorMessage(l10n, Exception('packs_failed:404')),
      l10n.aiErrorPacksFailed,
    );
  });

  test('maps unknown codes to generic message', () {
    expect(
      platformAuthErrorMessage(l10n, Exception('totally_unknown')),
      l10n.aiErrorPlatformGeneric,
    );
  });
}
