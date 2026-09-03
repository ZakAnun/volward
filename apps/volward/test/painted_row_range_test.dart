import 'package:flutter_test/flutter_test.dart';
import 'package:volward/widgets/scan_column_view.dart';

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
}
