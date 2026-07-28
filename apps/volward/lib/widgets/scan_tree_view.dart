import 'package:flutter/material.dart';

import '../scan_tree.dart';
import '../scan_tree_flatten.dart';
import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';
import 'apple_widgets.dart';

typedef ScanTreeSelectChanged = void Function(String entryId, bool selected);

class ScanTreeRow extends StatelessWidget {
  const ScanTreeRow({
    super.key,
    required this.row,
    required this.selected,
    required this.onToggleExpand,
    required this.onSelectChanged,
    required this.formatBytes,
    this.busy = false,
  });

  final FlatRow row;
  final Set<String> selected;
  final ValueChanged<String> onToggleExpand;
  final ScanTreeSelectChanged onSelectChanged;
  final String Function(num? bytes) formatBytes;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final node = row.node;
    if (node.isDirectory) {
      return _dirTile(context, node, row.depth, row.isExpanded);
    }
    return _fileTile(context, node, row.depth);
  }

  Widget _dirTile(
    BuildContext context,
    ScanTreeNode node,
    int nodeDepth,
    bool isOpen,
  ) {
    final v = context.volward;
    return Material(
      color: v.canvas,
      child: InkWell(
        onTap: () => onToggleExpand(node.path),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppleSpacing.md + nodeDepth * 14.0,
            AppleSpacing.xs,
            AppleSpacing.md,
            AppleSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(
                isOpen ? Icons.expand_more : Icons.chevron_right,
                size: 18,
                color: v.inkMuted48,
              ),
              const SizedBox(width: AppleSpacing.xxs),
              Icon(
                isOpen ? Icons.folder_open_outlined : Icons.folder_outlined,
                size: 16,
                color: v.folderIcon,
              ),
              const SizedBox(width: AppleSpacing.xs),
              Expanded(
                child: Text(
                  node.name,
                  style: context.vwCaptionStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${node.fileCount} · ${formatBytes(node.totalBytes)}',
                style: context.vwFinePrint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fileTile(BuildContext context, ScanTreeNode node, int nodeDepth) {
    final v = context.volward;
    final entry = node.entry;
    if (entry == null) return const SizedBox.shrink();

    final id = entry['id']?.toString() ?? node.entryId ?? '';
    final category = entry['category']?.toString() ?? '';
    final deletable = entry['deletable'] == true;
    final isSelected = selected.contains(id);

    return Container(
      decoration: BoxDecoration(
        color: isSelected ? v.primary.withValues(alpha: 0.06) : v.canvas,
        border: Border(bottom: BorderSide(color: v.hairline, width: 0.5)),
      ),
      child: AppleListRow(
        title: node.name,
        subtitle: '$category · ${formatBytes(entry['size_bytes'] as num?)}',
        selected: isSelected,
        leading: Padding(
          padding: EdgeInsets.only(left: nodeDepth * 14.0),
          child: Checkbox(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            value: isSelected,
            onChanged: (!deletable || busy)
                ? null
                : (val) => onSelectChanged(id, val == true),
          ),
        ),
        trailing: deletable
            ? Icon(Icons.delete_outline, size: 16, color: v.inkMuted48)
            : null,
        onTap: (!deletable || busy)
            ? null
            : () => onSelectChanged(id, !isSelected),
      ),
    );
  }
}

class ScanTreeView extends StatelessWidget {
  const ScanTreeView({
    super.key,
    required this.root,
    required this.expanded,
    required this.selected,
    required this.onToggleExpand,
    required this.onSelectChanged,
    required this.formatBytes,
    this.busy = false,
    this.depth = 0,
  });

  final ScanTreeNode root;
  final Set<String> expanded;
  final Set<String> selected;
  final ValueChanged<String> onToggleExpand;
  final ScanTreeSelectChanged onSelectChanged;
  final String Function(num? bytes) formatBytes;
  final bool busy;
  final int depth;

  @override
  Widget build(BuildContext context) {
    if (!root.isDirectory) {
      return ScanTreeRow(
        row: FlatRow(node: root, depth: depth, isExpanded: false),
        selected: selected,
        onToggleExpand: onToggleExpand,
        onSelectChanged: onSelectChanged,
        formatBytes: formatBytes,
        busy: busy,
      );
    }

    if (depth == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in root.children)
            ScanTreeRow(
              row: FlatRow(
                node: child,
                depth: depth,
                isExpanded: expanded.contains(child.path),
              ),
              selected: selected,
              onToggleExpand: onToggleExpand,
              onSelectChanged: onSelectChanged,
              formatBytes: formatBytes,
              busy: busy,
            ),
        ],
      );
    }

    return ScanTreeRow(
      row: FlatRow(
        node: root,
        depth: depth,
        isExpanded: expanded.contains(root.path),
      ),
      selected: selected,
      onToggleExpand: onToggleExpand,
      onSelectChanged: onSelectChanged,
      formatBytes: formatBytes,
      busy: busy,
    );
  }
}
