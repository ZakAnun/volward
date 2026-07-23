import 'package:flutter/material.dart';

import '../scan_tree.dart';
import '../theme/apple_tokens.dart';

typedef ScanColumnSelectCallback = void Function(int columnIndex, ScanTreeNode node);

/// macOS Finder-style column browser for [root] scan tree.
class ScanColumnView extends StatefulWidget {
  const ScanColumnView({
    super.key,
    required this.root,
    required this.selectionChain,
    required this.onSelect,
    required this.formatBytes,
    this.selectedEntryIds = const {},
    this.busy = false,
    this.columnWidth = 220,
  });

  final ScanTreeNode root;
  final List<ScanTreeNode> selectionChain;
  final ScanColumnSelectCallback onSelect;
  final String Function(num? bytes) formatBytes;
  final Set<String> selectedEntryIds;
  final bool busy;
  final double columnWidth;

  @override
  State<ScanColumnView> createState() => _ScanColumnViewState();
}

class _ScanColumnViewState extends State<ScanColumnView> {
  final ScrollController _hScroll = ScrollController();

  @override
  void didUpdateWidget(covariant ScanColumnView oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    final cols = <List<ScanTreeNode>>[widget.root.children];
    for (final node in widget.selectionChain) {
      if (node.isDirectory) {
        cols.add(node.children);
      }
    }
    return cols;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        if (!height.isFinite || height <= 0) {
          return const SizedBox.shrink();
        }

        final columns = _columns();
        if (widget.root.children.isEmpty) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: AppleColors.canvas,
              borderRadius: BorderRadius.circular(AppleRadius.sm),
              border: Border.all(color: AppleColors.hairline),
            ),
            child: Center(
              child: Text(
                'No items match the current filters.',
                style: AppleTypography.finePrint.copyWith(color: AppleColors.inkMuted48),
              ),
            ),
          );
        }

        return SizedBox(
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppleColors.canvas,
              borderRadius: BorderRadius.circular(AppleRadius.sm),
              border: Border.all(color: AppleColors.hairline),
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
                  separatorBuilder: (_, __) => const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: AppleColors.hairline,
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
  });

  final double width;
  final double height;
  final List<ScanTreeNode> items;
  final ScanTreeNode? selected;
  final ValueChanged<ScanTreeNode> onSelect;
  final String Function(num? bytes) formatBytes;
  final Set<String> selectedEntryIds;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ListView.builder(
        primary: false,
        padding: const EdgeInsets.symmetric(vertical: AppleSpacing.xxs),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final node = items[index];
          final isSelected = selected?.path == node.path;
          final entryId = node.entryId ?? node.entry?['id']?.toString();
          final marked = entryId != null && selectedEntryIds.contains(entryId);

          return _FinderRow(
            node: node,
            isSelected: isSelected,
            markedForDelete: marked,
            formatBytes: formatBytes,
            onTap: () => onSelect(node),
          );
        },
      ),
    );
  }
}

class _FinderRow extends StatelessWidget {
  const _FinderRow({
    required this.node,
    required this.isSelected,
    required this.markedForDelete,
    required this.formatBytes,
    required this.onTap,
  });

  final ScanTreeNode node;
  final bool isSelected;
  final bool markedForDelete;
  final String Function(num? bytes) formatBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDir = node.isDirectory;
    final fg = isSelected ? AppleColors.onPrimary : AppleColors.body;
    final muted = isSelected ? AppleColors.onPrimary.withValues(alpha: 0.85) : AppleColors.inkMuted48;
    final bg = isSelected
        ? AppleColors.primaryFocus
        : markedForDelete
            ? AppleColors.primary.withValues(alpha: 0.08)
            : Colors.transparent;

    final subtitle = isDir
        ? formatBytes(node.totalBytes)
        : formatBytes(node.entry?['size_bytes'] as num? ?? node.sizeBytes);

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        hoverColor: isSelected ? null : AppleColors.canvasParchment,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppleSpacing.xs,
            vertical: 5,
          ),
          child: Row(
            children: [
              Icon(
                isDir ? Icons.folder : Icons.insert_drive_file_outlined,
                size: 16,
                color: isDir
                    ? (isSelected ? const Color(0xFF7CB3FF) : const Color(0xFF5AC8FA))
                    : muted,
              ),
              const SizedBox(width: AppleSpacing.xxs),
              Expanded(
                child: Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppleTypography.caption.copyWith(
                    color: fg,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (isDir)
                Icon(Icons.chevron_right, size: 14, color: muted)
              else
                Text(
                  subtitle,
                  style: AppleTypography.finePrint.copyWith(
                    color: muted,
                    fontSize: 11,
                  ),
                ),
            ],
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
