import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:volward/ai/platform_auth_store.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/widgets/ai_purchase_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const baseUrl = 'https://example.test/v1';
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final storage = <String, String>{};

  const validToken = 'eyJhbGciOiJub25lIn0.eyJleHAiOjIwMDAwMDAwMDB9.sig';

  const packsJson = [
    {
      'id': 'starter',
      'credits': 50,
      'price_cny': 990,
      'label_en': 'Starter',
      'label_zh': '入门包',
    },
  ];

  late AppLocalizations l10n;

  void seedDeviceAndUser() {
    storage['volward_device_uuid'] = 'dev-uuid';
    storage['volward_device_token'] = 'device-token';
    storage['volward_platform_token'] = validToken;
  }

  setUp(() async {
    l10n = lookupAppLocalizations(const Locale('en'));
    storage.clear();
    seedDeviceAndUser();
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
    await PlatformAuthStore.instance.debugSetUserToken(validToken);
  });

  tearDown(() async {
    PlatformAuthStore.instance.configureForTest();
    await PlatformAuthStore.instance.debugSetUserToken(null);
    storage.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  http.Response _jsonResponse(Object body, {int status = 200}) {
    return http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }

  http.Client mockBillingClient({required String checkoutUrl}) {
    return MockClient((req) async {
      final path = req.url.path;
      if (path.contains('/billing/packs')) {
        return _jsonResponse(packsJson);
      }
      if (path.contains('/auth/me')) {
        return _jsonResponse({
          'user_id': 'u1',
          'email': 'user@example.com',
          'credits': 10,
        });
      }
      if (path.contains('/auth/refresh')) {
        return _jsonResponse({
          'token': validToken,
          'user_id': 'u1',
          'email': 'user@example.com',
          'credits': 10,
        });
      }
      if (path.contains('/billing/checkout')) {
        return _jsonResponse({'checkout_url': checkoutUrl});
      }
      if (path.contains('/ai/quota')) {
        return _jsonResponse({'credits_remaining': 10, 'credits_total': 10});
      }
      return http.Response('not found: ${req.url}', 404);
    });
  }

  Future<void> waitForPackList(WidgetTester tester) async {
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Starter').evaluate().isNotEmpty) return;
    }
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .whereType<String>()
        .toList();
    fail('Pack list did not load. Visible text: $texts');
  }

  Future<void> pumpDialog(
    WidgetTester tester, {
    required http.Client client,
  }) async {
    PlatformAuthStore.instance.configureForTest(
      baseUrl: baseUrl,
      client: client,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: buildVolwardTheme(brightness: Brightness.light),
        home: Builder(
          builder: (ctx) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showAiPurchaseDialog(ctx),
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await waitForPackList(tester);
  }

  test('mock client serves billing packs', () async {
    final client = mockBillingClient(
      checkoutUrl: 'https://sandbox-buy.paddle.com/checkout?_ptxn=x',
    );
    PlatformAuthStore.instance.configureForTest(
      baseUrl: baseUrl,
      client: client,
    );
    await PlatformAuthStore.instance.debugSetUserToken(validToken);

    final token = await PlatformAuthStore.instance.ensureDeviceRegistered();
    final res = await PlatformAuthStore.instance.httpClient.get(
      Uri.parse('$baseUrl/billing/packs'),
      headers: {'Authorization': 'Bearer $token'},
    );
    expect(res.statusCode, 200);
    expect(jsonDecode(res.body), packsJson);
  });

  testWidgets('rejects non-Paddle checkout URL', (tester) async {
    await pumpDialog(
      tester,
      client: mockBillingClient(
        checkoutUrl: 'https://www.volwardapp.com/pri_01abc',
      ),
    );

    await tester.tap(find.text('Starter'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text(l10n.aiErrorCheckoutUrlInvalid).evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text(l10n.aiErrorCheckoutUrlInvalid), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('shows browser button for valid Paddle URL', (tester) async {
    await pumpDialog(
      tester,
      client: mockBillingClient(
        checkoutUrl: 'https://sandbox-buy.paddle.com/checkout?_ptxn=x',
      ),
    );

    await tester.tap(find.text('Starter'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text(l10n.aiPurchaseOpenInBrowser).evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text(l10n.aiPurchaseOpenInBrowser), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('shows browser button for volwardapp pay URL', (tester) async {
    await pumpDialog(
      tester,
      client: mockBillingClient(
        checkoutUrl: 'https://volwardapp.com/pay/?_ptxn=txn_01abc',
      ),
    );

    await tester.tap(find.text('Starter'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text(l10n.aiPurchaseOpenInBrowser).evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text(l10n.aiPurchaseOpenInBrowser), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
  });
}
