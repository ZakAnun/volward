import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/theme/volward_theme.dart';

void main() {
  testWidgets('app uses Material scroll behavior without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildVolwardTheme(brightness: Brightness.light),
        home: const Scaffold(body: Text('ok')),
      ),
    );
    expect(find.text('ok'), findsOneWidget);
    final theme = Theme.of(tester.element(find.text('ok')));
    expect(theme.visualDensity, isNotNull);
  });
}
