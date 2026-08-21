import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../storage_home_summary.dart';
import '../../theme/apple_tokens.dart';
import '../../theme/volward_tokens.dart';
import 'dashboard_theme.dart';

/// Home dashboard middle block: the largest direct children of the selected
/// target, with bars normalized to the largest item.
class LargestItemsPanel extends StatelessWidget {
  const LargestItemsPanel({
    super.key,
    required this.summary,
    required this.maxItems,
    required this.onOpenItem,
  });

  static const panelKey = Key('storage-overview-largest-items');
  static const emptyKey = Key('storage-overview-largest-items-empty');
  static const progressKey = Key('storage-overview-largest-items-progress');

  static Key rowKey(String path) => ValueKey('storage-largest-item-$path');

  final StorageHomeSummary summary;
  final int maxItems;
  final ValueChanged<StorageHomeItem>? onOpenItem;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = summary.largestItems.take(maxItems).toList(growable: false);
    return KeyedSubtree(
      key: panelKey,
      child: DecoratedBox(
        decoration: dashboardPanelDecoration(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppleSpacing.lg,
            18,
            AppleSpacing.lg,
            18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.homeLargestItems,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.vwCaptionStrong.copyWith(
                        color: kOnDashboard.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                  if (summary.scannedBytes != null)
                    Text(
                      l10n.homeLargestItemsTotal(
                        formatStorageBytes(summary.scannedBytes),
                      ),
                      style: context.vwFinePrint.copyWith(
                        color: kOnDashboard.withValues(alpha: 0.58),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(child: _body(context, items)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, List<StorageHomeItem> items) {
    // Show progress bar only during an active scan (scanProgress != null).
    // During cache restore scanning=true but scanProgress=null — fall through
    // to the skeleton rows so the panel stays consistent with the rest of the UI.
    if (summary.scanning && summary.scanProgress != null) {
      return _progress(context);
    }
    if (summary.scanning) return _empty(context);
    if (items.isNotEmpty) return _rows(context, items);
    return _empty(context);
  }

  Widget _progress(BuildContext context) {
    final phase = localizedScanPhase(context, summary.scanPhase);
    return Column(
      key: progressKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Text(
            phase,
            style: context.vwFinePrint.copyWith(
              color: kOnDashboard.withValues(alpha: 0.68),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: phase,
          value: summary.scanProgress == null
              ? null
              : '${(summary.scanProgress! * 100).round()}%',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              key: const ValueKey('storage-scan-progress'),
              value: summary.scanProgress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: Colors.white.withValues(alpha: 0.10),
              color: context.volward.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final l10n = context.l10n;
    final scannedEmpty = summary.hasCompletedScan;
    return Column(
      key: emptyKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!scannedEmpty) ...[
          for (final width in const [1.0, 0.72, 0.48]) ...[
            ExcludeSemantics(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: width,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const SizedBox(height: 9),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 2),
        ],
        Text(
          scannedEmpty ? l10n.homeFolderEmpty : l10n.homeLargestItemsEmpty,
          textAlign: TextAlign.center,
          style: context.vwFinePrint.copyWith(
            color: kOnDashboard.withValues(alpha: 0.42),
          ),
        ),
      ],
    );
  }

  Widget _rows(BuildContext context, List<StorageHomeItem> items) {
    // Guard the divisor: an all-zero directory must render no bars, not NaN.
    final maxBytes = items.first.sizeBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++)
          _LargestItemRow(
            key: rowKey(items[i].path),
            item: items[i],
            rank: i + 1,
            total: items.length,
            fraction: maxBytes <= 0 ? 0 : items[i].sizeBytes / maxBytes,
            onTap: onOpenItem == null ? null : () => onOpenItem!(items[i]),
          ),
      ],
    );
  }
}

class _LargestItemRow extends StatelessWidget {
  const _LargestItemRow({
    super.key,
    required this.item,
    required this.rank,
    required this.total,
    required this.fraction,
    required this.onTap,
  });

  final StorageHomeItem item;
  final int rank;
  final int total;
  final double fraction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // A partial subtree total gets a trailing '+' rather than a confident
    // number the scan cannot yet back up.
    final sizeLabel =
        '${formatStorageBytes(item.sizeBytes)}${item.scanned ? '' : '+'}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Semantics(
          button: onTap != null,
          label: l10n.homeLargestItemsSemantics(
            item.name,
            sizeLabel,
            rank,
            total,
          ),
          onTap: onTap,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        item.isDirectory
                            ? Icons.folder_outlined
                            : Icons.insert_drive_file_outlined,
                        size: 13,
                        color: kOnDashboard.withValues(alpha: 0.52),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Tooltip(
                          message: item.path,
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.vwFinePrint.copyWith(
                              color: kOnDashboard.withValues(alpha: 0.86),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        sizeLabel,
                        style: context.vwFinePrint.copyWith(
                          color: kOnDashboard.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: fraction.clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: Colors.white.withValues(alpha: 0.07),
                      color: context.volward.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
