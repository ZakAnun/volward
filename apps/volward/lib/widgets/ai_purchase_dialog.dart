import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/paddle_checkout_url.dart';
import '../ai/platform_ai_provider.dart';
import '../ai/platform_auth_messages.dart';
import '../ai/platform_auth_store.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../theme/volward_tokens.dart';

class AiPurchaseResult {
  const AiPurchaseResult({required this.packId, required this.credits});
  final String packId;
  final int credits;
}

/// Shows packs → checkout (browser + QR) → polls quota until balance increases.
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
  static const _packCardHeight = 72.0;
  static const _packCardSpacing = 8.0;
  static const _expectedPackCount = 4;

  List<_Pack> _packs = const [];
  String? _error;
  bool _loading = true;
  String? _checkoutUrl;
  _Pack? _selectedPack;
  int? _baselineCredits;
  bool _checkoutLoading = false;
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
      final token = await PlatformAuthStore.instance.ensureDeviceRegistered();
      final base = PlatformAuthStore.instance.baseUrl;
      final client = PlatformAuthStore.instance.httpClient;
      final res = await client
          .get(
            Uri.parse('$base/billing/packs'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw Exception('packs_failed:${res.statusCode}');
      }
      final list = (jsonDecode(res.body) as List)
          .whereType<Map>()
          .map((e) => _Pack.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      PlatformUser? user;
      try {
        user = await PlatformAuthStore.instance.restorePlatformUser();
      } catch (_) {
        user = await PlatformAuthStore.instance.currentUser();
      }
      if (!mounted) return;
      setState(() {
        _packs = list;
        _baselineCredits = user?.credits;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final l10n = context.l10n;
      setState(() {
        _error = platformAuthErrorMessage(l10n, e);
        _loading = false;
      });
    }
  }

  Future<void> _checkout(_Pack pack) async {
    setState(() {
      _error = null;
      _checkoutLoading = true;
    });
    try {
      final token = await PlatformAuthStore.instance.ensureUserToken();
      if (token == null) throw Exception('session_expired');
      final base = PlatformAuthStore.instance.baseUrl;
      final client = PlatformAuthStore.instance.httpClient;
      final res = await client
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
        final code = _parseApiErrorCode(res.body) ?? 'checkout_failed';
        throw Exception('$code:${res.statusCode}');
      }
      final url =
          (jsonDecode(res.body) as Map<String, dynamic>)['checkout_url']
              as String?;
      if (url == null || url.isEmpty) {
        throw Exception('checkout_failed:missing_url');
      }
      final uri = Uri.tryParse(url);
      if (uri == null || !isAllowedPaddleCheckoutUrl(uri)) {
        throw Exception('checkout_url_invalid');
      }
      if (!mounted) return;
      setState(() {
        _checkoutUrl = url;
        _selectedPack = pack;
        _checkoutLoading = false;
      });
      _startPoll(token);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = platformAuthErrorMessage(context.l10n, e);
        _checkoutLoading = false;
      });
    }
  }

  Future<void> _openCheckoutInBrowser() async {
    final url = _checkoutUrl;
    if (url == null) return;
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(() => _error = context.l10n.aiErrorCheckoutFailed);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.l10n.aiErrorCheckoutFailed);
    }
  }

  /// High-contrast QR plate: dark dialogs need a light background for scan reliability.
  Widget _buildCheckoutQrCode(BuildContext context, String data) {
    final theme = Theme.of(context);
    final tokens = context.volward;
    final isDark = theme.brightness == Brightness.dark;
    // Dark UI: light QR plate + dark modules for camera contrast and readability.
    final background = isDark
        ? const Color(0xFFFAFAFC)
        : theme.colorScheme.surface;
    final foreground = isDark ? Colors.black : tokens.ink;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: QrImageView(
          data: data,
          backgroundColor: background,
          eyeStyle: QrEyeStyle(color: foreground),
          dataModuleStyle: QrDataModuleStyle(color: foreground),
        ),
      ),
    );
  }

  String? _parseApiErrorCode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded['error'] as String?;
      }
    } catch (_) {}
    return null;
  }

  void _backToPacks() {
    _poll?.cancel();
    setState(() {
      _checkoutUrl = null;
      _selectedPack = null;
      _error = null;
    });
  }

  void _startPoll(String token) {
    _poll?.cancel();
    var tries = 0;
    const maxTries = 40;
    _poll = Timer.periodic(const Duration(seconds: 3), (t) async {
      tries++;
      try {
        final p = PlatformAiProvider(token: token);
        final q = await p.queryQuota();
        final base = _baselineCredits ?? 0;
        if (q != null &&
            q.creditsRemaining > base &&
            _selectedPack != null &&
            mounted) {
          t.cancel();
          Navigator.of(context).pop(
            AiPurchaseResult(
              packId: _selectedPack!.id,
              credits: _selectedPack!.credits,
            ),
          );
        }
      } catch (_) {}
      if (tries >= maxTries && t.isActive) {
        t.cancel();
        if (mounted) {
          setState(() => _error = context.l10n.aiPurchaseWaitingHint);
        }
      }
    });
  }

  double _packListHeight({required int packCount}) {
    final count = packCount > 0 ? packCount : _expectedPackCount;
    return count * (_packCardHeight + _packCardSpacing);
  }

  Widget _packCardShell({
    required ThemeData theme,
    required Widget child,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _packCardSpacing),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: _packCardHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPackCard(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    _Pack pack,
  ) {
    return _packCardShell(
      theme: theme,
      onTap: _checkoutLoading ? null : () => _checkout(pack),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pack.labelFor(context), style: theme.textTheme.titleSmall),
                Text(l10n.aiPurchasePackCredits(pack.credits)),
              ],
            ),
          ),
          Text(
            l10n.aiPurchasePriceCny((pack.priceCny / 100).toStringAsFixed(2)),
          ),
        ],
      ),
    );
  }

  Widget _buildPackSkeleton(ThemeData theme) {
    final placeholder = theme.colorScheme.onSurface.withValues(alpha: 0.08);
    return _packCardShell(
      theme: theme,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: 96,
                  decoration: BoxDecoration(
                    color: placeholder,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: 64,
                  decoration: BoxDecoration(
                    color: placeholder,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 14,
            width: 48,
            decoration: BoxDecoration(
              color: placeholder,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackListStep(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final packCount = _loading ? _expectedPackCount : _packs.length;
    final listHeight = _packListHeight(packCount: packCount);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
          ),
        SizedBox(
          height: listHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading)
                    for (var i = 0; i < _expectedPackCount; i++)
                      _buildPackSkeleton(theme)
                  else if (_packs.isEmpty && _error == null)
                    SizedBox(
                      height: listHeight,
                      child: Center(child: Text(l10n.aiPurchaseNoPacks)),
                    )
                  else
                    for (final pack in _packs)
                      _buildPackCard(context, theme, l10n, pack),
                ],
              ),
              if (_loading || _checkoutLoading)
                const CircularProgressIndicator(),
            ],
          ),
        ),
        if (!_loading && _packs.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(l10n.aiCoveragePurchaseFooter, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.aiSettingsBuyCredits),
      content: SizedBox(
        width: 360,
        child: _checkoutUrl == null
            ? _buildPackListStep(context, theme, l10n)
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    if (_selectedPack != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          l10n.aiPurchaseSelectedSummary(
                            _selectedPack!.labelFor(context),
                            _selectedPack!.credits,
                            (_selectedPack!.priceCny / 100).toStringAsFixed(2),
                          ),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    FilledButton(
                      onPressed: _openCheckoutInBrowser,
                      child: Text(l10n.aiPurchaseOpenInBrowser),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: SizedBox(
                        height: 160,
                        width: 160,
                        child: _buildCheckoutQrCode(context, _checkoutUrl!),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.aiPurchaseScanQrHint,
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.aiPurchasePayHint,
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      l10n.aiPurchaseWaitingPayment,
                      style: theme.textTheme.bodySmall,
                    ),
                    TextButton(
                      onPressed: _backToPacks,
                      child: Text(l10n.aiPurchaseBackToPacks),
                    ),
                  ],
                ),
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
    required this.labelEn,
    required this.labelZh,
  });
  final String id;
  final int credits;
  final int priceCny;
  final String labelEn;
  final String labelZh;

  String labelFor(BuildContext context) {
    final useZh = Localizations.localeOf(context).languageCode == 'zh';
    if (useZh) return labelZh;
    return labelEn.isNotEmpty ? labelEn : labelZh;
  }

  factory _Pack.fromJson(Map<String, dynamic> j) => _Pack(
    id: j['id'] as String,
    credits: (j['credits'] as num).toInt(),
    priceCny: (j['price_cny'] as num?)?.toInt() ?? 0,
    labelEn: (j['label_en'] ?? j['id'] ?? '') as String,
    labelZh: (j['label_zh'] ?? j['label_en'] ?? j['id']) as String,
  );
}
