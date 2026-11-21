import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../../scan_tree.dart';
import '../../../theme/apple_tokens.dart';
import '../../../theme/volward_tokens.dart';

/// Production preview row for the focused file or directory.
class ItemPreview extends StatelessWidget {
  const ItemPreview({
    super.key,
    required this.focus,
    required this.selected,
    required this.busy,
    required this.onToggleSelection,
    required this.formatBytes,
    this.horizontalInset = 24,
  });

  final ScanTreeNode? focus;
  final bool Function(String id) selected;
  final bool busy;
  final ValueChanged<ScanTreeNode> onToggleSelection;
  final String Function(num? bytes) formatBytes;
  final double horizontalInset;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    final l10n = context.l10n;
    final node = focus;
    final padding = EdgeInsets.fromLTRB(
      horizontalInset,
      0,
      horizontalInset,
      AppleSpacing.xxs,
    );
    if (node == null) {
      return Padding(
        padding: padding,
        child: Material(
          color: v.canvas,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppleRadius.sm),
            side: BorderSide(color: v.hairline),
          ),
          child: SizedBox(
            height: 36,
            child: Center(
              child: Text(l10n.previewSelectPrompt, style: context.vwFinePrint),
            ),
          ),
        ),
      );
    }

    final isDir = node.isDirectory;
    final size = isDir ? node.displayBytes : node.sizeBytes;
    final subtreeItems = isDir ? node.fileCount : 0;
    final category = isDir ? l10n.previewFolderCategory : node.category;
    final entryId = node.entryId;
    final selectId = entryId ?? (isDir ? node.path : null);
    final marked = selectId != null && selected(selectId);
    return Padding(
      padding: padding,
      child: Material(
        color: v.canvas,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          side: BorderSide(color: v.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppleSpacing.sm,
              vertical: AppleSpacing.xxs,
            ),
            child: Row(
              children: [
                Icon(
                  isDir ? Icons.folder : Icons.insert_drive_file_outlined,
                  size: 22,
                  color: isDir ? v.folderIcon : v.inkMuted48,
                ),
                const SizedBox(width: AppleSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        node.name,
                        style: context.vwCaptionStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${isDir && !node.scanned ? '—' : formatBytes(size)} · $category'
                        '${isDir ? ' · ${l10n.previewItemCount(subtreeItems)}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.vwFinePrint,
                      ),
                    ],
                  ),
                ),
                if (selectId != null && category != 'System')
                  Checkbox(
                    value: marked,
                    onChanged: busy ? null : (_) => onToggleSelection(node),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
