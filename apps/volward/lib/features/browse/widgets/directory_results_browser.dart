import 'package:flutter/material.dart';
import 'package:volward/features/browse/controllers/directory_browse_controller.dart';
import 'package:volward/features/browse/controllers/directory_details_query.dart';
import 'package:volward/features/browse/widgets/scan_column_view.dart';
import 'package:volward/l10n/l10n.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/theme/apple_tokens.dart';
import 'package:volward/theme/volward_tokens.dart';

/// The column browser and its empty states. Reads only the query and browse
/// controllers plus plain flags — no page State.
class DirectoryResultsBrowser extends StatelessWidget {
  const DirectoryResultsBrowser({
    super.key,
    required this.displayTree,
    required this.matchingCount,
    required this.scanning,
    required this.deleting,
    required this.hasIndexApi,
    required this.refreshingPaths,
    required this.peekInFlight,
    required this.query,
    required this.browseController,
    required this.onSelect,
    required this.formatBytes,
  });

  final ScanTreeNode? displayTree;
  final int matchingCount;
  final bool scanning;
  final bool deleting;
  final bool hasIndexApi;
  final Set<String> refreshingPaths;
  final Set<String> peekInFlight;
  final DirectoryQueryController query;
  final DirectoryBrowseController browseController;
  final ValueChanged<ScanColumnTap> onSelect;
  final String Function(num? bytes) formatBytes;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    if (displayTree == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: v.canvas,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          border: Border.all(color: v.hairline),
        ),
        child: Center(
          child: Text(
            scanning
                ? context.l10n.resultsUpdating
                : matchingCount == 0
                ? context.l10n.resultsNoFilterMatches
                : context.l10n.resultsNoFilterMatchesWithCount(matchingCount),
            style: context.vwFinePrint,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // When the catalog index API is available, the old tree's children may be
    // empty even though Rust has real results (e.g. after a catalog-only
    // refresh, or for a root that was built from a preview stub). Skip the
    // empty-tree short-circuit in that case and let the query controller
    // schedule the appropriate cached query outside the build pass.
    final cache = browseController.visibleChildrenCache;
    final treeChildrenEmpty = displayTree!.children.isEmpty;
    final rootKey = query.visibleChildrenKeyFor(displayTree!);
    final cachedRootChildren =
        cache.peek(rootKey) ?? cache.latestForPath(displayTree!.path);
    final catalogQueryPending = browseController.pendingVisibleChildrenQueries
        .contains(rootKey);
    if (hasIndexApi && cachedRootChildren == null && !catalogQueryPending) {
      query.scheduleVisibleChildrenQuery(
        rootKey,
        displayTree!,
        preferTree: query.shouldUseTreeChildrenFor(displayTree!),
      );
    }
    // Only skip the empty-state when the catalog API is present and the root
    // is either already cached, still pending, or still scanning. For old
    // builds or genuinely empty directories, the friendly empty-state is
    // still shown.
    final catalogMayHaveChildren =
        hasIndexApi &&
        (catalogQueryPending ||
            cachedRootChildren?.isNotEmpty == true ||
            scanning);
    if (treeChildrenEmpty && !catalogMayHaveChildren) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: v.canvas,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          border: Border.all(color: v.hairline),
        ),
        child: Center(
          child: Text(
            context.l10n.resultsNoFilesUnder(displayTree!.path),
            style: context.vwFinePrint,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final columnChain = browseController.columnChain;
    return ScanColumnView(
      root: displayTree!,
      visibleChildren: query.visibleChildrenFor(displayTree!),
      visibleChildrenByPath: {
        for (final node in columnChain)
          node.path: query.visibleChildrenFor(node),
      },
      loadingChildrenPaths: {
        if (query.isPreparingVisibleChildren(displayTree!)) displayTree!.path,
        for (final node in columnChain)
          if (query.isPreparingVisibleChildren(node)) node.path,
      },
      childrenPreSorted:
          hasIndexApi &&
          !query.showingPreviewSnapshot &&
          browseController.categoryFilter == null &&
          !browseController.deletableOnly,
      selectionChain: List.unmodifiable(columnChain),
      onSelect: onSelect,
      formatBytes: formatBytes,
      selectedEntryIds: Set.unmodifiable(browseController.selected),
      peekInFlight: peekInFlight,
      busy: deleting || scanning || refreshingPaths.isNotEmpty,
      sortMode: query.sortMode,
      categoryFilter: browseController.categoryFilter,
      deletableOnly: browseController.deletableOnly,
    );
  }
}
