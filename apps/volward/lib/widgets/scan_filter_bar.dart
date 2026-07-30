import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';

enum ScanSortMode { sizeDesc, sizeAsc, nameAsc }

extension ScanSortModeLabel on ScanSortMode {
  String label(BuildContext context) {
    final l10n = context.l10n;
    switch (this) {
      case ScanSortMode.sizeDesc:
        return l10n.sortSizeDesc;
      case ScanSortMode.sizeAsc:
        return l10n.sortSizeAsc;
      case ScanSortMode.nameAsc:
        return l10n.sortNameAsc;
    }
  }
}

/// Category + sort controls for scan results.
///
/// Single-row layout:
///   [All] [Cache] [Temp] [Media] [System]  ···  [Size ↓ ▾]
///
/// - Type chips: single-select, only the 4 categories that the classifier
///   actually emits (Cache / Temp / Media / System) plus "All".
/// - Sort: popup-menu button — compact, easily extensible.
/// - The whole row scrolls horizontally when the available width is too
///   narrow for chips + sort controls (avoids RenderFlex overflow).
class ScanFilterBar extends StatelessWidget {
  const ScanFilterBar({
    super.key,
    required this.categoryFilter,
    required this.onCategoryChanged,
    required this.sortMode,
    required this.onSortChanged,
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
                      label: _categoryLabel(context, value),
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

  String _categoryLabel(BuildContext context, String? value) {
    final l10n = context.l10n;
    return switch (value) {
      null => l10n.filterAll,
      'Cache' => l10n.filterCategoryCache,
      'Temp' => l10n.filterCategoryTemp,
      'Media' => l10n.filterCategoryMedia,
      'System' => l10n.filterCategorySystem,
      _ => value,
    };
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
                label: mode.label(context),
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
              sortMode.label(context),
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
