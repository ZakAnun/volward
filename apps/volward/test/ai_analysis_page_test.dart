import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai_analysis_page.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/theme/volward_theme.dart';

void main() {
  group('AiCandidate / AiVerdict fromJson', () {
    test('AiCandidate round-trip via fromJson/toJson', () {
      final raw = {
        'path': '/Users/x/Projects/old-app/node_modules',
        'size_bytes': 47185920,
        'is_dir': true,
        'child_count': 2847,
        'extension': null,
      };
      final c = AiCandidate.fromJson(raw);
      expect(c.path, raw['path']);
      expect(c.sizeBytes, 47185920);
      expect(c.isDir, isTrue);
      expect(c.childCount, 2847);
      expect(c.extension, isNull);

      final encoded = c.toJson();
      expect(encoded['path'], c.path);
      expect(encoded['size_bytes'], c.sizeBytes);
      expect(encoded['is_dir'], isTrue);
      expect(encoded['child_count'], 2847);
      expect(encoded.containsKey('extension'), isFalse);

      final again = AiCandidate.fromJson(encoded);
      expect(again.path, c.path);
      expect(again.sizeBytes, c.sizeBytes);
      expect(again.isDir, c.isDir);
      expect(again.childCount, c.childCount);
    });

    test('AiCandidate fromJson with extension', () {
      final c = AiCandidate.fromJson({
        'path': '/tmp/foo.xyz',
        'size_bytes': 12,
        'is_dir': false,
        'extension': '.xyz',
      });
      expect(c.extension, '.xyz');
      expect(c.toJson()['extension'], '.xyz');
    });

    test('AiVerdict fromJson', () {
      final v = AiVerdict.fromJson({
        'path': '/Users/x/weird.cache',
        'verdict': 'safe_to_remove',
        'confidence': 'high',
        'reason': 'build cache',
      });
      expect(v.path, '/Users/x/weird.cache');
      expect(v.verdict, 'safe_to_remove');
      expect(v.confidence, 'high');
      expect(v.reason, 'build cache');
    });
  });

  testWidgets('AiAnalysisPage smoke construct', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: buildVolwardTheme(brightness: Brightness.light),
        home: const AiAnalysisPage(snapshotId: 'test-snap-id'),
      ),
    );
    // First frame: loading (or error if session unavailable).
    await tester.pump();
    expect(find.byType(AiAnalysisPage), findsOneWidget);
    expect(find.text('AI Disk Analysis'), findsOneWidget);
  });
}
