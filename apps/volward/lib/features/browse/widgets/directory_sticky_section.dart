import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:volward/features/browse/controllers/directory_details_helpers.dart';
import 'package:volward/features/browse/widgets/sticky_action_bar.dart';
import 'package:volward/l10n/l10n.dart';
import 'package:volward/theme/apple_tokens.dart';
import 'package:volward/theme/volward_tokens.dart';
import 'package:volward/widgets/apple_widgets.dart';

/// Bottom action bar for browse mode. Computes its label and actions from
/// plain data and callbacks.
class DirectoryDetailsStickyBar extends StatelessWidget {
  const DirectoryDetailsStickyBar({
    super.key,
    required this.scanning,
    required this.deleting,
    required this.scanStartPending,
    required this.refreshing,
    required this.hasResults,
    required this.ready,
    required this.peekCount,
    required this.deleteCount,
    required this.deleteBytes,
    required this.scannedFraction,
    required this.elapsedLabel,
    required this.progressSummary,
    required this.canRefresh,
    required this.onRescan,
    required this.onCancelScan,
    required this.onStartScan,
    required this.onConfirmDelete,
    required this.onConfirmEmptyTrash,
  });

  final bool scanning;
  final bool deleting;
  final bool scanStartPending;
  final bool refreshing;
  final bool hasResults;
  final bool ready;
  final int peekCount;
  final int deleteCount;
  final int deleteBytes;
  final ValueListenable<double?> scannedFraction;
  final ValueListenable<String?> elapsedLabel;
  final String Function() progressSummary;
  final bool canRefresh;
  final VoidCallback? onRescan;
  final VoidCallback onCancelScan;
  final VoidCallback? onStartScan;
  final VoidCallback onConfirmDelete;
  final VoidCallback onConfirmEmptyTrash;

  @override
  Widget build(BuildContext context) {
    final busy = deleting || scanning || scanStartPending || refreshing;
    final l10n = context.l10n;
    final String label;
    final String actionLabel;
    final VoidCallback? actionPressed;
    final IconData? actionIcon;

    if (scanning) {
      // Elapsed ticks via the scan presentation controller below; the label
      // is built there.
      label = '';
      actionLabel = l10n.scanActionCancel;
      actionIcon = Icons.stop_outlined;
      actionPressed = onCancelScan;
    } else {
      if (hasResults) {
        label = deleteCount > 0
            ? l10n.stickySelected(
                deleteCount,
                formatDirectoryBytes(deleteBytes),
              )
            : peekCount > 0
            ? l10n.stickyDirectoriesLoading(peekCount)
            : l10n.stickyBrowseResults;
        // Refresh targets the currently focused directory. The root uses a
        // full scan; a child directory uses a scoped peek scan.
        actionLabel = busy ? '' : l10n.scanActionRescan;
        actionIcon = busy ? null : Icons.refresh_outlined;
        actionPressed = (busy || !canRefresh) ? null : onRescan;
      } else {
        label = ready ? l10n.stickyReadyToScan : l10n.stickyLoadingEngine;
        actionLabel = l10n.scanActionStart;
        actionIcon = Icons.search;
        actionPressed = onStartScan;
      }
    }

    // During a scan, progress % arrives via scannedFractionNotifier (deferred
    // tree walk) and elapsed via scanElapsedNotifier (1 Hz) — wrap both so the
    // sticky label updates without rebuilding the whole page.
    final Widget leading = scanning
        ? ValueListenableBuilder<double?>(
            valueListenable: scannedFraction,
            builder: (context, _, __) {
              return ValueListenableBuilder<String?>(
                valueListenable: elapsedLabel,
                builder: (context, _, __) =>
                    Text(progressSummary(), style: context.vwCaption),
              );
            },
          )
        : Text(label, style: context.vwCaption);

    return StickyActionBar(
      leading: leading,
      action: (scanning || !hasResults)
          ? AppleButton(
              label: actionLabel,
              icon: actionIcon,
              onPressed: actionPressed,
            )
          : Wrap(
              alignment: WrapAlignment.end,
              spacing: AppleSpacing.xs,
              runSpacing: AppleSpacing.xs,
              children: [
                AppleButton(
                  label: l10n.trashActionEmpty,
                  icon: Icons.delete_sweep_outlined,
                  variant: AppleButtonVariant.pearl,
                  onPressed: busy ? null : onConfirmEmptyTrash,
                ),
                AppleButton(
                  label: deleting
                      ? l10n.deleteActionWorking
                      : l10n.deleteActionMoveToTrash,
                  icon: deleting ? null : Icons.delete_outline,
                  onPressed: deleteCount > 0 && !busy ? onConfirmDelete : null,
                ),
              ],
            ),
    );
  }
}
