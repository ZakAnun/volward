import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/widgets/scan_column_view.dart';

void main() {
  testWidgets('ScanColumnView folder tap invokes onSelect', (tester) async {
    ScanTreeNode? selected;

    final root = ScanTreeNode(
      name: 'root',
      path: '/root',
      isDirectory: true,
      children: [
        ScanTreeNode(
          name: 'Library',
          path: '/root/Library',
          isDirectory: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildVolwardTheme(brightness: Brightness.light),
        home: Scaffold(
          body: SizedBox(
            height: 240,
            width: 480,
            child: ScanColumnView(
              root: root,
              selectionChain: const [],
              onSelect: (_, node) => selected = node,
              formatBytes: (b) => '${b ?? 0} B',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Library'));
    await tester.pump();

    expect(selected?.path, '/root/Library');
  });

  testWidgets('ScanColumnView keeps selected folder highlighted', (tester) async {
    final root = ScanTreeNode(
      name: 'root',
      path: '/root',
      isDirectory: true,
      children: [
        ScanTreeNode(
          name: 'Library',
          path: '/root/Library',
          isDirectory: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildVolwardTheme(
          brightness: Brightness.light,
          accent: const Color(0xFF0066CC),
        ),
        home: Scaffold(
          body: SizedBox(
            height: 240,
            width: 480,
            child: ScanColumnView(
              root: root,
              selectionChain: [root.children.first],
              onSelect: (_, __) {},
              formatBytes: (b) => '${b ?? 0} B',
            ),
          ),
        ),
      ),
    );

    final selectedContainer = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text('Library'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );

    final decoration = selectedContainer.decoration! as BoxDecoration;
    expect(decoration.color, isNot(Colors.transparent));
    expect(decoration.color, isNot(Colors.white));
  });
}
