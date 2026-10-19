import 'package:flutter/material.dart';

import '../ai/ai_provider.dart';
import '../scan_tree.dart';
import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';

enum AiResultEntryTileVariant { previewSafe, previewReview, listRow }

/// Splits a filesystem path into a display basename and optional parent directory.
(String basename, String? parentDirectory) entryPathParts(String path) {
  if (path.isEmpty) {
    return ('', null);
  }
  final normalized = normalizeFsPath(path);
  final basename = lastPathSegment(normalized);
  final slash = normalized.lastIndexOf('/');
  if (slash <= 0) {
    return (basename, null);
  }
  final parent = normalized.substring(0, slash);
  if (parent.isEmpty || parent == normalized) {
    return (basename, null);
  }
  return (basename, parent);
}

/// Shared AI result row content: basename, parent path, reason, and optional meta.
class AiResultEntryTile extends StatelessWidget {
  const AiResultEntryTile({
    super.key,
    required this.item,
    required this.sizeLabel,
    required this.variant,
    this.cleanupMeta,
    this.reviewStatusLabel,
    this.maxReasonLines = 3,
    this.showInlineSize = true,
  });

  final AiVerdict item;
  final String sizeLabel;
  final AiResultEntryTileVariant variant;
  final String? cleanupMeta;
  final String? reviewStatusLabel;
  final int maxReasonLines;
  final bool showInlineSize;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    final (displayName, parentPath) = entryPathParts(item.path);
    final metaParts = <String>[item.confidence];
    if (cleanupMeta != null && cleanupMeta!.isNotEmpty) {
      metaParts.add(cleanupMeta!);
    }
    final metaLine = metaParts.join(' · ');
    final showMeta =
        variant != AiResultEntryTileVariant.listRow || metaParts.length > 1;
    final reviewLabel = reviewStatusLabel?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    value: item.path,
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.vwCaptionStrong,
                    ),
                  ),
                  if (parentPath != null) ...[
                    const SizedBox(height: AppleSpacing.xxs),
                    Text(
                      parentPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.vwFinePrint.copyWith(
                        color: tokens.inkMuted80,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showInlineSize) ...[
              const SizedBox(width: AppleSpacing.sm),
              Text(
                sizeLabel,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.vwCaptionStrong,
              ),
            ],
          ],
        ),
        if (item.reason.isNotEmpty) ...[
          const SizedBox(height: AppleSpacing.xxs),
          Text(
            item.reason,
            maxLines: maxReasonLines,
            overflow: TextOverflow.ellipsis,
            style: context.vwBody,
          ),
        ],
        if (showMeta && metaLine.isNotEmpty) ...[
          const SizedBox(height: AppleSpacing.xxs),
          Text(metaLine, style: context.vwCaption),
        ],
        if ((variant == AiResultEntryTileVariant.previewReview ||
                variant == AiResultEntryTileVariant.listRow) &&
            reviewLabel != null &&
            reviewLabel.isNotEmpty) ...[
          const SizedBox(height: AppleSpacing.xxs),
          Text(
            reviewLabel,
            style: context.vwCaption.copyWith(color: tokens.warning),
          ),
        ],
      ],
    );
  }
}
