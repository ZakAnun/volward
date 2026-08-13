import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/platform_ai_provider.dart';
import '../ai/platform_auth_store.dart';
import '../l10n/l10n.dart';
import 'dart:convert';

class AiPurchaseResult {
  const AiPurchaseResult({required this.packId, required this.credits});
  final String packId;
  final int credits;
}

/// Shows packs → checkout QR → polls quota until balance increases.
Future<AiPurchaseResult?> showAiPurchaseDialog(BuildContext context) {
  return showDialog<AiPurchaseResult>(
    context: context,
    builder: (ctx) => const _AiPurchaseDialog(),
  );
}

class _AiPurchaseDialog extends StatefulWidget {
  const _AiPurchaseDialog();

  @override
  State<_AiPurchaseDialog> createState() => _AiPurchaseDialogState();
}

class _AiPurchaseDialogState extends State<_AiPurchaseDialog> {
  List<_Pack> _packs = const [];
  String? _error;
  bool _loading = true;
  String? _checkoutUrl;
  String? _selectedPackId;
  int? _selectedCredits;
  int? _baselineCredits;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final token =
          await PlatformAuthStore.instance.ensureDeviceRegistered();
      const base = PlatformAuthStore.defaultBaseUrl;
      final res = await http.get(
        Uri.parse('$base/billing/packs'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw Exception('packs_failed:${res.statusCode}');
      }
      final list = (jsonDecode(res.body) as List)
          .whereType<Map>()
          .map((e) => _Pack.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final user = await PlatformAuthStore.instance.currentUser();
      if (!mounted) return;
      setState(() {
        _packs = list;
        _baselineCredits = user?.credits;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _checkout(_Pack pack) async {
    setState(() {
      _error = null;
      _selectedPackId = pack.id;
      _selectedCredits = pack.credits;
    });
    try {
      final token = await PlatformAuthStore.instance.userToken();
      if (token == null) throw Exception('session_expired');
      const base = PlatformAuthStore.defaultBaseUrl;
      final res = await http
          .post(
            Uri.parse('$base/billing/checkout'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'pack_id': pack.id}),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw Exception('checkout_failed:${res.statusCode}');
      }
      final url =
          (jsonDecode(res.body) as Map<String, dynamic>)['checkout_url']
              as String?;
      if (url == null || url.isEmpty) {
        throw Exception('checkout_failed:missing_url');
      }
      if (!mounted) return;
      setState(() => _checkoutUrl = url);
      _startPoll(token);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _startPoll(String token) {
    _poll?.cancel();
    var tries = 0;
    _poll = Timer.periodic(const Duration(seconds: 3), (t) async {
      tries++;
      if (tries > 10) {
        t.cancel();
        return;
      }
      try {
        final p = PlatformAiProvider(token: token);
        final q = await p.queryQuota();
        final base = _baselineCredits ?? 0;
        if (q != null &&
            q.creditsRemaining > base &&
            _selectedPackId != null &&
            mounted) {
          t.cancel();
          Navigator.of(context).pop(
            AiPurchaseResult(
              packId: _selectedPackId!,
              credits: _selectedCredits ?? (q.creditsRemaining - base),
            ),
          );
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.aiSettingsBuyCredits),
      content: SizedBox(
        width: 360,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                  if (_checkoutUrl == null) ...[
                    for (final pack in _packs)
                      ListTile(
                        title: Text(pack.label),
                        subtitle: Text('${pack.credits} credits'),
                        trailing: Text('¥${(pack.priceCny / 100).toStringAsFixed(2)}'),
                        onTap: () => _checkout(pack),
                      ),
                    if (_packs.isEmpty && _error == null)
                      const Text('No packs available'),
                  ] else ...[
                    SizedBox(
                      height: 200,
                      width: 200,
                      child: QrImageView(data: _checkoutUrl!),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => launchUrl(Uri.parse(_checkoutUrl!)),
                      child: const Text('Open in browser'),
                    ),
                    const Text('Waiting for payment…'),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.scanActionCancel),
        ),
      ],
    );
  }
}

class _Pack {
  const _Pack({
    required this.id,
    required this.credits,
    required this.priceCny,
    required this.label,
  });
  final String id;
  final int credits;
  final int priceCny;
  final String label;

  factory _Pack.fromJson(Map<String, dynamic> j) => _Pack(
        id: j['id'] as String,
        credits: (j['credits'] as num).toInt(),
        priceCny: (j['price_cny'] as num?)?.toInt() ?? 0,
        label: (j['label_zh'] ?? j['label_en'] ?? j['id']) as String,
      );
}
