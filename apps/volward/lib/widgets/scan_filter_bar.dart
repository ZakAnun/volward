import 'package:flutter/material.dart';

import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';

enum ScanSortMode { sizeDesc, sizeAsc, nameAsc }

/// Category + sort + toggle filters for scan results.
class ScanFilterBar extends StatelessWidget {
  const ScanFilterBar({
    super.key,
    required this.categoryFilter,
    required this.onCategoryChanged,
    required this.sortMode,
    required this.onSortChanged,
    required this.deletableOnly,
    required this.onDeletableOnlyChanged,
    required this.incrementalScan,
    required this.onIncrementalScanChanged,
    required this.incrementalEnabled,
    required this.scanning,
  });

  static const categoryOptions = <String?>[
    null,
    'Cache',
    'Temp',
    'Media',
    'Unknown',
    'System',
  ];

  static const _segmentHeight = 28.0;
  static const _labelWidth = 44.0;

  final String? categoryFilter;
  final ValueChanged<String?> onCategoryChanged;
  final ScanSortMode sortMode;
  final ValueChanged<ScanSortMode> onSortChanged;
  final bool deletableOnly;
  final ValueChanged<bool> onDeletableOnlyChanged;
  final bool incrementalScan;
  final ValueChanged<bool> onIncrementalScanChanged;
  final bool incrementalEnabled;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: v.surfacePearl,
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        border: Border.all(color: v.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppleSpacing.sm,
          vertical: AppleSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _labeledRow(
              context: context,
              label: 'Type',
              child: SizedBox(
                height: _segmentHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categoryOptions.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppleSpacing.xxs),
                  itemBuilder: (context, index) {
                    final value = categoryOptions[index];
                    final label = value ?? 'All';
                    return _FilterPill(
                      label: label,
                      selected: categoryFilter == value,
                      onTap: scanning ? null : () => onCategoryChanged(value),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: AppleSpacing.xxs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: _labelWidth,
                  child: Text(
                    'Sort',
                    style: AppleTypography.finePrint.copyWith(
                      fontWeight: FontWeight.w600,
                      color: v.inkMuted80,
                    ),
                  ),
                ),
                _SortSegmentedControl(
                  height: _segmentHeight,
                  sortMode: sortMode,
                  enabled: !scanning,
                  onChanged: onSortChanged,
                ),
                const Spacer(),
                _FilterToggle(
                  label: 'Deletable',
                  selected: deletableOnly,
                  enabled: !scanning,
                  onChanged: onDeletableOnlyChanged,
                ),
                if (incrementalEnabled) ...[
                  const SizedBox(width: AppleSpacing.xs),
                  Tooltip(
                    message: '复用未变化的文件夹，加快后续扫描',
                    child: _FilterToggle(
                      label: 'Incremental',
                      selected: incrementalScan,
                      enabled: !scanning,
                      onChanged: onIncrementalScanChanged,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _labeledRow({
    required BuildContext context,
    required String label,
    required Widget child,
  }) {
    final v = context.volward;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: _labelWidth,
          child: Text(
            label,
            style: AppleTypography.finePrint.copyWith(
              fontWeight: FontWeight.w600,
              color: v.inkMuted80,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    final fg = selected ? v.onPrimary : v.inkMuted80;
    final bg = selected ? v.primaryFocus : v.canvas;
    final border = selected ? v.primaryFocus : v.hairline;

    return Material(
      color: bg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        side: BorderSide(color: border, width: selected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: selected
            ? v.primary.withValues(alpha: 0.12)
            : v.canvasParchment,
        child: Container(
          height: ScanFilterBar._segmentHeight,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: AppleTypography.finePrint.copyWith(
              color: fg,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _SortSegmentedControl extends StatelessWidget {
  const _SortSegmentedControl({
    required this.height,
    required this.sortMode,
    required this.enabled,
    required this.onChanged,
  });

  final double height;
  final ScanSortMode sortMode;
  final bool enabled;
  final ValueChanged<ScanSortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: v.canvas,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          border: Border.all(color: v.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _segment(
              context,
              'Size ↓',
              ScanSortMode.sizeDesc,
              showDivider: true,
            ),
            _segment(
              context,
              'Size ↑',
              ScanSortMode.sizeAsc,
              showDivider: true,
            ),
            _segment(context, 'Name', ScanSortMode.nameAsc, showDivider: false),
          ],
        ),
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    String label,
    ScanSortMode mode, {
    required bool showDivider,
  }) {
    final v = context.volward;
    final selected = sortMode == mode;
    final fg = selected ? v.onPrimary : v.inkMuted80;
    final bg = selected ? v.primaryFocus : v.canvas;

    Widget cell = Material(
      color: bg,
      child: InkWell(
        onTap: enabled ? () => onChanged(mode) : null,
        splashColor: Colors.transparent,
        highlightColor: v.canvasParchment,
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: AppleTypography.finePrint.copyWith(
              color: enabled ? fg : fg.withValues(alpha: 0.45),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              height: 1.2,
            ),
          ),
        ),
      ),
    );

    if (showDivider) {
      cell = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cell,
          VerticalDivider(width: 1, thickness: 1, color: v.hairline),
        ],
      );
    }
    return cell;
  }
}

class _FilterToggle extends StatelessWidget {
  const _FilterToggle({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? () => onChanged(!selected) : null,
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        splashColor: Colors.transparent,
        highlightColor: v.canvasParchment,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppleSpacing.xxs,
            vertical: 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: selected,
                  onChanged: enabled ? (v) => onChanged(v ?? false) : null,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppleTypography.finePrint.copyWith(
                  color: enabled ? v.inkMuted80 : v.inkMuted48,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
