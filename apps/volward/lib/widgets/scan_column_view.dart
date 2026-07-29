import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../scan_tree.dart';
import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';
import 'scan_filter_bar.dart';

typedef ScanColumnSelectCallback =
    void Function(int columnIndex, ScanTreeNode node);

/// macOS Finder-style column browser for [root] scan tree.
class ScanColumnView extends StatefulWidget {
  const ScanColumnView({
    super.key,
    required this.root,
    required this.selectionChain,
    required this.onSelect,
    required this.formatBytes,
    this.visibleChildren,
    this.visibleChildrenByPath = const {},
    this.selectedEntryIds = const {},
    this.peekInFlight = const {},
    this.busy = false,
    this.columnWidth = 220,
    this.sortMode = ScanSortMode.sizeDesc,
    this.categoryFilter,
    this.deletableOnly = false,
    this.childrenPreSorted = false,
  });

  final ScanTreeNode root;
  final List<ScanTreeNode>? visibleChildren;
  final Map<String, List<ScanTreeNode>> visibleChildrenByPath;
  final List<ScanTreeNode> selectionChain;
  final ScanColumnSelectCallback onSelect;
  final String Function(num? bytes) formatBytes;
  final Set<String> selectedEntryIds;

  /// Paths for which a peek scan is actively running (from VolwardSession).
  final Set<String> peekInFlight;
  final bool busy;
  final double columnWidth;

  /// Sort applied to each column's children at render time (zero latency —
  /// no isolate, no tree copy).
  final ScanSortMode sortMode;
  final String? categoryFilter;
  final bool deletableOnly;
  final bool childrenPreSorted;

  @override
  State<ScanColumnView> createState() => _ScanColumnViewState();
}

class _ColumnViewKey {
  const _ColumnViewKey({
    required this.sortMode,
    required this.categoryFilter,
    required this.deletableOnly,
  });

  final ScanSortMode sortMode;
  final String? categoryFilter;
  final bool deletableOnly;

  @override
  bool operator ==(Object other) {
    return other is _ColumnViewKey &&
        other.sortMode == sortMode &&
        other.categoryFilter == categoryFilter &&
        other.deletableOnly == deletableOnly;
  }

  @override
  int get hashCode => Object.hash(sortMode, categoryFilter, deletableOnly);
}

class _ScanColumnViewState extends State<ScanColumnView> {
  final ScrollController _hScroll = ScrollController();

  // View-results cache: source-list identity → (filter/sort key, result).
  // Avoids re-sorting all visible columns on every navigation tick when the
  // underlying data hasn't changed.  Cleared whenever root identity changes
  // (i.e. a new snapshot was merged) to prevent stale entries from accumulating.
  final Map<int, (_ColumnViewKey, List<ScanTreeNode>)> _sortCache = {};

  @override
  void didUpdateWidget(covariant ScanColumnView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // New snapshot → new ScanTreeNode objects → old cache keys will never be
    // hit again.  Clear to avoid unbounded growth.
    if (!identical(oldWidget.root, widget.root)) {
      _sortCache.clear();
    }
    if (widget.selectionChain.length > oldWidget.selectionChain.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  void _scrollToEnd() {
    if (!_hScroll.hasClients) return;
    _hScroll.animateTo(
      _hScroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  List<List<ScanTreeNode>> _columns() {
    List<ScanTreeNode> childrenFor(ScanTreeNode node) {
      return widget.visibleChildrenByPath[node.path] ??
          (node.path == widget.root.path && widget.visibleChildren != null
              ? widget.visibleChildren!
              : node.children);
    }

    final cols = <List<ScanTreeNode>>[_sorted(childrenFor(widget.root))];
    for (final node in widget.selectionChain) {
      if (node.isDirectory) {
        cols.add(_sorted(childrenFor(node)));
      }
    }
    return cols;
  }

  /// Filters and sorts [items] at render time — O(k log k) where k is the
  /// visible column length, not the whole tree. Dirs always sort before files
  /// so the Finder-style layout is preserved.
  ///
  /// Results are cached by list identity so that repeated calls during the same
  /// render (e.g. column-nav ticks with unchanged data) return the pre-sorted
  /// list with zero additional work.
  List<ScanTreeNode> _sorted(List<ScanTreeNode> items) {
    if (widget.childrenPreSorted) {
      return items;
    }
    final key = identityHashCode(items);
    final viewKey = _ColumnViewKey(
      sortMode: widget.sortMode,
      categoryFilter: widget.categoryFilter,
      deletableOnly: widget.deletableOnly,
    );
    final cached = _sortCache[key];
    if (cached != null && cached.$1 == viewKey) {
      return cached.$2;
    }
    final list = items
        .where(
          (node) => node.matchesView(
            categoryFilter: widget.categoryFilter,
            deletableOnly: widget.deletableOnly,
          ),
        )
        .toList(growable: false);
    if (list.length <= 1) {
      _sortCache[key] = (viewKey, list);
      return list;
    }
    list.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      switch (widget.sortMode) {
        case ScanSortMode.sizeDesc:
          return b.displayBytes.compareTo(a.displayBytes);
        case ScanSortMode.sizeAsc:
          return a.displayBytes.compareTo(b.displayBytes);
        case ScanSortMode.nameAsc:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });
    _sortCache[key] = (viewKey, list);
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        if (!height.isFinite || height <= 0) {
          return const SizedBox.shrink();
        }

        final columns = _columns();
        if (columns.first.isEmpty) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: v.canvas,
              borderRadius: BorderRadius.circular(AppleRadius.sm),
              border: Border.all(color: v.hairline),
            ),
            child: Center(
              child: Text(
                'No items match the current filters.',
                style: context.vwFinePrint.copyWith(color: v.inkMuted48),
              ),
            ),
          );
        }

        return SizedBox(
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: v.canvas,
              borderRadius: BorderRadius.circular(AppleRadius.sm),
              border: Border.all(color: v.hairline),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppleRadius.sm),
              child: Scrollbar(
                controller: _hScroll,
                thumbVisibility: true,
                child: ListView.separated(
                  controller: _hScroll,
                  primary: false,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: columns.length,
                  separatorBuilder: (_, __) => VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: v.hairline,
                  ),
                  itemBuilder: (context, columnIndex) {
                    return _FinderColumn(
                      width: widget.columnWidth,
                      height: height,
                      items: columns[columnIndex],
                      selected: columnIndex < widget.selectionChain.length
                          ? widget.selectionChain[columnIndex]
                          : null,
                      formatBytes: widget.formatBytes,
                      selectedEntryIds: widget.selectedEntryIds,
                      peekInFlight: widget.peekInFlight,
                      onSelect: (node) => widget.onSelect(columnIndex, node),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FinderColumn extends StatelessWidget {
  const _FinderColumn({
    required this.width,
    required this.height,
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.formatBytes,
    required this.selectedEntryIds,
    required this.peekInFlight,
  });

  final double width;
  final double height;
  final List<ScanTreeNode> items;
  final ScanTreeNode? selected;
  final ValueChanged<ScanTreeNode> onSelect;
  final String Function(num? bytes) formatBytes;
  final Set<String> selectedEntryIds;
  final Set<String> peekInFlight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ListView.builder(
        primary: false,
        itemExtent: 28,
        scrollCacheExtent: const ScrollCacheExtent.pixels(560),
        padding: const EdgeInsets.symmetric(vertical: AppleSpacing.xxs),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final node = items[index];
          final isSelected = selected?.path == node.path;
          final entryId = node.entryId;
          final marked = entryId != null && selectedEntryIds.contains(entryId);

          return _FinderRow(
            key: ValueKey(node.path),
            node: node,
            isSelected: isSelected,
            markedForDelete: marked,
            formatBytes: formatBytes,
            peekInFlight: peekInFlight.contains(node.path),
            onTap: () => onSelect(node),
          );
        },
      ),
    );
  }
}

class _FinderRow extends StatelessWidget {
  const _FinderRow({
    super.key,
    required this.node,
    required this.isSelected,
    required this.markedForDelete,
    required this.formatBytes,
    required this.onTap,
    this.peekInFlight = false,
  });

  final ScanTreeNode node;
  final bool isSelected;
  final bool markedForDelete;
  final String Function(num? bytes) formatBytes;
  final VoidCallback onTap;

  /// True when a peek scan is actively running for this node's path.
  final bool peekInFlight;

  Color _background(VolwardTokens v) {
    if (isSelected) return v.primaryFocus;
    if (markedForDelete) return v.primary.withValues(alpha: 0.08);
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    final isDir = node.isDirectory;
    final fg = isSelected ? v.onPrimary : v.body;
    final muted = isSelected
        ? v.onPrimary.withValues(alpha: 0.85)
        : v.inkMuted48;
    final bg = _background(v);

    final subtitle = isDir
        ? (node.scanned ? formatBytes(node.displayBytes) : '—')
        : formatBytes(node.sizeBytes);

    return Material(
      color: bg,
      child: InkWell(
        hoverColor: isSelected ? Colors.transparent : v.dividerSoft,
        splashColor: Colors.transparent,
        highlightColor: isSelected ? Colors.transparent : v.dividerSoft,
        onTap: onTap,
        child: SizedBox(
          height: 28,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppleSpacing.xs),
            child: Row(
              children: [
                Icon(
                  isDir ? Icons.folder : Icons.insert_drive_file_outlined,
                  size: 16,
                  color: isDir
                      ? (isSelected ? v.folderIconOnPrimary : v.folderIcon)
                      : muted,
                ),
                const SizedBox(width: AppleSpacing.xxs),
                Expanded(
                  child: Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.vwCaption.copyWith(
                      color: fg,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (isDir)
                  (!node.scanned && peekInFlight)
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: isSelected ? v.onPrimary : v.primary,
                          ),
                        )
                      : (!node.scanned)
                      ? Icon(Icons.more_horiz, size: 14, color: muted)
                      : Icon(Icons.chevron_right, size: 14, color: muted)
                else
                  Text(
                    subtitle,
                    style: context.vwFinePrint.copyWith(
                      color: muted,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Builds the column list from [root] and [selectionChain].
List<List<ScanTreeNode>> scanColumnLayout(
  ScanTreeNode root,
  List<ScanTreeNode> selectionChain,
) {
  final cols = <List<ScanTreeNode>>[root.children];
  for (final node in selectionChain) {
    if (node.isDirectory) cols.add(node.children);
  }
  return cols;
}

/// Currently focused node (last in chain), if any.
ScanTreeNode? scanColumnFocusNode(List<ScanTreeNode> selectionChain) {
  if (selectionChain.isEmpty) return null;
  return selectionChain.last;
}
