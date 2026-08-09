import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/snapshot_query.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/widgets/scan_column_view.dart';
import 'package:volward/widgets/scan_filter_bar.dart';

void main() {
  testWidgets('ScanColumnView renders a visible slice', (tester) async {
    final root = ScanTreeNode(name: 'root', path: '/root', isDirectory: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildVolwardTheme(brightness: Brightness.light),
        home: Scaffold(
          body: SizedBox(
            height: 240,
            width: 480,
            child: ScanColumnView(
              root: root,
              visibleChildren: const [
                SnapshotNodeRecord(
                  name: 'Visible folder',
                  path: '/root/visible',
                  isDirectory: true,
                  sizeBytes: 0,
                ),
              ],
              selectionChain: const [],
              onSelect: (_) {},
              formatBytes: (b) => '${b ?? 0} B',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Visible folder'), findsOneWidget);
  });

  testWidgets('ScanColumnView folder tap invokes onSelect', (tester) async {
    SnapshotNodeRecord? selected;

    final root = ScanTreeNode(
      name: 'root',
      path: '/root',
      isDirectory: true,
      children: [
        ScanTreeNode(name: 'Library', path: '/root/Library', isDirectory: true),
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
              onSelect: (tap) => selected = tap.node,
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

  testWidgets('ScanColumnView reports Command and Shift modifiers', (
    tester,
  ) async {
    ScanColumnTap? received;
    final root = ScanTreeNode(
      name: 'root',
      path: '/root',
      isDirectory: true,
      children: [
        ScanTreeNode(name: 'a', path: '/root/a', isDirectory: false),
        ScanTreeNode(name: 'b', path: '/root/b', isDirectory: false),
        ScanTreeNode(name: 'c', path: '/root/c', isDirectory: false),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            width: 480,
            child: ScanColumnView(
              root: root,
              selectionChain: const [],
              onSelect: (tap) => received = tap,
              formatBytes: (b) => '${b ?? 0} B',
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(find.text('a'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(received?.commandPressed, isTrue);
    expect(received?.shiftPressed, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('c'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(received?.shiftPressed, isTrue);
    expect(received?.columnItems.map((item) => item.path).toList(), [
      '/root/a',
      '/root/b',
      '/root/c',
    ]);
  });

  testWidgets('ScanColumnView keeps selected folder highlighted', (
    tester,
  ) async {
    final root = ScanTreeNode(
      name: 'root',
      path: '/root',
      isDirectory: true,
      children: [
        ScanTreeNode(name: 'Library', path: '/root/Library', isDirectory: true),
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
              onSelect: (_) {},
              formatBytes: (b) => '${b ?? 0} B',
            ),
          ),
        ),
      ),
    );

    final selectedContainer = tester.widget<ColoredBox>(
      find
          .ancestor(of: find.text('Library'), matching: find.byType(ColoredBox))
          .first,
    );

    expect(selectedContainer.color, isNot(Colors.transparent));
    expect(selectedContainer.color, isNot(Colors.white));
  });

  testWidgets(
    'ScanColumnView shows a static placeholder for idle unscanned folders',
    (tester) async {
      final root = ScanTreeNode(
        name: 'root',
        path: '/root',
        isDirectory: true,
        children: [
          ScanTreeNode(
            name: 'Pending',
            path: '/root/Pending',
            isDirectory: true,
            scanned: false,
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
                onSelect: (_) {},
                formatBytes: (b) => '${b ?? 0} B',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    },
  );

  testWidgets('ScanColumnView animates only the actively peeking folder', (
    tester,
  ) async {
    final root = ScanTreeNode(
      name: 'root',
      path: '/root',
      isDirectory: true,
      children: [
        ScanTreeNode(
          name: 'Pending',
          path: '/root/Pending',
          isDirectory: true,
          scanned: false,
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
              onSelect: (_) {},
              formatBytes: (b) => '${b ?? 0} B',
              peekInFlight: const {'/root/Pending'},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
  });

  testWidgets(
    'ScanColumnView keeps folder interaction stable across rebuilds',
    (tester) async {
      var selected = 0;
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

      Widget buildView() => MaterialApp(
        home: Scaffold(
          body: ScanColumnView(
            root: root,
            selectionChain: const [],
            onSelect: (_) => selected++,
            formatBytes: (bytes) => '${bytes ?? 0} B',
          ),
        ),
      );

      await tester.pumpWidget(buildView());
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.text('Library'));
        await tester.pumpWidget(buildView());
      }

      expect(selected, 10);
      expect(find.text('Library'), findsOneWidget);
    },
  );

  testWidgets('ScanColumnView preserves catalog-provided slice order', (
    tester,
  ) async {
    final root = ScanTreeNode(name: 'root', path: '/root', isDirectory: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildVolwardTheme(brightness: Brightness.light),
        home: Scaffold(
          body: SizedBox(
            height: 240,
            width: 480,
            child: ScanColumnView(
              root: root,
              visibleChildren: const [
                SnapshotNodeRecord(
                  name: 'Small first',
                  path: '/root/small',
                  isDirectory: true,
                  sizeBytes: 1,
                ),
                SnapshotNodeRecord(
                  name: 'Large second',
                  path: '/root/large',
                  isDirectory: true,
                  sizeBytes: 1000,
                ),
              ],
              childrenPreSorted: true,
              selectionChain: const [],
              onSelect: (_) {},
              formatBytes: (b) => '${b ?? 0} B',
              sortMode: ScanSortMode.sizeDesc,
            ),
          ),
        ),
      ),
    );

    final smallTop = tester.getTopLeft(find.text('Small first')).dy;
    final largeTop = tester.getTopLeft(find.text('Large second')).dy;
    expect(smallTop, lessThan(largeTop));
  });
}
