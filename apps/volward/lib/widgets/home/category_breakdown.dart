import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../../storage_home_summary.dart';
import '../../theme/volward_tokens.dart';
import 'dashboard_theme.dart';

class CategoryBreakdown extends StatelessWidget {
  const CategoryBreakdown({
    super.key,
    required this.categories,
    required this.enabled,
    required this.onSelectCategory,
  });

  static const pieKey = Key('storage-overview-category-pie');

  /// Narrowest legend column that still fits a row's widest realistic content:
  /// an ellipsised label, a seven-digit file count, and a percent. Below this
  /// the two-column split costs more than the vertical space it saves, so the
  /// legend stacks instead.
  static const _minLegendColumnWidth = 176.0;

  /// Gap between the two legend columns.
  static const _columnGap = 8.0;

  final List<StorageHomeCategorySummary> categories;
  final bool enabled;
  final ValueChanged<String>? onSelectCategory;

  @override
  Widget build(BuildContext context) {
    final total = categories.fold<int>(0, (sum, item) => sum + item.count);
    final slices = <PieSlice>[
      for (final category in categories)
        PieSlice(
          color: categoryColor(category.name),
          fraction: total == 0 ? 0 : category.count / total,
        ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CustomPaint(
          key: CategoryBreakdown.pieKey,
          size: const Size.square(72),
          painter: CategoryPiePainter(slices: slices),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Two columns save vertical space once there are 4+ categories,
              // but only where each column is still wide enough to hold a row.
              // Splitting unconditionally overflowed by up to 102px in the
              // compact dashboard.
              final useTwoColumns =
                  categories.length >= 4 &&
                  (constraints.maxWidth - _columnGap) / 2 >=
                      _minLegendColumnWidth;
              return useTwoColumns
                  ? _buildTwoColumnLegend(total)
                  : _buildSingleColumnLegend(total);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSingleColumnLegend(int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < categories.length; i++)
          CategoryLegendRow(
            category: categories[i],
            color: categoryColor(categories[i].name),
            percentLabel: percentLabel(categories[i].count, total),
            enabled: enabled,
            onSelect:
                !enabled ||
                    onSelectCategory == null ||
                    categories[i].name == homeOtherCategoryName
                ? null
                : () => onSelectCategory!(categories[i].name),
          ),
      ],
    );
  }

  Widget _buildTwoColumnLegend(int total) {
    final leftCount = (categories.length / 2).ceil();
    final leftCategories = categories.take(leftCount).toList();
    final rightCategories = categories.skip(leftCount).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final category in leftCategories)
                CategoryLegendRow(
                  category: category,
                  color: categoryColor(category.name),
                  percentLabel: percentLabel(category.count, total),
                  enabled: enabled,
                  onSelect:
                      !enabled ||
                          onSelectCategory == null ||
                          category.name == homeOtherCategoryName
                      ? null
                      : () => onSelectCategory!(category.name),
                ),
            ],
          ),
        ),
        const SizedBox(width: _columnGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final category in rightCategories)
                CategoryLegendRow(
                  category: category,
                  color: categoryColor(category.name),
                  percentLabel: percentLabel(category.count, total),
                  enabled: enabled,
                  onSelect:
                      !enabled ||
                          onSelectCategory == null ||
                          category.name == homeOtherCategoryName
                      ? null
                      : () => onSelectCategory!(category.name),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class PieSlice {
  const PieSlice({required this.color, required this.fraction});

  final Color color;
  final double fraction;
}

class CategoryPiePainter extends CustomPainter {
  const CategoryPiePainter({required this.slices});

  final List<PieSlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final outer = Rect.fromCircle(center: center, radius: radius);
    final inner = Rect.fromCircle(center: center, radius: radius * 0.56);
    var start = -math.pi / 2;
    final gap = slices.length > 1 ? 0.07 : 0.0;
    for (final slice in slices) {
      final sweep = slice.fraction * 2 * math.pi;
      final padded = math.max(0.0, sweep - gap);
      if (padded > 0) {
        final from = start + gap / 2;
        final path = Path()
          ..arcTo(outer, from, padded, true)
          ..arcTo(inner, from + padded, -padded, false)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..color = slice.color
            ..isAntiAlias = true
            ..style = PaintingStyle.fill,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant CategoryPiePainter oldDelegate) {
    if (oldDelegate.slices.length != slices.length) return true;
    for (var i = 0; i < slices.length; i++) {
      final next = slices[i];
      final previous = oldDelegate.slices[i];
      if (next.color != previous.color || next.fraction != previous.fraction) {
        return true;
      }
    }
    return false;
  }
}

class CategoryLegendRow extends StatelessWidget {
  const CategoryLegendRow({
    super.key,
    required this.category,
    required this.color,
    required this.percentLabel,
    required this.enabled,
    required this.onSelect,
  });

  final StorageHomeCategorySummary category;
  final Color color;
  final String percentLabel;
  final bool enabled;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final label = localizedCategory(context, category.name);
    final count = NumberFormat.decimalPattern(locale).format(category.count);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: enabled ? null : () {},
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('storage-category-${category.name}'),
          onTap: enabled ? onSelect : null,
          borderRadius: BorderRadius.circular(8),
          child: Semantics(
            button: true,
            enabled: enabled,
            label: label,
            value: '$count · $percentLabel',
            onTap: enabled ? onSelect : null,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: enabled ? 1 : 0.42),
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 8, height: 8),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.vwFinePrint.copyWith(
                            color: dashboardOn(context).withValues(
                              alpha: enabled ? 0.84 : 0.42,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // The label ellipsises to nothing, but the numbers do
                      // not — a seven-digit count on a narrow column pushed
                      // the row past its width. Cap the pair at half the row
                      // so the count is the thing that gives, and only once
                      // the label has already collapsed.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth / 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                count,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: context.vwFinePrint.copyWith(
                                  color: dashboardOn(context).withValues(
                                    alpha: enabled ? 0.64 : 0.36,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              percentLabel,
                              maxLines: 1,
                              softWrap: false,
                              style: context.vwFinePrint.copyWith(
                                color: dashboardOn(context).withValues(
                                  alpha: enabled ? 0.64 : 0.36,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String localizedCategory(BuildContext context, String name) {
  final l10n = context.l10n;
  return switch (name) {
    'Cache' => l10n.filterCategoryCache,
    'Temp' => l10n.filterCategoryTemp,
    'Media' => l10n.filterCategoryMedia,
    'System' => l10n.filterCategorySystem,
    'Other' => l10n.homeCategoryOther,
    _ => name,
  };
}

Color categoryColor(String name) {
  return switch (name) {
    'Cache' => const Color(0xFF64D2FF),
    'Temp' => const Color(0xFFFFD60A),
    'Media' => const Color(0xFFBF5AF2),
    'System' => const Color(0xFF30D158),
    'Other' => const Color(0xFF8E8E93),
    _ => const Color(0xFF8E8E93),
  };
}

String percentLabel(int count, int total) {
  if (total <= 0 || count <= 0) return '0%';
  final exact = count * 100 / total;
  if (exact < 0.1) return '<0.1%';
  if (exact < 1) return '${exact.toStringAsFixed(1)}%';
  return '${exact.round()}%';
}
