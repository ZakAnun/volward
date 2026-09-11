import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/platform_auth_messages.dart';
import '../ai/platform_auth_store.dart';
import '../analytics/analytics.dart';
import '../analytics/analytics_events.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';
import 'apple_widgets.dart';

enum _LinkStep { collapsed, email, otp }

/// Inline email + OTP linking form for platform settings.
class PlatformLinkEmailSection extends StatefulWidget {
  const PlatformLinkEmailSection({
    super.key,
    required this.onLinked,
    required this.onError,
  });

  final ValueChanged<PlatformUser> onLinked;
  final ValueChanged<String> onError;

  @override
  State<PlatformLinkEmailSection> createState() =>
      _PlatformLinkEmailSectionState();
}

class _PlatformLinkEmailSectionState extends State<PlatformLinkEmailSection> {
  _LinkStep _step = _LinkStep.collapsed;
  bool _busy = false;
  String _email = '';
  int _resendSeconds = 0;
  Timer? _resendTimer;

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String hint,
  }) {
    final v = context.volward;
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: v.surfacePearl,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        borderSide: BorderSide(color: v.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        borderSide: BorderSide(color: v.hairline),
      ),
    );
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  Future<void> _sendOtp() async {
    final l10n = context.l10n;
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      widget.onError(l10n.aiSettingsInvalidEmail);
      return;
    }

    setState(() {
      _busy = true;
      _email = email;
    });
    try {
      await PlatformAuthStore.instance.ensureDeviceRegistered();
      await PlatformAuthStore.instance.requestOtp(email);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _LinkStep.otp;
      });
      _startResendCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onError(platformAuthErrorMessage(l10n, e));
    }
  }

  Future<void> _verifyOtp() async {
    final l10n = context.l10n;
    final code = _otpController.text.trim();
    if (code.length != 6) {
      widget.onError(l10n.aiErrorOtpVerifyFailed);
      return;
    }

    setState(() => _busy = true);
    try {
      final user = await PlatformAuthStore.instance.verifyOtp(_email, code);
      unawaited(
        Analytics.instance.track(AnalyticsEvents.aiAccountLinked, {
          'provider': 'platform',
        }),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onLinked(user);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onError(platformAuthErrorMessage(l10n, e));
    }
  }

  Widget _busyIndicator() {
    if (!_busy) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(top: AppleSpacing.xs),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildCollapsed(AppLocalizations l10n) {
    return AppleButton(
      label: l10n.aiSettingsLinkEmail,
      onPressed: _busy ? null : () => setState(() => _step = _LinkStep.email),
    );
  }

  Widget _buildEmailStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          enabled: !_busy,
          decoration: _fieldDecoration(
            context,
            hint: l10n.aiSettingsEnterEmail,
          ),
        ),
        const SizedBox(height: AppleSpacing.sm),
        AppleButton(
          label: l10n.aiSettingsSendOtp,
          onPressed: _busy ? null : () => unawaited(_sendOtp()),
        ),
        _busyIndicator(),
      ],
    );
  }

  Widget _buildOtpStep(AppLocalizations l10n) {
    final canResend = !_busy && _resendSeconds == 0;
    final resendLabel = _resendSeconds > 0
        ? l10n.aiSettingsResendCooldown(_resendSeconds)
        : l10n.aiSettingsResendOtp;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          enabled: !_busy,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _fieldDecoration(context, hint: l10n.aiSettingsEnterOtp),
        ),
        const SizedBox(height: AppleSpacing.sm),
        AppleButton(
          label: l10n.aiSettingsVerifyOtp,
          onPressed: _busy ? null : () => unawaited(_verifyOtp()),
        ),
        const SizedBox(height: AppleSpacing.xs),
        AppleButton(
          label: resendLabel,
          variant: AppleButtonVariant.pearl,
          onPressed: canResend ? () => unawaited(_sendOtp()) : null,
        ),
        _busyIndicator(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: switch (_step) {
        _LinkStep.collapsed => _buildCollapsed(l10n),
        _LinkStep.email => _buildEmailStep(l10n),
        _LinkStep.otp => _buildOtpStep(l10n),
      },
    );
  }
}
