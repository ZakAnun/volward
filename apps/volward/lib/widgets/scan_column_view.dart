import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../l10n/l10n.dart';
import '../scan_tree.dart';
import '../snapshot_catalog.dart';
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
    this.loadingChildrenPaths = const {},
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
  final Set<String> loadingChildrenPaths;
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
    _hScroll.jumpTo(_hScroll.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  List<_FinderColumnData> _columns() {
    List<ScanTreeNode> childrenFor(ScanTreeNode node) {
      return widget.visibleChildrenByPath[node.path] ??
          (node.path == widget.root.path && widget.visibleChildren != null
              ? widget.visibleChildren!
              : node.children);
    }

    final cols = <_FinderColumnData>[
      _FinderColumnData(
        path: widget.root.path,
        items: _sorted(childrenFor(widget.root)),
        loading: widget.loadingChildrenPaths.contains(widget.root.path),
      ),
    ];
    for (final node in widget.selectionChain) {
      if (node.isDirectory) {
        cols.add(
          _FinderColumnData(
            path: node.path,
            items: _sorted(childrenFor(node)),
            loading: widget.loadingChildrenPaths.contains(node.path),
          ),
        );
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
          return SnapshotCatalog.compareAsciiCaseInsensitive(a.name, b.name);
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
        if (columns.first.items.isEmpty) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: v.canvas,
              borderRadius: BorderRadius.circular(AppleRadius.sm),
              border: Border.all(color: v.hairline),
            ),
            child: Center(
              child: Text(
                columns.first.loading
                    ? context.l10n.scanColumnPreparingFolder
                    : context.l10n.scanColumnNoFilterMatches,
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
                      path: columns[columnIndex].path,
                      items: columns[columnIndex].items,
                      loading: columns[columnIndex].loading,
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

class _FinderColumnData {
  const _FinderColumnData({
    required this.path,
    required this.items,
    required this.loading,
  });

  final String path;
  final List<ScanTreeNode> items;
  final bool loading;
}

class _FinderColumn extends StatelessWidget {
  const _FinderColumn({
    required this.width,
    required this.height,
    required this.path,
    required this.items,
    required this.loading,
    required this.selected,
    required this.onSelect,
    required this.formatBytes,
    required this.selectedEntryIds,
    required this.peekInFlight,
  });

  final double width;
  final double height;
  final String path;
  final List<ScanTreeNode> items;
  final bool loading;
  final ScanTreeNode? selected;
  final ValueChanged<ScanTreeNode> onSelect;
  final String Function(num? bytes) formatBytes;
  final Set<String> selectedEntryIds;
  final Set<String> peekInFlight;

  static const int _paintedColumnThreshold = 240;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    final rowStyle = _FinderRowStyle(
      selectedBackground: v.primaryFocus,
      markedBackground: v.primary.withValues(alpha: 0.08),
      folderIcon: v.folderIcon,
      selectedFolderIcon: v.folderIconOnPrimary,
      fileIcon: v.inkMuted48,
      idleIcon: v.inkMuted48,
      selectedIdleIcon: v.onPrimary.withValues(alpha: 0.85),
      progressColor: v.primary,
      selectedProgressColor: v.onPrimary,
      normalName: context.vwCaption.copyWith(
        color: v.body,
        fontWeight: FontWeight.w400,
      ),
      selectedName: context.vwCaption.copyWith(
        color: v.onPrimary,
        fontWeight: FontWeight.w600,
      ),
      normalSize: context.vwFinePrint.copyWith(
        color: v.inkMuted48,
        fontSize: 11,
      ),
      selectedSize: context.vwFinePrint.copyWith(
        color: v.onPrimary.withValues(alpha: 0.85),
        fontSize: 11,
      ),
    );
    return SizedBox(
      width: width,
      height: height,
      child: items.isEmpty && loading
          ? const Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            )
          : items.length > _paintedColumnThreshold
          ? _PaintedFinderColumn(
              width: width,
              height: height,
              items: items,
              selected: selected,
              onSelect: onSelect,
              formatBytes: formatBytes,
              selectedEntryIds: selectedEntryIds,
              peekInFlight: peekInFlight,
              style: rowStyle,
            )
          : ListView.builder(
              primary: false,
              itemExtent: 28,
              scrollCacheExtent: const ScrollCacheExtent.pixels(112),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
              addSemanticIndexes: false,
              padding: const EdgeInsets.symmetric(vertical: AppleSpacing.xxs),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final node = items[index];
                final isSelected = selected?.path == node.path;
                final entryId = node.entryId;
                final marked =
                    entryId != null && selectedEntryIds.contains(entryId);
                final isDir = node.isDirectory;
                final subtitle = isDir
                    ? (node.scanned ? formatBytes(node.displayBytes) : '—')
                    : formatBytes(node.sizeBytes);

                return _FinderRow(
                  node: node,
                  isSelected: isSelected,
                  markedForDelete: marked,
                  subtitle: subtitle,
                  style: rowStyle,
                  peekInFlight: peekInFlight.contains(node.path),
                  onTap: () => onSelect(node),
                );
              },
            ),
    );
  }
}

class _FinderRowStyle {
  const _FinderRowStyle({
    required this.selectedBackground,
    required this.markedBackground,
    required this.folderIcon,
    required this.selectedFolderIcon,
    required this.fileIcon,
    required this.idleIcon,
    required this.selectedIdleIcon,
    required this.progressColor,
    required this.selectedProgressColor,
    required this.normalName,
    required this.selectedName,
    required this.normalSize,
    required this.selectedSize,
  });

  final Color selectedBackground;
  final Color markedBackground;
  final Color folderIcon;
  final Color selectedFolderIcon;
  final Color fileIcon;
  final Color idleIcon;
  final Color selectedIdleIcon;
  final Color progressColor;
  final Color selectedProgressColor;
  final TextStyle normalName;
  final TextStyle selectedName;
  final TextStyle normalSize;
  final TextStyle selectedSize;
}

class _PaintedFinderColumn extends StatefulWidget {
  const _PaintedFinderColumn({
    required this.width,
    required this.height,
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.formatBytes,
    required this.selectedEntryIds,
    required this.peekInFlight,
    required this.style,
  });

  final double width;
  final double height;
  final List<ScanTreeNode> items;
  final ScanTreeNode? selected;
  final ValueChanged<ScanTreeNode> onSelect;
  final String Function(num? bytes) formatBytes;
  final Set<String> selectedEntryIds;
  final Set<String> peekInFlight;
  final _FinderRowStyle style;

  @override
  State<_PaintedFinderColumn> createState() => _PaintedFinderColumnState();
}

class _PaintedFinderColumnState extends State<_PaintedFinderColumn> {
  static const double _rowHeight = 28;
  static const double _verticalPadding = AppleSpacing.xxs;

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handleTap(TapUpDetails details) {
    final y = details.localPosition.dy - _verticalPadding;
    final index = y ~/ _rowHeight;
    if (index < 0 || index >= widget.items.length) return;
    widget.onSelect(widget.items[index]);
  }

  @override
  Widget build(BuildContext context) {
    final contentHeight =
        widget.items.length * _rowHeight + _verticalPadding * 2;
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        primary: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _handleTap,
          child: SizedBox(
            width: widget.width,
            height: contentHeight < widget.height
                ? widget.height
                : contentHeight,
            child: CustomPaint(
              painter: _FinderColumnPainter(
                scrollController: _scrollController,
                viewportHeight: widget.height,
                items: widget.items,
                selectedPath: widget.selected?.path,
                formatBytes: widget.formatBytes,
                selectedEntryIds: widget.selectedEntryIds,
                peekInFlight: widget.peekInFlight,
                style: widget.style,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FinderColumnPainter extends CustomPainter {
  _FinderColumnPainter({
    required this.scrollController,
    required this.viewportHeight,
    required this.items,
    required this.selectedPath,
    required this.formatBytes,
    required this.selectedEntryIds,
    required this.peekInFlight,
    required this.style,
  }) : super(repaint: scrollController);

  static const double _rowHeight = 28;
  static const double _verticalPadding = AppleSpacing.xxs;
  static const double _leftPadding = AppleSpacing.xs;
  static const double _iconSize = 16;
  static const double _gap = AppleSpacing.xxs;
  static const double _trailingWidth = 54;

  final ScrollController scrollController;
  final double viewportHeight;
  final List<ScanTreeNode> items;
  final String? selectedPath;
  final String Function(num? bytes) formatBytes;
  final Set<String> selectedEntryIds;
  final Set<String> peekInFlight;
  final _FinderRowStyle style;
  final _textCache = <_PaintedTextKey, TextPainter>{};
  final _sizeLabelCache = <int, String>{};
  final _iconCache = <_PaintedIconKey, TextPainter>{};

  static const int _maxTextCacheEntries = 256;
  static const int _maxSizeLabelCacheEntries = 256;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = scrollController.hasClients
        ? scrollController.offset.clamp(0.0, double.infinity)
        : 0.0;
    final first = ((offset - _verticalPadding) / _rowHeight).floor().clamp(
      0,
      items.length,
    );
    final last = ((offset + viewportHeight - _verticalPadding) / _rowHeight)
        .ceil()
        .clamp(0, items.length);

    for (var index = first; index < last; index++) {
      _paintRow(canvas, size, index);
    }
  }

  void _paintRow(Canvas canvas, Size size, int index) {
    final node = items[index];
    final y = _verticalPadding + index * _rowHeight;
    final selected = node.path == selectedPath;
    final entryId = node.entryId;
    final marked = entryId != null && selectedEntryIds.contains(entryId);
    final bg = selected
        ? style.selectedBackground
        : marked
        ? style.markedBackground
        : Colors.transparent;
    if ((bg.a * 255.0).round().clamp(0, 255) != 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, _rowHeight),
        Paint()..color = bg,
      );
    }

    final isDir = node.isDirectory;
    final muted = selected ? style.selectedIdleIcon : style.idleIcon;
    final iconColor = isDir
        ? (selected ? style.selectedFolderIcon : style.folderIcon)
        : style.fileIcon;
    final icon = isDir ? Icons.folder : Icons.insert_drive_file_outlined;
    _iconPainter(icon, iconColor).paint(canvas, Offset(_leftPadding, y + 6));

    final trailing = isDir ? null : _sizeLabel(index, node.sizeBytes);
    final trailingWidth = trailing == null ? 18.0 : _trailingWidth;
    const nameLeft = _leftPadding + _iconSize + _gap;
    final nameRight = size.width - _leftPadding - trailingWidth;
    if (nameRight > nameLeft) {
      _textPainter(
        text: node.name,
        style: selected ? style.selectedName : style.normalName,
        maxWidth: nameRight - nameLeft,
        align: TextAlign.left,
      ).paint(canvas, Offset(nameLeft, y + 6));
    }

    if (isDir) {
      final statusIcon = !node.scanned ? Icons.more_horiz : Icons.chevron_right;
      _iconPainter(
        statusIcon,
        muted,
      ).paint(canvas, Offset(size.width - _leftPadding - 14, y + 7));
    } else if (trailing != null) {
      _textPainter(
        text: trailing,
        style: selected ? style.selectedSize : style.normalSize,
        maxWidth: _trailingWidth,
        align: TextAlign.right,
      ).paint(
        canvas,
        Offset(size.width - _leftPadding - _trailingWidth, y + 7),
      );
    }
  }

  String _sizeLabel(int index, int sizeBytes) {
    final cached = _sizeLabelCache.remove(index);
    if (cached != null) {
      _sizeLabelCache[index] = cached;
      return cached;
    }
    final label = formatBytes(sizeBytes);
    _sizeLabelCache[index] = label;
    while (_sizeLabelCache.length > _maxSizeLabelCacheEntries) {
      _sizeLabelCache.remove(_sizeLabelCache.keys.first);
    }
    return label;
  }

  TextPainter _iconPainter(IconData icon, Color color) {
    final size = icon == Icons.more_horiz || icon == Icons.chevron_right
        ? 14.0
        : _iconSize;
    final key = _PaintedIconKey(
      codePoint: icon.codePoint,
      color: color,
      size: size,
    );
    final cached = _iconCache[key];
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          color: color,
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    _iconCache[key] = painter;
    return painter;
  }

  TextPainter _textPainter({
    required String text,
    required TextStyle style,
    required double maxWidth,
    TextAlign align = TextAlign.left,
  }) {
    final key = _PaintedTextKey(
      text: text,
      style: style,
      maxWidth: maxWidth,
      align: align,
    );
    final cached = _textCache.remove(key);
    if (cached != null) {
      _textCache[key] = cached;
      return cached;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      textAlign: align,
    )..layout(maxWidth: maxWidth);
    _textCache[key] = painter;
    while (_textCache.length > _maxTextCacheEntries) {
      _textCache.remove(_textCache.keys.first);
    }
    return painter;
  }

  @override
  bool shouldRepaint(covariant _FinderColumnPainter oldDelegate) {
    return oldDelegate.items != items ||
        oldDelegate.selectedPath != selectedPath ||
        oldDelegate.selectedEntryIds != selectedEntryIds ||
        oldDelegate.peekInFlight != peekInFlight ||
        oldDelegate.style != style ||
        oldDelegate.viewportHeight != viewportHeight;
  }
}

class _PaintedTextKey {
  const _PaintedTextKey({
    required this.text,
    required this.style,
    required this.maxWidth,
    required this.align,
  });

  final String text;
  final TextStyle style;
  final double maxWidth;
  final TextAlign align;

  @override
  bool operator ==(Object other) {
    return other is _PaintedTextKey &&
        other.text == text &&
        other.style == style &&
        other.maxWidth == maxWidth &&
        other.align == align;
  }

  @override
  int get hashCode => Object.hash(text, style, maxWidth, align);
}

class _PaintedIconKey {
  const _PaintedIconKey({
    required this.codePoint,
    required this.color,
    required this.size,
  });

  final int codePoint;
  final Color color;
  final double size;

  @override
  bool operator ==(Object other) {
    return other is _PaintedIconKey &&
        other.codePoint == codePoint &&
        other.color == color &&
        other.size == size;
  }

  @override
  int get hashCode => Object.hash(codePoint, color, size);
}

class _FinderRow extends StatelessWidget {
  const _FinderRow({
    required this.node,
    required this.isSelected,
    required this.markedForDelete,
    required this.subtitle,
    required this.style,
    required this.onTap,
    this.peekInFlight = false,
  });

  final ScanTreeNode node;
  final bool isSelected;
  final bool markedForDelete;
  final String subtitle;
  final _FinderRowStyle style;
  final VoidCallback onTap;

  /// True when a peek scan is actively running for this node's path.
  final bool peekInFlight;

  Color get _background {
    if (isSelected) return style.selectedBackground;
    if (markedForDelete) return style.markedBackground;
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final isDir = node.isDirectory;
    final muted = isSelected ? style.selectedIdleIcon : style.idleIcon;

    return ColoredBox(
      color: _background,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
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
                      ? (isSelected
                            ? style.selectedFolderIcon
                            : style.folderIcon)
                      : style.fileIcon,
                ),
                const SizedBox(width: AppleSpacing.xxs),
                Expanded(
                  child: Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: isSelected ? style.selectedName : style.normalName,
                  ),
                ),
                if (isDir)
                  (!node.scanned && peekInFlight)
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: isSelected
                                ? style.selectedProgressColor
                                : style.progressColor,
                          ),
                        )
                      : (!node.scanned)
                      ? Icon(Icons.more_horiz, size: 14, color: muted)
                      : Icon(Icons.chevron_right, size: 14, color: muted)
                else
                  Text(
                    subtitle,
                    style: isSelected ? style.selectedSize : style.normalSize,
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
