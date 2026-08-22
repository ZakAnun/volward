import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../storage_home_summary.dart';
import '../storage_overview.dart';
import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';
import 'home/category_breakdown.dart';
import 'home/dashboard_theme.dart';
import 'home/largest_items_panel.dart';
import 'home/skeleton_loader.dart';
import 'volward_logo.dart';

const _dashboardInk = kDashboardInk;
const _dashboardSoft = Color(0xFF1A1A1E);
const _onDashboard = kOnDashboard;
const _liveChipFill = Color(0x2934C759);
const _liveChipLine = Color(0x3834C759);
const _liveChipText = Color(0xFFD5FFD9);
const _volumeFocusOrder = 0.0;
const _targetFocusOrderStart = 100.0;
const _chooseFolderFocusOrder = 10000.0;
const _browseFocusOrder = 10001.0;
const _aiFocusOrder = 10001.5;
const _scanFocusOrder = 10002.0;
const _settingsFocusOrder = 10003.0;
const _dashboardControlHeight = 32.0; // Reduced from 36 to save vertical space
const _wideSidebarWidth = 216.0;
const _panelGap = 14.0;
const _sidebarPadding = 18.0;
const _sidebarLogoHeight = 104.0;
const _sidebarLogoGap = 18.0;
const _targetTileHeight = 44.0;
const _targetTileGap = 10.0;

// Flex ratios for the right panel. They track the intrinsic heights summed at
// the bottom of this file (capacity is the tallest, browse next, largest
// smallest), rounded so capacity keeps its content whole.
const _capacityFlex = 35;
const _largestFlex = 32;
const _browseFlex = 34;

Color _glass(double whiteAlpha) => dashboardGlass(whiteAlpha);

Color _dashboardAccent(BuildContext context, double alpha) {
  return context.volward.primary.withValues(alpha: alpha);
}

Color _dashboardBase(BuildContext context) {
  return Color.alphaBlend(_dashboardAccent(context, 0.10), _dashboardInk);
}

Color _dashboardSoftBase(BuildContext context) {
  return Color.alphaBlend(_dashboardAccent(context, 0.08), _dashboardSoft);
}

LinearGradient _dashboardGradient(BuildContext context) {
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      _dashboardBase(context),
      _dashboardSoftBase(context),
      _dashboardAccent(context, 0.42),
    ],
    stops: const [0, 0.55, 1],
  );
}

LinearGradient _meterGradient(BuildContext context) {
  final primary = context.volward.primary;
  final start = Color.lerp(primary, Colors.white, 0.46) ?? primary;
  final end = Color.lerp(primary, Colors.black, 0.06) ?? primary;
  return LinearGradient(colors: [start, end]);
}

TextStyle _dashboardControlTextStyle(BuildContext context, Color color) {
  return context.vwCaptionStrong.copyWith(color: color);
}

class StorageStewardHome extends StatelessWidget {
  const StorageStewardHome({
    super.key,
    required this.summary,
    required this.onBrowse,
    required this.onChooseFolder,
    required this.onSelectTarget,
    required this.onScan,
    required this.onCancelScan,
    this.onOpenSettings,
    this.onSelectCategory,
    this.onOpenItem,
    this.onOpenAi,
    this.mainPaneOverride,
    this.interactionsLocked = false,
    this.aiActionFocusNode,
  });

  static const backgroundColor = Color(0xFF111113);
  static const panelKey = Key('storage-overview-panel');
  static const panelBackgroundKey = Key('storage-overview-background');
  static const capacityKey = Key('storage-overview-capacity');
  static const targetsKey = Key('storage-overview-targets');
  static const chooseFolderKey = Key('storage-overview-choose-folder');
  static const browseKey = Key('storage-overview-browse');
  static const scanActionKey = Key('storage-overview-scan-action');
  static const volumeSelectorKey = Key('storage-overview-volume-selector');
  static const capacityMeterKey = Key('storage-overview-capacity-meter');
  static const capacityPathKey = Key('storage-overview-capacity-path');
  static const dashboardSurfaceKey = Key('storage-overview-dashboard-surface');
  static const contentViewportKey = Key('storage-overview-content-viewport');
  static const boardKey = Key('storage-overview-board');
  static const browseCardKey = Key('storage-overview-browse-card');
  static const aiActionKey = Key('storage-overview-ai-action');
  static const mainPaneKey = Key('storage-overview-main-pane');
  static const categoryPieKey = CategoryBreakdown.pieKey;
  static const statusChipKey = Key('storage-overview-status-chip');
  static const actionsKey = Key('storage-overview-actions');
  static const settingsKey = Key('storage-overview-settings');
  static const recentFoldersKey = Key('storage-overview-recent-folders');

  final StorageHomeSummary summary;
  final VoidCallback onBrowse;
  final VoidCallback onChooseFolder;
  final ValueChanged<StorageLocationInfo> onSelectTarget;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;
  final VoidCallback? onOpenSettings;
  final ValueChanged<String>? onSelectCategory;
  final ValueChanged<StorageHomeItem>? onOpenItem;
  final VoidCallback? onOpenAi;
  final Widget? mainPaneOverride;
  final bool interactionsLocked;
  final FocusNode? aiActionFocusNode;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return _HeroVisual(
          summary: summary,
          compact: compact,
          onBrowse: onBrowse,
          onChooseFolder:
              interactionsLocked || summary.scanning ? null : onChooseFolder,
          onSelectTarget: interactionsLocked ? null : onSelectTarget,
          onScan: onScan,
          onCancelScan: onCancelScan,
          onOpenSettings: onOpenSettings,
          onSelectCategory: onSelectCategory,
          onOpenItem: onOpenItem,
          onOpenAi: onOpenAi,
          mainPaneOverride: mainPaneOverride,
          interactionsLocked: interactionsLocked,
          aiActionFocusNode: aiActionFocusNode,
        );
      },
    );
  }
}

class _HeroVisual extends StatelessWidget {
  const _HeroVisual({
    required this.summary,
    required this.compact,
    required this.onBrowse,
    required this.onChooseFolder,
    required this.onSelectTarget,
    required this.onScan,
    required this.onCancelScan,
    required this.onOpenSettings,
    required this.onSelectCategory,
    required this.onOpenItem,
    required this.onOpenAi,
    required this.mainPaneOverride,
    required this.interactionsLocked,
    required this.aiActionFocusNode,
  });

  final StorageHomeSummary summary;
  final bool compact;
  final VoidCallback onBrowse;
  final VoidCallback? onChooseFolder;
  final ValueChanged<StorageLocationInfo>? onSelectTarget;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;
  final VoidCallback? onOpenSettings;
  final ValueChanged<String>? onSelectCategory;
  final ValueChanged<StorageHomeItem>? onOpenItem;
  final VoidCallback? onOpenAi;
  final Widget? mainPaneOverride;
  final bool interactionsLocked;
  final FocusNode? aiActionFocusNode;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Semantics(
        key: StorageStewardHome.panelKey,
        container: true,
        explicitChildNodes: true,
        child: KeyedSubtree(
          key: StorageStewardHome.panelBackgroundKey,
          child: DecoratedBox(
            key: StorageStewardHome.dashboardSurfaceKey,
            decoration: BoxDecoration(
              color: _dashboardBase(context),
              gradient: _dashboardGradient(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeroTopbar(
                  summary: summary,
                  compact: compact,
                  onChooseFolder: onChooseFolder,
                  onSelectTarget: onSelectTarget,
                  onOpenSettings: onOpenSettings,
                ),
                Expanded(
                  child: LayoutBuilder(
                    key: StorageStewardHome.contentViewportKey,
                    builder: (context, viewport) {
                      final board = Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 16 : AppleSpacing.lg,
                          0,
                          compact ? 16 : AppleSpacing.lg,
                          compact ? 16 : AppleSpacing.lg,
                        ),
                        child: compact
                            ? _CompactBoard(
                                summary: summary,
                                availableHeight: viewport.maxHeight,
                                onSelectTarget: onSelectTarget,
                                onBrowse: onBrowse,
                                onScan: onScan,
                                onCancelScan: onCancelScan,
                                onSelectCategory: onSelectCategory,
                                onOpenItem: onOpenItem,
                                onOpenAi: onOpenAi,
                                mainPaneOverride: mainPaneOverride,
                                interactionsLocked: interactionsLocked,
                                aiActionFocusNode: aiActionFocusNode,
                              )
                            : _WideBoard(
                                summary: summary,
                                onSelectTarget: onSelectTarget,
                                onBrowse: onBrowse,
                                onScan: onScan,
                                onCancelScan: onCancelScan,
                                onSelectCategory: onSelectCategory,
                                onOpenItem: onOpenItem,
                                onOpenAi: onOpenAi,
                                mainPaneOverride: mainPaneOverride,
                                interactionsLocked: interactionsLocked,
                                aiActionFocusNode: aiActionFocusNode,
                              ),
                      );
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          key: StorageStewardHome.boardKey,
                          constraints: BoxConstraints(
                            minHeight: math.max(
                              _wideDashboardHeight(summary, context),
                              viewport.maxHeight,
                            ),
                          ),
                          child: board,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroTopbar extends StatelessWidget {
  const _HeroTopbar({
    required this.summary,
    required this.compact,
    required this.onChooseFolder,
    required this.onSelectTarget,
    required this.onOpenSettings,
  });

  final StorageHomeSummary summary;
  final bool compact;
  final VoidCallback? onChooseFolder;
  final ValueChanged<StorageLocationInfo>? onSelectTarget;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final volumeChoices = _volumeChoices(summary);
    final selector = volumeChoices.length < 2
        ? null
        : FocusTraversalOrder(
            order: const NumericFocusOrder(_volumeFocusOrder),
            child: _VolumeSelector(
              locations: volumeChoices,
              selectedPath: summary.selectedLocation?.path ?? '',
              selectedVolumeId: summary.selectedVolume?.id,
              enabled: !summary.scanning && onSelectTarget != null,
              onSelected: onSelectTarget ?? (_) {},
            ),
          );
    final chooseFolder = SizedBox(
      width: 168,
      child: FocusTraversalOrder(
        order: const NumericFocusOrder(_chooseFolderFocusOrder),
        child: _DashboardActionButton(
          key: StorageStewardHome.chooseFolderKey,
          label: l10n.homeChooseFolder,
          icon: Icons.folder_open_outlined,
          primary: false,
          onPressed: onChooseFolder,
        ),
      ),
    );
    final settings = onOpenSettings == null
        ? null
        : FocusTraversalOrder(
            order: const NumericFocusOrder(_settingsFocusOrder),
            child: IconButton(
              key: StorageStewardHome.settingsKey,
              tooltip: l10n.settingsTooltip,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(
                Icons.settings_outlined,
                size: 18,
                color: _onDashboard,
              ),
              onPressed: onOpenSettings,
            ),
          );
    final brand = Row(
      children: [
        const VolwardLogoMark(size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Volward',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.vwCaptionStrong.copyWith(color: _onDashboard),
          ),
        ),
      ],
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: brand),
                if (settings != null) settings,
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [if (selector != null) selector, chooseFolder],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppleSpacing.lg,
        18,
        AppleSpacing.lg,
        14,
      ),
      child: Row(
        children: [
          Expanded(child: brand),
          if (selector != null) ...[const SizedBox(width: 12), selector],
          const SizedBox(width: 12),
          chooseFolder,
          if (settings != null) ...[const SizedBox(width: 4), settings],
        ],
      ),
    );
  }
}

class _WideBoard extends StatelessWidget {
  const _WideBoard({
    required this.summary,
    required this.onSelectTarget,
    required this.onBrowse,
    required this.onScan,
    required this.onCancelScan,
    required this.onSelectCategory,
    required this.onOpenItem,
    required this.onOpenAi,
    required this.mainPaneOverride,
    required this.interactionsLocked,
    required this.aiActionFocusNode,
  });

  final StorageHomeSummary summary;
  final ValueChanged<StorageLocationInfo>? onSelectTarget;
  final VoidCallback onBrowse;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;
  final ValueChanged<String>? onSelectCategory;
  final ValueChanged<StorageHomeItem>? onOpenItem;
  final VoidCallback? onOpenAi;
  final Widget? mainPaneOverride;
  final bool interactionsLocked;
  final FocusNode? aiActionFocusNode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _wideDashboardHeight(summary, context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _wideSidebarWidth,
            child: KeyedSubtree(
              key: StorageStewardHome.targetsKey,
              child: _Sidebar(summary: summary, onSelectTarget: onSelectTarget),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: KeyedSubtree(
              key: StorageStewardHome.mainPaneKey,
              child: mainPaneOverride ??
                  _MainPane(
                    summary: summary,
                    compact: false,
                    balancePanels: true,
                    onBrowse: onBrowse,
                    onScan: onScan,
                    onCancelScan: onCancelScan,
                    onSelectCategory: onSelectCategory,
                    onOpenItem: onOpenItem,
                    onOpenAi: onOpenAi,
                    interactionsLocked: interactionsLocked,
                    aiActionFocusNode: aiActionFocusNode,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactBoard extends StatelessWidget {
  const _CompactBoard({
    required this.summary,
    required this.availableHeight,
    required this.onSelectTarget,
    required this.onBrowse,
    required this.onScan,
    required this.onCancelScan,
    required this.onSelectCategory,
    required this.onOpenItem,
    required this.onOpenAi,
    required this.mainPaneOverride,
    required this.interactionsLocked,
    required this.aiActionFocusNode,
  });

  final StorageHomeSummary summary;
  final double availableHeight;
  final ValueChanged<StorageLocationInfo>? onSelectTarget;
  final VoidCallback onBrowse;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;
  final ValueChanged<String>? onSelectCategory;
  final ValueChanged<StorageHomeItem>? onOpenItem;
  final VoidCallback? onOpenAi;
  final Widget? mainPaneOverride;
  final bool interactionsLocked;
  final FocusNode? aiActionFocusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: StorageStewardHome.targetsKey,
          child: _Sidebar(summary: summary, onSelectTarget: onSelectTarget),
        ),
        const SizedBox(height: 14),
        KeyedSubtree(
          key: StorageStewardHome.mainPaneKey,
          child: mainPaneOverride == null
              ? _MainPane(
                  summary: summary,
                  compact: true,
                  balancePanels: false,
                  onBrowse: onBrowse,
                  onScan: onScan,
                  onCancelScan: onCancelScan,
                  onSelectCategory: onSelectCategory,
                  onOpenItem: onOpenItem,
                  onOpenAi: onOpenAi,
                  interactionsLocked: interactionsLocked,
                  aiActionFocusNode: aiActionFocusNode,
                )
              : SizedBox(
                  height: math.max(560.0, availableHeight),
                  child: mainPaneOverride,
                ),
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.summary, required this.onSelectTarget});

  final StorageHomeSummary summary;
  final ValueChanged<StorageLocationInfo>? onSelectTarget;

  @override
  Widget build(BuildContext context) {
    final targetLocations = _targetLocations(summary);
    final recentLocations = _recentCustomLocations(summary);
    final selectedPath = summary.selectedLocation?.path ?? '';
    final selectedCustom =
        summary.selectedLocation?.kind == StorageLocationKind.custom
        ? summary.selectedLocation
        : null;
    final recentMenuLocation =
        selectedCustom ??
        (recentLocations.isNotEmpty ? recentLocations.first : null);
    final recentMenuChoices = [
      if (selectedCustom != null) selectedCustom,
      for (final location in recentLocations)
        if (selectedCustom == null ||
            !_samePath(location.path, selectedCustom.path))
          location,
    ];
    Widget targetTile(int index) {
      final location = targetLocations[index];
      final selected = _samePath(location.path, selectedPath);
      final choices =
          location.kind == StorageLocationKind.custom &&
              recentMenuChoices.length > 1
          ? recentMenuChoices
          : const <StorageLocationInfo>[];
      return FocusTraversalOrder(
        order: NumericFocusOrder(_targetFocusOrderStart + index),
        child: _TargetMenuTile(
          location: location,
          choices: choices,
          selected: selected,
          enabled: !summary.scanning && onSelectTarget != null,
          onSelectTarget: onSelectTarget,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _glass(0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final recentFallback =
              recentMenuLocation != null &&
              !targetLocations.any(
                (location) => _samePath(location.path, recentMenuLocation.path),
              );
          final recentTile = recentFallback
              ? FocusTraversalOrder(
                  order: NumericFocusOrder(
                    _targetFocusOrderStart + targetLocations.length,
                  ),
                  child: _TargetMenuTile(
                    location: recentMenuLocation,
                    choices: recentMenuChoices,
                    selected: _samePath(recentMenuLocation.path, selectedPath),
                    recentFallback: true,
                    enabled: !summary.scanning && onSelectTarget != null,
                    onSelectTarget: onSelectTarget,
                  ),
                )
              : null;

          return Padding(
            padding: const EdgeInsets.all(_sidebarPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: _glass(0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const SizedBox(
                    height: _sidebarLogoHeight,
                    child: Center(child: VolwardLogoMark(size: 72)),
                  ),
                ),
                const SizedBox(height: _sidebarLogoGap),
                for (
                  var index = 0;
                  index < targetLocations.length;
                  index++
                ) ...[
                  targetTile(index),
                  if (index < targetLocations.length - 1)
                    const SizedBox(height: _targetTileGap),
                ],
                if (recentTile != null) ...[
                  const SizedBox(height: _targetTileGap),
                  recentTile,
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MainPane extends StatelessWidget {
  const _MainPane({
    required this.summary,
    required this.compact,
    required this.balancePanels,
    required this.onBrowse,
    required this.onScan,
    required this.onCancelScan,
    required this.onSelectCategory,
    required this.onOpenItem,
    required this.onOpenAi,
    required this.interactionsLocked,
    required this.aiActionFocusNode,
  });

  final StorageHomeSummary summary;
  final bool compact;
  final bool balancePanels;
  final VoidCallback onBrowse;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;
  final ValueChanged<String>? onSelectCategory;
  final ValueChanged<StorageHomeItem>? onOpenItem;
  final VoidCallback? onOpenAi;
  final bool interactionsLocked;
  final FocusNode? aiActionFocusNode;

  @override
  Widget build(BuildContext context) {
    final capacity = KeyedSubtree(
      key: StorageStewardHome.capacityKey,
      child: _StatPanel(summary: summary, compact: compact),
    );
    final largest = LargestItemsPanel(
      summary: summary,
      // Same constant the intrinsic-height sum below budgets rows for; a
      // literal here would drift from it.
      maxItems: _largestItemCount,
      onOpenItem: onOpenItem,
    );
    final composition = _BrowseCard(
      summary: summary,
      compact: compact,
      onBrowse: onBrowse,
      onScan: onScan,
      onCancelScan: onCancelScan,
      onSelectCategory: onSelectCategory,
      onOpenAi: onOpenAi,
      interactionsLocked: interactionsLocked,
      aiActionFocusNode: aiActionFocusNode,
    );
    if (balancePanels) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: _capacityFlex, child: capacity),
          const SizedBox(height: _panelGap),
          Expanded(flex: _largestFlex, child: largest),
          const SizedBox(height: _panelGap),
          Expanded(flex: _browseFlex, child: composition),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        capacity,
        const SizedBox(height: _panelGap),
        largest,
        const SizedBox(height: _panelGap),
        composition,
      ],
    );
  }
}

class _StatPanel extends StatelessWidget {
  const _StatPanel({required this.summary, required this.compact});

  final StorageHomeSummary summary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final volume = summary.selectedVolume;
    final usableVolume = summary.hasUsableCapacity ? volume : null;
    final used = formatStorageBytes(usableVolume?.usedBytes);
    final total = formatStorageBytes(usableVolume?.totalBytes);
    final available = formatStorageBytes(usableVolume?.availableBytes);
    final rawCapacityPath =
        volume?.rootPath ?? summary.selectedLocation?.path ?? '';
    final capacityPath = rawCapacityPath.isEmpty ? '—' : rawCapacityPath;

    return Semantics(
      label: l10n.homeCapacitySemantics(used, total, available),
      value: capacityPath,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _glass(0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 18 : AppleSpacing.lg,
                    compact ? 18 : 20, // Reduced from 22
                    compact ? 18 : AppleSpacing.lg,
                    compact ? 16 : 16, // Reduced from 18
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Tooltip(
                        message: capacityPath,
                        child: Text(
                          capacityPath,
                          key: StorageStewardHome.capacityPathKey,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.vwFinePrint.copyWith(
                            color: Colors.white.withValues(alpha: 0.58),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8), // Reduced from 10
                      Text(
                        used,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.vwDisplayLg.copyWith(
                          color: _onDashboard,
                          fontSize: compact ? 40 : 52,
                          fontWeight: FontWeight.w700,
                          height: 0.92,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.homeCapacityUsed,
                        style: context.vwFinePrint.copyWith(
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: 16), // Reduced from 18
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _CapacityMetric(
                              label: l10n.homeCapacityTotal,
                              value: total,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _CapacityMetric(
                              label: l10n.homeCapacityAvailable,
                              value: available,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Wide mode gives this panel a flex-bounded height, so the
                // meter is pinned to the card's bottom edge like every
                // neighbouring panel. Compact mode scrolls (unbounded height),
                // where a Spacer would assert — hence the fixed gap there.
                if (!compact) const Spacer() else const SizedBox(height: 10),
                _HeroMeter(summary: summary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CapacityMetric extends StatelessWidget {
  const _CapacityMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.vwBodyStrong.copyWith(color: _onDashboard),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 2,
          style: context.vwFinePrint.copyWith(
            color: Colors.white.withValues(alpha: 0.58),
          ),
        ),
      ],
    );
  }
}

class _HeroMeter extends StatelessWidget {
  const _HeroMeter({required this.summary});

  final StorageHomeSummary summary;

  @override
  Widget build(BuildContext context) {
    final progress = summary.hasUsableCapacity
        ? summary.selectedVolume?.usedFraction
        : null;
    return SizedBox(
      key: StorageStewardHome.capacityMeterKey,
      height: 12,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: _glass(0.12)),
          if (progress != null)
            FractionallySizedBox(
              widthFactor: progress.clamp(0, 1),
              alignment: Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: _meterGradient(context)),
              ),
            ),
        ],
      ),
    );
  }
}

class _BrowseCard extends StatelessWidget {
  const _BrowseCard({
    required this.summary,
    required this.compact,
    required this.onBrowse,
    required this.onScan,
    required this.onCancelScan,
    required this.onSelectCategory,
    required this.onOpenAi,
    required this.interactionsLocked,
    required this.aiActionFocusNode,
  });

  final StorageHomeSummary summary;
  final bool compact;
  final VoidCallback onBrowse;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;
  final ValueChanged<String>? onSelectCategory;
  final VoidCallback? onOpenAi;
  final bool interactionsLocked;
  final FocusNode? aiActionFocusNode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Restoring a cached snapshot also sets `scanning` so the dashboard reads
    // as busy, but there is no scan to cancel — keying the label off
    // `scanning` there produced a permanently disabled "Cancel Scan".
    final scanLabel = summary.canCancelScan
        ? l10n.homeCancelScan
        : summary.hasCompletedScan
        ? l10n.homeRescan
        : l10n.homeStartScan;
    final scanCallback = summary.canCancelScan ? onCancelScan : onScan;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackedCard = compact || constraints.maxWidth < 280;

        if (stackedCard) {
          // Compact mode: keep original stacked layout
          final showSkeleton = summary.scanning || summary.overview.loading;
          final details = Padding(
            padding: const EdgeInsets.fromLTRB(
              AppleSpacing.lg,
              18,
              AppleSpacing.lg,
              18,
            ),
            child: showSkeleton && summary.categories.isEmpty
                // Loading/scanning with no categories: show skeleton
                ? _buildCategorySkeleton()
                : showSkeleton
                // Partial results are real data — show them, greyed out to read
                // as in-progress. An opaque skeleton on top would build the
                // breakdown and then hide it.
                ? CategoryBreakdown(
                    categories: summary.categories,
                    enabled: false,
                    onSelectCategory: onSelectCategory,
                  )
                : summary.categories.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      summary.hasCompletedScan
                          ? l10n.homeFolderEmpty
                          : l10n.homeLargestItemsEmpty,
                      style: context.vwFinePrint.copyWith(
                        color: _onDashboard.withValues(alpha: 0.42),
                      ),
                    ),
                  )
                : CategoryBreakdown(
                    categories: summary.categories,
                    enabled: true,
                    onSelectCategory: onSelectCategory,
                  ),
          );
          final actions = KeyedSubtree(
            key: StorageStewardHome.actionsKey,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppleSpacing.lg,
                0,
                AppleSpacing.lg,
                18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusChip(
                    key: StorageStewardHome.statusChipKey,
                    label: _overviewStatus(context, summary),
                    tone: _statusChipTone(summary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    summary.lastScannedAtMs == null
                        ? l10n.homeNeverScanned
                        : l10n.homeLastScan(
                            _formatScanTime(context, summary.lastScannedAtMs!),
                          ),
                    maxLines: 2,
                    style: context.vwFinePrint.copyWith(
                      color: Colors.white.withValues(alpha: 0.58),
                    ),
                  ),
                  if (summary.reclaimableBytes != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      l10n.homeReclaimable(
                        formatStorageBytes(summary.reclaimableBytes),
                      ),
                      style: context.vwFinePrint.copyWith(color: _onDashboard),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 168,
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(_browseFocusOrder),
                        child: _DashboardActionButton(
                          key: StorageStewardHome.browseKey,
                          label: l10n.homeBrowseFiles,
                          icon: Icons.folder_outlined,
                          primary: false,
                          onPressed: interactionsLocked ? null : onBrowse,
                        ),
                      ),
                    ),
                  ),
                  if (onOpenAi != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 140,
                        child: FocusTraversalOrder(
                          order: const NumericFocusOrder(_aiFocusOrder),
                          child: Focus(
                            focusNode: aiActionFocusNode,
                            child: _DashboardActionButton(
                              key: StorageStewardHome.aiActionKey,
                              label: l10n.aiAnalysisFab,
                              icon: Icons.auto_awesome_outlined,
                              primary: false,
                              accentOutline: true,
                              onPressed: interactionsLocked ? null : onOpenAi,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 168,
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(_scanFocusOrder),
                        child: _DashboardActionButton(
                          key: StorageStewardHome.scanActionKey,
                          label: scanLabel,
                          icon: summary.canCancelScan
                              ? Icons.stop_circle_outlined
                              : Icons.radar_outlined,
                          primary: true,
                          semanticColor: summary.canCancelScan
                              ? context.volward.danger
                              : null,
                          onPressed: scanCallback,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );

          return KeyedSubtree(
            key: StorageStewardHome.browseCardKey,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _glass(0.08),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [details, actions],
              ),
            ),
          );
        }

        // Wide mode: new vertical layout
        // Top: Last scan + Status chip
        // Middle: Category breakdown (pie chart)
        // Bottom: Buttons
        return KeyedSubtree(
          key: StorageStewardHome.browseCardKey,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _glass(0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppleSpacing.lg,
                16,
                AppleSpacing.lg,
                16,
              ), // Match LargestItemsPanel horizontal padding
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top row: Last scan on left, Status chip on right
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          summary.lastScannedAtMs == null
                              ? l10n.homeNeverScanned
                              : l10n.homeLastScan(
                                  _formatScanTime(
                                    context,
                                    summary.lastScannedAtMs!,
                                  ),
                                ),
                          maxLines: 2,
                          style: context.vwFinePrint.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _StatusChip(
                        key: StorageStewardHome.statusChipKey,
                        label: _overviewStatus(context, summary),
                        tone: _statusChipTone(summary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10), // Reduced from 12
                  // Middle: Category breakdown, skeleton (loading/scanning), or empty hint
                  if ((summary.scanning || summary.overview.loading) &&
                      summary.categories.isEmpty)
                    // Loading/scanning with no categories yet: show skeleton only
                    Expanded(child: _buildCategorySkeleton())
                  else if (summary.scanning || summary.overview.loading)
                    // Partial results are real data — show them, greyed out to
                    // read as in-progress. An opaque skeleton on top would
                    // build the breakdown and then hide it.
                    Expanded(
                      child: CategoryBreakdown(
                        categories: summary.categories,
                        enabled: false,
                        onSelectCategory: onSelectCategory,
                      ),
                    )
                  else if (summary.categories.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          summary.hasCompletedScan
                              ? l10n.homeFolderEmpty
                              : l10n.homeLargestItemsEmpty,
                          style: context.vwFinePrint.copyWith(
                            color: _onDashboard.withValues(alpha: 0.42),
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: CategoryBreakdown(
                        categories: summary.categories,
                        enabled: true,
                        onSelectCategory: onSelectCategory,
                      ),
                    ),
                  // Fixed-height reclaimable space (always present to prevent button jump)
                  const SizedBox(height: 8),
                  SizedBox(
                    height: _finePrintLineHeight(context),
                    child: summary.reclaimableBytes != null
                        ? Text(
                            l10n.homeReclaimable(
                              formatStorageBytes(summary.reclaimableBytes),
                            ),
                            textAlign: TextAlign.center,
                            style: context.vwFinePrint.copyWith(
                              color: _onDashboard.withValues(alpha: 0.72),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 10), // Reduced from 12
                  // Bottom: Buttons (fixed at bottom)
                  KeyedSubtree(
                    key: StorageStewardHome.actionsKey,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 140,
                          child: FocusTraversalOrder(
                            order: const NumericFocusOrder(_browseFocusOrder),
                            child: _DashboardActionButton(
                              key: StorageStewardHome.browseKey,
                              label: l10n.homeBrowseFiles,
                              icon: Icons.folder_outlined,
                              primary: false,
                              onPressed: interactionsLocked ? null : onBrowse,
                            ),
                          ),
                        ),
                        if (onOpenAi != null) ...[
                          const SizedBox(width: 10),
                          Flexible(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: FocusTraversalOrder(
                                order: const NumericFocusOrder(_aiFocusOrder),
                                child: Focus(
                                  focusNode: aiActionFocusNode,
                                  child: _DashboardActionButton(
                                    key: StorageStewardHome.aiActionKey,
                                    label: l10n.aiAnalysisFab,
                                    icon: Icons.auto_awesome_outlined,
                                    primary: false,
                                    accentOutline: true,
                                    onPressed:
                                        interactionsLocked ? null : onOpenAi,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 140,
                          child: FocusTraversalOrder(
                            order: const NumericFocusOrder(_scanFocusOrder),
                            child: _DashboardActionButton(
                              key: StorageStewardHome.scanActionKey,
                              label: scanLabel,
                              icon: summary.canCancelScan
                                  ? Icons.stop_circle_outlined
                                  : Icons.radar_outlined,
                              primary: true,
                              semanticColor: summary.canCancelScan
                                  ? context.volward.danger
                                  : null,
                              onPressed: scanCallback,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds a skeleton loader mimicking the category breakdown layout
  Widget _buildCategorySkeleton() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final needsCompactLayout = constraints.maxHeight < 96;
        return _CategorySkeletonContent(compact: needsCompactLayout);
      },
    );
  }
}

class _CategorySkeletonContent extends StatelessWidget {
  const _CategorySkeletonContent({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Match real CategoryBreakdown layout: pie chart stays 72x72 (square)
    const pieSize = 72.0;
    final rowGap = compact ? 3.0 : 5.0;
    final markerSize = compact ? 8.0 : 12.0;
    final lineHeight = compact ? 8.0 : 12.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _dashboardSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SkeletonLoader(
              width: pieSize,
              height: pieSize,
              borderRadius: pieSize / 2,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    Row(
                      children: [
                        SkeletonLoader(
                          width: markerSize,
                          height: markerSize,
                          borderRadius: 3,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SkeletonLoader(
                            width: double.infinity,
                            height: lineHeight,
                            borderRadius: 4,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SkeletonLoader(
                          width: 40,
                          height: lineHeight,
                          borderRadius: 4,
                        ),
                      ],
                    ),
                    if (i < 2) SizedBox(height: rowGap),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _StatusChipTone { neutral, live, cached }

class _StatusChip extends StatelessWidget {
  const _StatusChip({super.key, required this.label, required this.tone});

  final String label;
  final _StatusChipTone tone;

  @override
  Widget build(BuildContext context) {
    final parentBackground = _glass(0.08);
    final fill = switch (tone) {
      _StatusChipTone.live => _liveChipFill,
      _StatusChipTone.cached => context.volward.warning.withValues(alpha: 0.16),
      _StatusChipTone.neutral => parentBackground,
    };
    final borderColor = switch (tone) {
      _StatusChipTone.live => _liveChipLine,
      _StatusChipTone.cached => context.volward.warning.withValues(alpha: 0.38),
      _StatusChipTone.neutral => Colors.white.withValues(alpha: 0.10),
    };
    final foreground = switch (tone) {
      _StatusChipTone.live => _liveChipText,
      _StatusChipTone.cached => _highestContrastForeground(
        Color.alphaBlend(fill, parentBackground),
      ),
      _StatusChipTone.neutral => Colors.white.withValues(alpha: 0.84),
    };
    return SizedBox(
      height: _dashboardControlHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: _dashboardControlTextStyle(context, foreground),
            ),
          ),
        ),
      ),
    );
  }
}

class _VolumeSelector extends StatelessWidget {
  const _VolumeSelector({
    required this.locations,
    required this.selectedPath,
    required this.selectedVolumeId,
    required this.enabled,
    required this.onSelected,
  });

  final List<StorageLocationInfo> locations;
  final String selectedPath;
  final String? selectedVolumeId;
  final bool enabled;
  final ValueChanged<StorageLocationInfo> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    StorageLocationInfo? selected;
    for (final location in locations) {
      if (_samePath(location.path, selectedPath) ||
          location.volumeId == selectedVolumeId) {
        selected = location;
        break;
      }
    }
    selected ??= locations.first;
    final selectedLabel = localizedLocationLabel(context, selected);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: enabled ? null : () {},
      child: Semantics(
        key: StorageStewardHome.volumeSelectorKey,
        container: true,
        button: true,
        enabled: enabled,
        label: l10n.homeScanTargets,
        value: selectedLabel,
        child: PopupMenuButton<StorageLocationInfo>(
          enabled: enabled,
          initialValue: selected,
          tooltip: l10n.homeScanTargets,
          onSelected: onSelected,
          itemBuilder: (context) => [
            for (final location in locations)
              PopupMenuItem<StorageLocationInfo>(
                key: ValueKey('storage-volume-option-${location.id}'),
                value: location,
                child: Text(localizedLocationLabel(context, location)),
              ),
          ],
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.storage_outlined,
                    size: 18,
                    color: _onDashboard,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      selectedLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.vwFinePrint.copyWith(color: _onDashboard),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: _onDashboard,
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

class _DashboardActionButton extends StatelessWidget {
  const _DashboardActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.primary,
    required this.onPressed,
    this.semanticColor,
    this.accentOutline = false,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback? onPressed;

  /// Overrides the accent for an action whose meaning is not "proceed" —
  /// Cancel Scan uses [VolwardColors.danger]. Null keeps the primary accent.
  final Color? semanticColor;
  final bool accentOutline;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final actionColor = semanticColor ?? context.volward.primary;
    final background = enabled
        ? primary
            ? actionColor
            : Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.04);
    final foreground = enabled && primary
        ? _highestContrastForeground(background)
        : enabled && accentOutline
            ? actionColor
            : _onDashboard.withValues(alpha: enabled ? 1 : 0.42);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: enabled ? null : () {},
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        onTap: onPressed,
        excludeSemantics: true,
        child: SizedBox(
          height: _dashboardControlHeight,
          child: Material(
            color: background,
            shape: StadiumBorder(
              side: BorderSide(
                color: primary || accentOutline
                    ? actionColor
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: InkWell(
              onTap: onPressed,
              customBorder: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: foreground),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _dashboardControlTextStyle(context, foreground),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _highestContrastForeground(Color background) {
  final luminance = background.computeLuminance();
  final blackContrast = (luminance + 0.05) / 0.05;
  final whiteContrast = 1.05 / (luminance + 0.05);
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}

class _TargetMenuTile extends StatelessWidget {
  const _TargetMenuTile({
    required this.location,
    required this.choices,
    required this.selected,
    required this.enabled,
    required this.onSelectTarget,
    this.recentFallback = false,
  });

  final StorageLocationInfo location;
  final List<StorageLocationInfo> choices;
  final bool selected;
  final bool enabled;
  final ValueChanged<StorageLocationInfo>? onSelectTarget;
  final bool recentFallback;

  @override
  Widget build(BuildContext context) {
    final hasMenu = choices.isNotEmpty;
    final label = recentFallback
        ? context.l10n.homeRecentFolders
        : localizedLocationLabel(context, location);
    final selectedFill = _dashboardAccent(context, 0.24);
    final selectedLine = _dashboardAccent(context, 0.62);
    final tileKey = ValueKey(
      recentFallback
          ? 'storage-overview-recent-folders-tile'
          : 'storage-target-${location.id}',
    );
    final tileContent = _TargetTileContent(
      label: label,
      choices: choices,
      selected: selected,
      enabled: enabled,
      recentFallback: recentFallback,
    );
    final tile = Material(
      color: selected ? selectedFill : Colors.white.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? selectedLine : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Tooltip(
        message: recentFallback
            ? context.l10n.homeRecentFolders
            : location.path,
        child: hasMenu
            ? KeyedSubtree(
                key: tileKey,
                child: ExcludeSemantics(child: tileContent),
              )
            : InkWell(
                key: tileKey,
                onTap: enabled && onSelectTarget != null
                    ? () => onSelectTarget!(location)
                    : null,
                borderRadius: BorderRadius.circular(16),
                child: Semantics(
                  key: ValueKey(
                    recentFallback
                        ? 'storage-recent-folders-semantics'
                        : 'storage-target-semantics-${location.id}',
                  ),
                  selected: selected,
                  button: true,
                  enabled: enabled,
                  label: label,
                  value: recentFallback
                      ? choices.length.toString()
                      : location.path,
                  onTap: enabled && onSelectTarget != null
                      ? () => onSelectTarget!(location)
                      : null,
                  child: ExcludeSemantics(child: tileContent),
                ),
              ),
      ),
    );
    if (!hasMenu) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: enabled ? null : () {},
        child: tile,
      );
    }
    final menuSurface = Color.alphaBlend(
      _dashboardAccent(context, 0.18),
      _dashboardSoft,
    );
    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: enabled ? null : () {},
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        enabled: enabled,
        label: label,
        value: recentFallback ? choices.length.toString() : location.path,
        onTap: enabled ? () {} : null,
        child: PopupMenuButton<StorageLocationInfo>(
          key: recentFallback
              ? StorageStewardHome.recentFoldersKey
              : ValueKey('storage-target-menu-${location.id}'),
          enabled: enabled,
          tooltip: label,
          color: menuSurface,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: menuShape,
          onSelected: onSelectTarget,
          itemBuilder: (context) => [
            for (final location in choices)
              PopupMenuItem<StorageLocationInfo>(
                key: ValueKey('storage-recent-folder-option-${location.id}'),
                value: location,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 220),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        localizedLocationLabel(context, location),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.vwCaptionStrong.copyWith(
                          color: _onDashboard,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        location.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.vwFinePrint.copyWith(
                          color: _onDashboard.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          child: tile,
        ),
      ),
    );
  }
}

class _TargetTileContent extends StatelessWidget {
  const _TargetTileContent({
    required this.label,
    required this.choices,
    required this.selected,
    required this.enabled,
    required this.recentFallback,
  });

  final String label;
  final List<StorageLocationInfo> choices;
  final bool selected;
  final bool enabled;
  final bool recentFallback;

  @override
  Widget build(BuildContext context) {
    final hasMenu = choices.isNotEmpty;
    return SizedBox(
      width: double.infinity,
      height: _targetTileHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            if (recentFallback) ...[
              Icon(
                Icons.history_outlined,
                size: 16,
                color: _onDashboard.withValues(alpha: enabled ? 0.8 : 0.42),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.vwCaption.copyWith(
                  color: _onDashboard.withValues(
                    alpha: enabled ? (selected ? 1 : 0.8) : 0.42,
                  ),
                ),
              ),
            ),
            if (hasMenu) ...[
              const SizedBox(width: 8),
              if (recentFallback)
                Text(
                  choices.length.toString(),
                  style: context.vwFinePrint.copyWith(
                    color: _onDashboard.withValues(
                      alpha: enabled ? 0.58 : 0.32,
                    ),
                  ),
                ),
              Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: _onDashboard.withValues(alpha: enabled ? 0.8 : 0.42),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String localizedLocationLabel(
  BuildContext context,
  StorageLocationInfo location,
) {
  final l10n = context.l10n;
  final name = location.name.trim().isEmpty
      ? rootDisplayNameFor(location.path)
      : location.name;
  return switch (location.kind) {
    StorageLocationKind.home => l10n.homeLocationHome,
    StorageLocationKind.applications => l10n.homeLocationApplications,
    StorageLocationKind.desktop => l10n.homeLocationDesktop,
    StorageLocationKind.downloads => l10n.homeLocationDownloads,
    StorageLocationKind.documents => l10n.homeLocationDocuments,
    StorageLocationKind.volume => l10n.homeLocationVolume(name),
    StorageLocationKind.custom => l10n.homeLocationCustom(name),
  };
}

String _overviewStatus(BuildContext context, StorageHomeSummary summary) {
  final l10n = context.l10n;
  if (!summary.hasUsableCapacity) {
    return summary.overview.loading && summary.selectedVolume == null
        ? l10n.homeOverviewLoading
        : l10n.homeOverviewUnavailable;
  }
  return switch (summary.selectedVolume?.freshness) {
    StorageDataFreshness.live => l10n.homeOverviewLive,
    StorageDataFreshness.cached => l10n.homeOverviewCached,
    StorageDataFreshness.unavailable || null => l10n.homeOverviewUnavailable,
  };
}

_StatusChipTone _statusChipTone(StorageHomeSummary summary) {
  if (!summary.hasUsableCapacity) return _StatusChipTone.neutral;
  return switch (summary.selectedVolume?.freshness) {
    StorageDataFreshness.live => _StatusChipTone.live,
    StorageDataFreshness.cached => _StatusChipTone.cached,
    StorageDataFreshness.unavailable || null => _StatusChipTone.neutral,
  };
}

bool _samePath(String left, String right) {
  final leftIsWindows = _isWindowsPath(left);
  final rightIsWindows = _isWindowsPath(right);
  if (leftIsWindows != rightIsWindows) return false;

  String normalize(String value, {required bool windows}) {
    var normalized = windows ? value.replaceAll('\\', '/') : value;
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return windows ? normalized.toLowerCase() : normalized;
  }

  return normalize(left, windows: leftIsWindows) ==
      normalize(right, windows: rightIsWindows);
}

bool _isWindowsPath(String value) {
  if (value.startsWith(r'\\') || value.startsWith('//')) return true;
  if (value.length < 2 || value[1] != ':') return false;
  final drive = value.codeUnitAt(0);
  return (drive >= 65 && drive <= 90) || (drive >= 97 && drive <= 122);
}

List<StorageLocationInfo> _volumeChoices(StorageHomeSummary summary) {
  final fromLocations = summary.overview.locations
      .where((location) => location.kind == StorageLocationKind.volume)
      .toList(growable: false);
  if (fromLocations.length >= 2) {
    return fromLocations;
  }
  if (summary.overview.volumes.length < 2) {
    return fromLocations;
  }
  return [
    for (final volume in summary.overview.volumes)
      StorageLocationInfo(
        id: 'drive-${volume.id.replaceAll(':', '').toLowerCase()}',
        name: volume.name,
        path: volume.rootPath,
        kind: StorageLocationKind.volume,
        volumeId: volume.id,
      ),
  ];
}

List<StorageLocationInfo> _targetLocations(StorageHomeSummary summary) {
  final locations = summary.overview.locations
      .where((location) => location.kind != StorageLocationKind.volume)
      .toList();
  final selectedLocation = summary.selectedLocation;
  if (selectedLocation != null &&
      selectedLocation.path.isNotEmpty &&
      selectedLocation.kind != StorageLocationKind.volume &&
      !locations.any(
        (location) => _samePath(location.path, selectedLocation.path),
      )) {
    locations.add(selectedLocation);
  }
  return locations;
}

double _wideDashboardHeight(StorageHomeSummary summary, BuildContext context) {
  // Sidebar height
  final targetLocations = _targetLocations(summary);
  final recentLocations = _recentCustomLocations(summary);
  final selectedCustom =
      summary.selectedLocation?.kind == StorageLocationKind.custom
      ? summary.selectedLocation
      : null;
  final recentMenuLocation =
      selectedCustom ??
      (recentLocations.isNotEmpty ? recentLocations.first : null);
  final hasRecentFallback =
      recentMenuLocation != null &&
      !targetLocations.any(
        (location) => _samePath(location.path, recentMenuLocation.path),
      );
  final visibleTargets = targetLocations.length + (hasRecentFallback ? 1 : 0);

  final sidebarHeight =
      _sidebarPadding * 2 +
      _sidebarLogoHeight +
      _sidebarLogoGap +
      visibleTargets * _targetTileHeight +
      math.max(0, visibleTargets - 1) * _targetTileGap;

  // Right column height
  final rightColumnHeight = _rightColumnHeight(summary, context);

  return math.max(sidebarHeight, rightColumnHeight);
}

List<StorageLocationInfo> _recentCustomLocations(StorageHomeSummary summary) {
  final locations = _targetLocations(summary);
  final pinnedCustomLocation = summary.pinnedCustomLocation;
  final customLocations = [
    ...summary.recentCustomLocations,
    if (pinnedCustomLocation != null) pinnedCustomLocation,
  ];
  final recent = <StorageLocationInfo>[];
  for (final customLocation in customLocations) {
    if (customLocation.path.isNotEmpty &&
        customLocation.kind == StorageLocationKind.custom &&
        !locations.any(
          (location) => _samePath(location.path, customLocation.path),
        ) &&
        !recent.any(
          (location) => _samePath(location.path, customLocation.path),
        )) {
      recent.add(customLocation);
    }
  }
  return recent;
}

// Right panel component heights, summed by [_rightColumnHeight] to size the
// wide dashboard. Each constant mirrors a real widget or gap — when you change
// one of those, change its twin here or the board grows a scrollbar.
//
// Capacity panel — _StatPanel with !compact. Its structure is
// Padding(top 20, bottom 16) wrapping
// [path, gap 8, used, gap 6, label, gap 16, metrics], then gap 10, then meter.
const _capacityPanelPaddingTop = 20.0;
const _capacityPanelPaddingBottom = 16.0;
const _capacityPathBottomGap = 8.0;
const _capacityUsedHeight = 52.0; // fontSize 52 at height 0.92 measures ~48
const _capacityUsedBottomGap = 6.0;
const _capacityUsedLabelBottomGap = 16.0;
const _capacityMetricsHeight = 52.0; // Row with Total/Available (2 columns)
const _capacityMetricsBottomGap = 10.0;
const _capacityMeterHeight = 12.0;

// Largest items panel — LargestItemsPanel, capped at [_largestItemCount] rows
// in wide mode.
const _largestPanelPadding = 18.0 * 2;
const _largestHeaderBottomGap = 10.0;
const _largestItemHeight = 29.0;
const _largestItemCount = 3;
const _largestEmptyBodyHeight = 89.0; // Empty state text height with padding

// Browse card — _BrowseCard's vertical wide-mode layout:
// padding(16) + last-scan row with status chip + gap(10) + CategoryBreakdown
// + gap(8) + reclaimable + gap(10) + buttons + padding(16).
const _browsePanelPadding = 16.0 * 2;
const _browseTopRowHeight = 28.0; // Last scan text (max 2 lines) + status chip
const _browseTopRowBottomGap = 10.0;
// The pie declares Size.square(72) and the legend rides beside it, so this is
// the pie's own height — budgeting less squashes the chart.
const _browseCategoryBreakdownHeight = 72.0;
const _browseReclaimableHeightBase =
    17.0; // Single line reclaimable text (finePrint)
const _browseReclaimableBottomGap = 10.0;
const _browseButtonHeight = _dashboardControlHeight;

/// Returns text-scale-adjusted heights for single-line finePrint (12px * ~1.42)
/// labels. All layout prediction constants ending in `…Base` are at scale=1.0;
/// multiply by this factor when computing [_rightColumnHeight].
double _finePrintLineHeight(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(12.0) / 12.0;
  return _browseReclaimableHeightBase * scale;
}

double _rightColumnHeight(StorageHomeSummary summary, BuildContext context) {
  final textLineH = _finePrintLineHeight(context);
  // Capacity panel intrinsic height
  final capacityHeight =
      _capacityPanelPaddingTop +
      textLineH + // path (finePrint)
      _capacityPathBottomGap +
      _capacityUsedHeight +
      _capacityUsedBottomGap +
      textLineH + // "used" label (finePrint)
      _capacityUsedLabelBottomGap +
      _capacityMetricsHeight +
      _capacityPanelPaddingBottom +
      _capacityMetricsBottomGap +
      _capacityMeterHeight;

  // Largest items panel intrinsic height
  final largestItemCount = summary.largestItems.take(_largestItemCount).length;
  final largestBodyHeight = largestItemCount > 0
      ? largestItemCount * _largestItemHeight
      : _largestEmptyBodyHeight;
  final largestHeight =
      _largestPanelPadding +
      textLineH + // header (finePrint)
      _largestHeaderBottomGap +
      largestBodyHeight;

  // Browse card intrinsic height (new vertical layout in wide mode)
  final browseHeight =
      _browsePanelPadding +
      _browseTopRowHeight +
      _browseTopRowBottomGap +
      _browseCategoryBreakdownHeight +
      textLineH + // reclaimable (finePrint)
      _browseReclaimableBottomGap +
      _browseButtonHeight;

  // Two gaps between three panels
  const panelGaps = _panelGap * 2;

  return capacityHeight + largestHeight + browseHeight + panelGaps;
}

String _formatScanTime(BuildContext context, int millisecondsSinceEpoch) {
  final value = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMMMd(locale).add_jm().format(value);
}
