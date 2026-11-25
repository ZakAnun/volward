import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:volward/features/browse/controllers/directory_browse_controller.dart';
import 'package:volward/features/browse/controllers/directory_details_query.dart';
import 'package:volward/features/browse/widgets/browse_results_pane.dart';
import 'package:volward/features/browse/widgets/directory_compact_chrome.dart';
import 'package:volward/features/browse/widgets/directory_results_browser.dart';
import 'package:volward/features/browse/widgets/item_preview.dart';
import 'package:volward/features/browse/widgets/scan_column_view.dart';
import 'package:volward/features/browse/widgets/scan_filter_bar.dart';
import 'package:volward/l10n/l10n.dart';
import 'package:volward/theme/apple_tokens.dart';
import 'directory_section_layout.dart';

/// Browse-mode results composition: chrome, column browser and item preview.
/// The page resolves the tree once per revision and hands this widget data
/// plus callbacks; nothing here touches the page State.
class DirectoryBrowseResults extends StatelessWidget {
  const DirectoryBrowseResults({
    super.key,
    required this.revision,
    required this.query,
    required this.browseController,
    required this.scanning,
    required this.deleting,
    required this.hasIndexApi,
    required this.refreshingPaths,
    required this.peekInFlight,
    required this.canRefresh,
    required this.onRescan,
    required this.onPickFolder,
    required this.showHomeAction,
    required this.onBrowseHome,
    required this.onPermission,
    required this.formatBytes,
  });

  final ValueListenable<int> revision;
  final DirectoryQueryController query;
  final DirectoryBrowseController browseController;
  final bool scanning;
  final bool deleting;
  final bool hasIndexApi;
  final Set<String> refreshingPaths;
  final Set<String> peekInFlight;
  final bool canRefresh;
  final VoidCallback? onRescan;
  final VoidCallback onPickFolder;
  final bool showHomeAction;
  final VoidCallback onBrowseHome;
  final DirectoryPermissionSlot onPermission;
  final String Function(num? bytes) formatBytes;

  @override
  Widget build(BuildContext context) {
    return BrowseResultsPane(
      revision: revision,
      builder: (context) {
        final displayTree = query.resolveResultTree();
        final matchingCount = query.matchingEntryCount();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DirectoryCompactChrome(
              summary: query.compactResultsSummary(displayTree, matchingCount),
              targetLabel: query.session.scanRoots.isEmpty
                  ? context.l10n.scanTargetHomeShort
                  : context.l10n.scanTargetCustomShort,
              scanning: scanning,
              scannedFraction: query.scanPresentationController.scannedFraction,
              canRefresh: canRefresh && !deleting && !scanning,
              onRescan: onRescan,
              onPickFolder: onPickFolder,
              showHomeAction: showHomeAction,
              onBrowseHome: onBrowseHome,
              permissionBanner: onPermission(context),
              categoryFilter: browseController.categoryFilter,
              presentCategories: {
                if (query.snapshotMatchesCurrentRoot())
                  for (final entry
                      in (query.session.lastSnapshot?.categoryCounts ??
                              const <String, int>{})
                          .entries)
                    if (entry.value > 0 &&
                        ScanFilterBar.categoryOptions.contains(entry.key))
                      entry.key,
              },
              onCategoryChanged: (category) {
                query.applySetState(() {
                  browseController.categoryFilter = category;
                  query.resetColumnNav();
                });
              },
              sortMode: query.sortMode,
              onSortChanged: (mode) {
                // Sort is applied at render time by ScanColumnView — no
                // isolate, no tree copy, zero latency.
                query.applySetState(() {
                  browseController.sortIndex = mode.index;
                });
              },
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: browseController.columnNavTick,
                builder: (context, _) {
                  final focus = scanColumnFocusNode(
                    browseController.columnChain,
                  );
                  return Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: padDirectorySectionExpanded(
                              DirectoryResultsBrowser(
                                displayTree: displayTree,
                                matchingCount: matchingCount,
                                scanning: scanning,
                                deleting: deleting,
                                hasIndexApi: hasIndexApi,
                                refreshingPaths: refreshingPaths,
                                peekInFlight: peekInFlight,
                                query: query,
                                browseController: browseController,
                                onSelect: query.onColumnSelect,
                                formatBytes: formatBytes,
                              ),
                              padding: const EdgeInsets.fromLTRB(
                                directoryDetailHorizontalInset,
                                0,
                                directoryDetailHorizontalInset,
                                AppleSpacing.xxs,
                              ),
                            ),
                          ),
                          ItemPreview(
                            focus: focus,
                            selected: browseController.selected.contains,
                            busy:
                                deleting ||
                                scanning ||
                                refreshingPaths.isNotEmpty,
                            onToggleSelection: query.toggleFocusedFileSelection,
                            formatBytes: formatBytes,
                            horizontalInset: directoryDetailHorizontalInset,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Builds the permission banner slot from data the page supplies.
typedef DirectoryPermissionSlot = Widget? Function(BuildContext context);
