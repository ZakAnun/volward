import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:volward/ai/platform_auth_store.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/widgets/platform_link_email_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const baseUrl = 'https://example.test/v1';
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final storage = <String, String>{};

  const validToken = 'eyJhbGciOiJub25lIn0.eyJleHAiOjIwMDAwMDAwMDB9.sig';

  late AppLocalizations l10n;
  String? lastError;
  PlatformUser? linkedUser;

  void seedRegisteredDevice() {
    storage['volward_device_uuid'] = 'dev-uuid';
    storage['volward_device_token'] = 'device-token';
  }

  setUp(() async {
    l10n = lookupAppLocalizations(const Locale('en'));
    lastError = null;
    linkedUser = null;
    storage.clear();
    seedRegisteredDevice();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map;
          final key = args['key'] as String;
          switch (call.method) {
            case 'read':
              return storage[key];
            case 'write':
              storage[key] = args['value'] as String;
              return null;
            case 'delete':
              storage.remove(key);
              return null;
            default:
              return null;
          }
        });
    PlatformAuthStore.instance.configureForTest(baseUrl: baseUrl);
    await PlatformAuthStore.instance.debugSetUserToken(null);
  });

  tearDown(() async {
    PlatformAuthStore.instance.configureForTest();
    await PlatformAuthStore.instance.debugSetUserToken(null);
    storage.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  http.Client mockAuthClient() {
    return MockClient((req) async {
      final path = req.url.path;
      if (path.endsWith('/auth/request-otp')) {
        return http.Response('', 200);
      }
      if (path.endsWith('/auth/verify-otp')) {
        return http.Response(
          jsonEncode({
            'token': validToken,
            'user_id': 'u1',
            'email': 'user@example.com',
            'credits': 3,
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });
  }

  Future<void> pumpSection(WidgetTester tester, {http.Client? client}) async {
    PlatformAuthStore.instance.configureForTest(
      baseUrl: baseUrl,
      client: client ?? mockAuthClient(),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: buildVolwardTheme(brightness: Brightness.light),
        home: Scaffold(
          body: PlatformLinkEmailSection(
            onLinked: (user) => linkedUser = user,
            onError: (msg) => lastError = msg,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> expandEmailForm(WidgetTester tester) async {
    await tester.tap(find.text(l10n.aiSettingsLinkEmail));
    await tester.pumpAndSettle();
  }

  /// Wait for async auth calls; avoid pumpAndSettle (60s resend timer).
  Future<void> waitForOtpStep(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text(l10n.aiSettingsVerifyOtp).evaluate().isNotEmpty ||
          lastError != null) {
        return;
      }
    }
  }

  Future<void> waitForLinked(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (linkedUser != null || lastError != null) {
        return;
      }
    }
  }

  testWidgets('rejects empty email before sending OTP', (tester) async {
    await pumpSection(tester);
    await expandEmailForm(tester);

    await tester.tap(find.text(l10n.aiSettingsSendOtp));
    await tester.pumpAndSettle();

    expect(lastError, l10n.aiSettingsInvalidEmail);
    expect(find.text(l10n.aiSettingsVerifyOtp), findsNothing);
  });

  testWidgets('sends OTP and switches to OTP step', (tester) async {
    await pumpSection(tester);
    await expandEmailForm(tester);

    await tester.enterText(find.byType(TextField), 'user@example.com');
    await tester.tap(find.text(l10n.aiSettingsSendOtp));
    await waitForOtpStep(tester);

    expect(lastError, isNull);
    expect(find.text(l10n.aiSettingsVerifyOtp), findsOneWidget);
    expect(find.text(l10n.aiSettingsResendCooldown(60)), findsOneWidget);
  });

  testWidgets('verify success invokes onLinked', (tester) async {
    await pumpSection(tester);
    await expandEmailForm(tester);

    await tester.enterText(find.byType(TextField), 'user@example.com');
    await tester.tap(find.text(l10n.aiSettingsSendOtp));
    await waitForOtpStep(tester);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text(l10n.aiSettingsVerifyOtp));
    await waitForLinked(tester);

    expect(lastError, isNull);
    expect(linkedUser, isNotNull);
    expect(linkedUser!.email, 'user@example.com');
    expect(linkedUser!.credits, 3);
  });
}
