import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:volward/features/browse/scan_sort_mode.dart';
import 'package:volward/features/browse/widgets/scan_filter_bar.dart';
import 'package:volward/l10n/l10n.dart';
import 'package:volward/theme/apple_tokens.dart';
import 'package:volward/theme/volward_tokens.dart';
import 'package:volward/widgets/apple_widgets.dart';
import 'directory_section_layout.dart';

const Key directoryBrowseFolderActionKey = Key('volward-browse-folder-action');
const Key directoryBrowseHomeActionKey = Key('volward-browse-home-action');

/// Results header: summary text, target chip, refresh, filter bar and the
/// permission banner slot. Data in, callbacks out.
class DirectoryCompactChrome extends StatelessWidget {
  const DirectoryCompactChrome({
    super.key,
    required this.summary,
    required this.targetLabel,
    required this.scanning,
    required this.scannedFraction,
    required this.canRefresh,
    required this.onRescan,
    required this.onPickFolder,
    required this.showHomeAction,
    required this.onBrowseHome,
    required this.permissionBanner,
    required this.categoryFilter,
    required this.presentCategories,
    required this.sortMode,
    required this.onCategoryChanged,
    required this.onSortChanged,
  });

  final String summary;
  final String targetLabel;
  final bool scanning;
  final ValueListenable<double?> scannedFraction;
  final bool canRefresh;
  final VoidCallback? onRescan;
  final VoidCallback onPickFolder;
  final bool showHomeAction;
  final VoidCallback onBrowseHome;
  final Widget? permissionBanner;
  final String? categoryFilter;
  final Set<String> presentCategories;
  final ScanSortMode sortMode;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<ScanSortMode> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return padDirectorySection(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (permissionBanner != null) ...[
            permissionBanner!,
            const SizedBox(height: AppleSpacing.xxs),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  summary,
                  style: context.vwFinePrintInk,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppleSpacing.xs),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(targetLabel, style: context.vwFinePrint),
                  if (scanning) ...[
                    const SizedBox(width: 4),
                    ValueListenableBuilder<double?>(
                      valueListenable: scannedFraction,
                      builder: (ctx, frac, _) {
                        return Text(
                          frac != null ? '${(frac * 100).round()}%' : '…',
                          style: ctx.vwFinePrint.copyWith(
                            color: ctx.volward.primary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
              const SizedBox(width: AppleSpacing.xs),
              Tooltip(
                message: context.l10n.scanActionRescan,
                child: IconButton(
                  icon: Icon(
                    Icons.refresh_outlined,
                    size: 18,
                    color: context.volward.inkMuted80,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: canRefresh ? onRescan : null,
                ),
              ),
              const SizedBox(width: AppleSpacing.xxs),
              AppleButton(
                key: directoryBrowseFolderActionKey,
                label: context.l10n.scanActionFolder,
                icon: Icons.folder_open_outlined,
                variant: AppleButtonVariant.pearl,
                onPressed: onPickFolder,
              ),
              if (showHomeAction) ...[
                const SizedBox(width: AppleSpacing.xxs),
                AppleButton(
                  key: directoryBrowseHomeActionKey,
                  label: context.l10n.scanActionHome,
                  icon: Icons.home_outlined,
                  variant: AppleButtonVariant.pearl,
                  onPressed: onBrowseHome,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppleSpacing.xxs),
          ScanFilterBar(
            categoryFilter: categoryFilter,
            presentCategories: presentCategories,
            onCategoryChanged: onCategoryChanged,
            sortMode: sortMode,
            onSortChanged: onSortChanged,
            scanning: scanning,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(
        directoryDetailHorizontalInset,
        AppleSpacing.xxs,
        directoryDetailHorizontalInset,
        AppleSpacing.xxs,
      ),
    );
  }
}
