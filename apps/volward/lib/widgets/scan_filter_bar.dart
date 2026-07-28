import 'package:flutter/material.dart';

import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';

enum ScanSortMode { sizeDesc, sizeAsc, nameAsc }

extension ScanSortModeLabel on ScanSortMode {
  String get label {
    switch (this) {
      case ScanSortMode.sizeDesc:
        return 'Size ↓';
      case ScanSortMode.sizeAsc:
        return 'Size ↑';
      case ScanSortMode.nameAsc:
        return 'Name';
    }
  }
}

/// Category + sort + toggle filters for scan results.
///
/// Single-row layout:
///   [All] [Cache] [Temp] [Media] [System]  ···  [Size ↓ ▾] [✓ Deletable]
///
/// - Type chips: single-select, only the 4 categories that the classifier
///   actually emits (Cache / Temp / Media / System) plus "All".
/// - Sort: popup-menu button — compact, easily extensible.
/// - Deletable / Incremental: checkbox toggles on the right.
/// - The whole row scrolls horizontally when the available width is too
///   narrow for chips + trailing controls (avoids RenderFlex overflow).
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

  /// Only the categories that classify.rs actually emits, plus null == All.
  static const categoryOptions = <String?>[
    null,
    'Cache',
    'Temp',
    'Media',
    'System',
  ];

  static const _barHeight = 32.0;

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
          vertical: AppleSpacing.xxs,
        ),
        child: SizedBox(
          height: _barHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final chips = <Widget>[
                for (final value in categoryOptions)
                  Padding(
                    padding: const EdgeInsets.only(right: AppleSpacing.xxs),
                    child: _FilterChip(
                      label: value ?? 'All',
                      selected: categoryFilter == value,
                      onTap: scanning ? null : () => onCategoryChanged(value),
                    ),
                  ),
              ];

              final trailing = <Widget>[
                _SortMenuButton(
                  sortMode: sortMode,
                  enabled: !scanning,
                  onChanged: onSortChanged,
                ),
                const SizedBox(width: AppleSpacing.xs),
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
              ];

              // Horizontally scrollable so chips + trailing never overflow.
              // minWidth keeps trailing right-aligned when everything fits.
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: chips),
                      Row(mainAxisSize: MainAxisSize.min, children: trailing),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Filter chip ──────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
    final bg = selected ? v.primaryFocus : Colors.transparent;
    final border = selected ? v.primaryFocus : v.hairline;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppleRadius.pill),
          border: Border.all(color: border, width: selected ? 1.5 : 1),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppleTypography.finePrint.copyWith(
            color: fg,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            height: 1,
          ),
        ),
      ),
    );
  }
}

// ── Sort popup-menu button ───────────────────────────────────────────────────

class _SortMenuButton extends StatelessWidget {
  const _SortMenuButton({
    required this.sortMode,
    required this.enabled,
    required this.onChanged,
  });

  final ScanSortMode sortMode;
  final bool enabled;
  final ValueChanged<ScanSortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    final fg = enabled ? v.inkMuted80 : v.inkMuted48;

    return PopupMenuButton<ScanSortMode>(
      enabled: enabled,
      initialValue: sortMode,
      onSelected: onChanged,
      tooltip: '',
      offset: const Offset(0, 30),
      color: v.canvas,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        side: BorderSide(color: v.hairline),
      ),
      itemBuilder: (context) => ScanSortMode.values
          .map(
            (mode) => PopupMenuItem<ScanSortMode>(
              value: mode,
              height: 32,
              child: _SortMenuItem(
                label: mode.label,
                selected: sortMode == mode,
              ),
            ),
          )
          .toList(),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          border: Border.all(color: v.hairline),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              sortMode.label,
              style: AppleTypography.finePrint.copyWith(
                color: fg,
                fontWeight: FontWeight.w500,
                height: 1,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.keyboard_arrow_down_rounded, size: 13, color: fg),
          ],
        ),
      ),
    );
  }
}

class _SortMenuItem extends StatelessWidget {
  const _SortMenuItem({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: selected
              ? Icon(Icons.check_rounded, size: 13, color: v.primary)
              : null,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppleTypography.finePrint.copyWith(
            color: selected ? v.primary : v.inkMuted80,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            height: 1,
          ),
        ),
      ],
    );
  }
}

// ── Deletable / Incremental toggle ───────────────────────────────────────────

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
    return GestureDetector(
      onTap: enabled ? () => onChanged(!selected) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: Checkbox(
              value: selected,
              onChanged: enabled ? (val) => onChanged(val ?? false) : null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppleTypography.finePrint.copyWith(
              color: enabled ? v.inkMuted80 : v.inkMuted48,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
