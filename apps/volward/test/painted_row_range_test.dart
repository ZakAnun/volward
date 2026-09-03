import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/widgets/scan_column_view.dart';

Finder _paintedColumn() {
  return find.byWidgetPredicate(
    (w) =>
        w is CustomPaint &&
        w.painter.runtimeType.toString() == '_FinderColumnPainter',
  );
}

CustomPainter _columnPainter(WidgetTester tester) {
  return tester.widget<CustomPaint>(_paintedColumn()).painter!;
}

void main() {
  test('paintedRowRange covers only rows overlapping the viewport', () {
    final range = paintedRowRange(
      offset: 280,
      viewportHeight: 280,
      itemCount: 400,
    );
    expect(range.first, 9);
    expect(range.last, greaterThan(range.first));
    expect(range.last, lessThanOrEqualTo(400));
  });

  test('paintedRowRange is stable for sub-pixel scroll within the same rows', () {
    final a = paintedRowRange(offset: 280.0, viewportHeight: 280, itemCount: 400);
    final b = paintedRowRange(offset: 280.4, viewportHeight: 280, itemCount: 400);
    expect(b.first, a.first);
    expect(b.last, a.last);
  });

  testWidgets(
    'shouldRepaint is true when the painted column first/last range changes',
    (tester) async {
      final root = ScanTreeNode(
        name: 'root',
        path: '/root',
        isDirectory: true,
        children: List.generate(
          300,
          (i) => ScanTreeNode(
            name: 'file_$i.txt',
            path: '/root/file_$i.txt',
            isDirectory: false,
            sizeBytes: 1024,
          ),
        ),
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
                selectionChain: [root.children.first],
                onSelect: (_) {},
                formatBytes: (b) => '${b ?? 0} B',
              ),
            ),
          ),
        ),
      );

      final oldPainter = _columnPainter(tester);
      final scrollable = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      );
      tester.state<ScrollableState>(scrollable).position.jumpTo(560);
      await tester.pump();

      final newPainter = _columnPainter(tester);
      expect(
        newPainter.shouldRepaint(oldPainter),
        isTrue,
        reason: 'visible first/last must participate in shouldRepaint so '
            'CustomPaint markNeedsPaint after a range-changing scroll',
      );
    },
  );
}
