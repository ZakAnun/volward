import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../storage_home_summary.dart';
import '../storage_overview.dart';
import '../theme/volward_tokens.dart';
import 'home/dashboard_theme.dart';
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
const _scanFocusOrder = 10002.0;
const _settingsFocusOrder = 10003.0;
const _dashboardControlHeight = 36.0;
const _wideSidebarWidth = 216.0;
const _wideDashboardMinHeight = 430.0;
const _panelGap = 14.0;
const _sidebarPadding = 18.0;
const _sidebarLogoHeight = 104.0;
const _sidebarLogoGap = 18.0;
const _targetTileHeight = 44.0;
const _targetTileGap = 10.0;

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
  static const scanSummaryKey = Key('storage-overview-scan-summary');
  static const lastScanOpenKey = Key('storage-overview-last-scan-open');
  static const categoryPieKey = Key('storage-overview-category-pie');
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return _HeroVisual(
          summary: summary,
          compact: compact,
          onBrowse: onBrowse,
          onChooseFolder: summary.scanning ? null : onChooseFolder,
          onSelectTarget: onSelectTarget,
          onScan: onScan,
          onCancelScan: onCancelScan,
          onOpenSettings: onOpenSettings,
          onSelectCategory: onSelectCategory,
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
  });

  final StorageHomeSummary summary;
  final bool compact;
  final VoidCallback onBrowse;
  final VoidCallback? onChooseFolder;
  final ValueChanged<StorageLocationInfo> onSelectTarget;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;
  final VoidCallback? onOpenSettings;
  final ValueChanged<String>? onSelectCategory;

  @override
  Widget build(BuildContext context) {
    final board = Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 22,
        0,
        compact ? 16 : 22,
        compact ? 16 : 22,
      ),
      child: compact
          ? _CompactBoard(
              summary: summary,
              onSelectTarget: onSelectTarget,
              onBrowse: onBrowse,
              onScan: onScan,
              onCancelScan: onCancelScan,
              onSelectCategory: onSelectCategory,
            )
          : _WideBoard(
              summary: summary,
              onSelectTarget: onSelectTarget,
              onBrowse: onBrowse,
              onScan: onScan,
              onCancelScan: onCancelScan,
              onSelectCategory: onSelectCategory,
            ),
    );

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
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          key: StorageStewardHome.boardKey,
                          constraints: BoxConstraints(
                            minHeight: viewport.maxHeight,
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
  final ValueChanged<StorageLocationInfo> onSelectTarget;
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
              enabled: !summary.scanning,
              onSelected: onSelectTarget,
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
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 14),
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
  });

  final StorageHomeSummary summary;
  final ValueChanged<StorageLocationInfo> onSelectTarget;
  final VoidCallback onBrowse;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;
  final ValueChanged<String>? onSelectCategory;

  @override
  Widget build(BuildContext context) {
    final dashboardHeight = _wideDashboardHeight(summary);
    return SizedBox(
      height: dashboardHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
            child: _MainPane(
              summary: summary,
              compact: false,
              balancePanels: true,
              onBrowse: onBrowse,
              onScan: onScan,
              onCancelScan: onCancelScan,
              onSelectCategory: onSelectCategory,
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
    required this.onSelectTarget,
    required this.onBrowse,
    required this.onScan,
    required this.onCancelScan,
    required this.onSelectCategory,
  });

  final StorageHomeSummary summary;
  final ValueChanged<StorageLocationInfo> onSelectTarget;
  final VoidCallback onBrowse;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;
  final ValueChanged<String>? onSelectCategory;

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
        _MainPane(
          summary: summary,
          compact: true,
          balancePanels: false,
          onBrowse: onBrowse,
          onScan: onScan,
          onCancelScan: onCancelScan,
          onSelectCategory: onSelectCategory,
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.summary, required this.onSelectTarget});

  final StorageHomeSummary summary;
  final ValueChanged<StorageLocationInfo> onSelectTarget;

  @override
  Widget build(BuildContext context) {
    final targetLocations = _targetLocations(summary);
    final recentLocations = _recentCustomLocations(summary);
    final selectedPath = summary.selectedLocation?.path ?? '';
    final selectedCustom =
        summary.selectedLocation?.kind == StorageLocationKind.custom
            ? summary.selectedLocation
            : null;
    final recentMenuLocation = selectedCustom ??
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
      final choices = location.kind == StorageLocationKind.custom &&
              recentMenuChoices.length > 1
          ? recentMenuChoices
          : const <StorageLocationInfo>[];
      return FocusTraversalOrder(
        order: NumericFocusOrder(_targetFocusOrderStart + index),
        child: _TargetMenuTile(
          location: location,
          choices: choices,
          selected: selected,
          enabled: !summary.scanning,
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
          final recentFallback = recentMenuLocation != null &&
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
                    enabled: !summary.scanning,
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
                for (var index = 0;
                    index < targetLocations.length;
                    index++) ...[
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
  });

  final StorageHomeSummary summary;
  final bool compact;
  final bool balancePanels;
  final VoidCallback onBrowse;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;
  final ValueChanged<String>? onSelectCategory;

  @override
  Widget build(BuildContext context) {
    final capacity = KeyedSubtree(
      key: StorageStewardHome.capacityKey,
      child: _StatPanel(summary: summary, compact: compact),
    );
    final browse = _BrowseCard(
      summary: summary,
      compact: compact,
      onBrowse: onBrowse,
      onScan: onScan,
      onCancelScan: onCancelScan,
      onSelectCategory: onSelectCategory,
    );
    if (balancePanels) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: capacity),
          const SizedBox(height: _panelGap),
          Expanded(child: browse),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        capacity,
        const SizedBox(height: _panelGap),
        browse,
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
                    compact ? 18 : 22,
                    compact ? 18 : 22,
                    compact ? 18 : 22,
                    compact ? 16 : 18,
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
                      const SizedBox(height: 10),
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
                      const SizedBox(height: 18),
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
                if (!compact) const Spacer(),
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
    final progress =
        summary.hasUsableCapacity ? summary.selectedVolume?.usedFraction : null;
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
                decoration: BoxDecoration(
                  gradient: _meterGradient(context),
                ),
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
  });

  final StorageHomeSummary summary;
  final bool compact;
  final VoidCallback onBrowse;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;
  final ValueChanged<String>? onSelectCategory;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scanLabel = summary.scanning
        ? l10n.homeCancelScan
        : summary.hasCompletedScan
            ? l10n.homeRescan
            : l10n.homeStartScan;
    final scanCallback = summary.scanning ? onCancelScan : onScan;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackedCard = compact || constraints.maxWidth < 280;
        final details = GestureDetector(
          key: StorageStewardHome.lastScanOpenKey,
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: onBrowse,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 18, stackedCard ? 20 : 12, 18),
            child: _ScanSummary(
              summary: summary,
              onSelectCategory: onSelectCategory,
            ),
          ),
        );
        final actions = KeyedSubtree(
          key: StorageStewardHome.actionsKey,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              stackedCard ? 20 : 0,
              stackedCard ? 0 : 18,
              20,
              18,
            ),
            child: SizedBox(
              width: stackedCard ? null : 168,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusChip(
                    label: _overviewStatus(context, summary),
                    tone: _statusChipTone(summary),
                  ),
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
                          onPressed: onBrowse,
                        ),
                      ),
                    ),
                  ),
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
                          icon: summary.scanning
                              ? Icons.stop_circle_outlined
                              : Icons.radar_outlined,
                          primary: true,
                          semanticColor:
                              summary.scanning ? context.volward.danger : null,
                          onPressed: scanCallback,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        return KeyedSubtree(
          key: StorageStewardHome.scanSummaryKey,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _glass(0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: stackedCard
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [details, actions],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: details),
                      actions,
                    ],
                  ),
          ),
        );
      },
    );
  }
}

enum _StatusChipTone { neutral, live, cached }

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.tone});

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

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({
    required this.categories,
    required this.enabled,
    required this.onSelectCategory,
  });

  final List<StorageHomeCategorySummary> categories;
  final bool enabled;
  final ValueChanged<String>? onSelectCategory;

  @override
  Widget build(BuildContext context) {
    final total = categories.fold<int>(0, (sum, item) => sum + item.count);
    final slices = <_PieSlice>[
      for (final category in categories)
        _PieSlice(
          color: _categoryColor(category.name),
          fraction: total == 0 ? 0 : category.count / total,
        ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CustomPaint(
          key: StorageStewardHome.categoryPieKey,
          size: const Size.square(72),
          painter: _CategoryPiePainter(slices: slices),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < categories.length; i++)
                _CategoryLegendRow(
                  category: categories[i],
                  color: _categoryColor(categories[i].name),
                  percentLabel: _percentLabel(categories[i].count, total),
                  enabled: enabled,
                  onSelect: !enabled ||
                          onSelectCategory == null ||
                          categories[i].name == homeOtherCategoryName
                      ? null
                      : () => onSelectCategory!(categories[i].name),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PieSlice {
  const _PieSlice({required this.color, required this.fraction});

  final Color color;
  final double fraction;
}

class _CategoryPiePainter extends CustomPainter {
  const _CategoryPiePainter({required this.slices});

  final List<_PieSlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final outer = Rect.fromCircle(center: center, radius: radius);
    final inner = Rect.fromCircle(center: center, radius: radius * 0.56);
    var start = -math.pi / 2;
    final gap = slices.length > 1 ? 0.07 : 0.0;
    for (final slice in slices) {
      final sweep = slice.fraction * 2 * math.pi;
      final padded = math.max(0.0, sweep - gap);
      if (padded > 0) {
        final from = start + gap / 2;
        final path = Path()
          ..arcTo(outer, from, padded, true)
          ..arcTo(inner, from + padded, -padded, false)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..color = slice.color
            ..isAntiAlias = true
            ..style = PaintingStyle.fill,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _CategoryPiePainter oldDelegate) {
    if (oldDelegate.slices.length != slices.length) return true;
    for (var i = 0; i < slices.length; i++) {
      final next = slices[i];
      final previous = oldDelegate.slices[i];
      if (next.color != previous.color || next.fraction != previous.fraction) {
        return true;
      }
    }
    return false;
  }
}

class _CategoryLegendRow extends StatelessWidget {
  const _CategoryLegendRow({
    required this.category,
    required this.color,
    required this.percentLabel,
    required this.enabled,
    required this.onSelect,
  });

  final StorageHomeCategorySummary category;
  final Color color;
  final String percentLabel;
  final bool enabled;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final label = _localizedCategory(context, category.name);
    final count = NumberFormat.decimalPattern(locale).format(category.count);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: enabled ? null : () {},
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('storage-category-${category.name}'),
          onTap: enabled ? onSelect : null,
          borderRadius: BorderRadius.circular(8),
          child: Semantics(
            button: true,
            enabled: enabled,
            label: label,
            value: '$count · $percentLabel',
            onTap: enabled ? onSelect : null,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: enabled ? 1 : 0.42),
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox(width: 8, height: 8),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.vwFinePrint.copyWith(
                          color: _onDashboard.withValues(
                            alpha: enabled ? 0.84 : 0.42,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      count,
                      style: context.vwFinePrint.copyWith(
                        color: _onDashboard.withValues(
                          alpha: enabled ? 0.64 : 0.36,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      percentLabel,
                      style: context.vwFinePrint.copyWith(
                        color: _onDashboard.withValues(
                          alpha: enabled ? 0.64 : 0.36,
                        ),
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

class _ScanSummary extends StatelessWidget {
  const _ScanSummary({required this.summary, required this.onSelectCategory});

  final StorageHomeSummary summary;
  final ValueChanged<String>? onSelectCategory;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          const SizedBox(height: 4),
          Text(
            l10n.homeReclaimable(formatStorageBytes(summary.reclaimableBytes)),
            style: context.vwFinePrint.copyWith(color: _onDashboard),
          ),
        ],
        if (summary.scannedBytes != null) ...[
          const SizedBox(height: 4),
          Text(
            l10n.homeScannedSize(formatStorageBytes(summary.scannedBytes)),
            style: context.vwFinePrint.copyWith(
              color: Colors.white.withValues(alpha: 0.74),
            ),
          ),
        ],
        if (summary.categories.isNotEmpty) ...[
          const SizedBox(height: 12),
          _CategoryBreakdown(
            categories: summary.categories,
            enabled: !summary.scanning,
            onSelectCategory: onSelectCategory,
          ),
        ],
        if (summary.scanning) ...[
          const SizedBox(height: 12),
          ExcludeSemantics(
            child: Text(
              _localizedScanPhase(context, summary.scanPhase),
              key: const ValueKey('storage-scan-phase'),
              style: context.vwFinePrint.copyWith(
                color: Colors.white.withValues(alpha: 0.68),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            label: _localizedScanPhase(context, summary.scanPhase),
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
      ],
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
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback? onPressed;
  final Color? semanticColor;

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
                color: primary
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
  final ValueChanged<StorageLocationInfo> onSelectTarget;
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
        message:
            recentFallback ? context.l10n.homeRecentFolders : location.path,
        child: hasMenu
            ? KeyedSubtree(
                key: tileKey,
                child: ExcludeSemantics(child: tileContent),
              )
            : InkWell(
                key: tileKey,
                onTap: enabled ? () => onSelectTarget(location) : null,
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
                  onTap: enabled ? () => onSelectTarget(location) : null,
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
                color: _onDashboard.withValues(
                  alpha: enabled ? 0.8 : 0.42,
                ),
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
                color: _onDashboard.withValues(
                  alpha: enabled ? 0.8 : 0.42,
                ),
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

String _localizedCategory(BuildContext context, String name) {
  final l10n = context.l10n;
  return switch (name) {
    'Cache' => l10n.filterCategoryCache,
    'Temp' => l10n.filterCategoryTemp,
    'Media' => l10n.filterCategoryMedia,
    'System' => l10n.filterCategorySystem,
    'Other' => l10n.homeCategoryOther,
    _ => name,
  };
}

Color _categoryColor(String name) {
  return switch (name) {
    'Cache' => const Color(0xFF64D2FF),
    'Temp' => const Color(0xFFFFD60A),
    'Media' => const Color(0xFFBF5AF2),
    'System' => const Color(0xFF30D158),
    'Other' => const Color(0xFF8E8E93),
    _ => const Color(0xFF8E8E93),
  };
}

String _percentLabel(int count, int total) {
  if (total <= 0 || count <= 0) return '0%';
  final exact = count * 100 / total;
  if (exact < 0.1) return '<0.1%';
  if (exact < 1) return '${exact.toStringAsFixed(1)}%';
  return '${exact.round()}%';
}

String _localizedScanPhase(BuildContext context, String? phase) =>
    localizedScanPhase(context, phase);

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

double _wideDashboardHeight(StorageHomeSummary summary) {
  final visibleTargets = _visibleTargetCount(summary);
  final targetHeight = _sidebarPadding * 2 +
      _sidebarLogoHeight +
      _sidebarLogoGap +
      visibleTargets * _targetTileHeight +
      math.max(0, visibleTargets - 1) * _targetTileGap;
  return math.max(_wideDashboardMinHeight, targetHeight);
}

int _visibleTargetCount(StorageHomeSummary summary) {
  final targetLocations = _targetLocations(summary);
  final recentLocations = _recentCustomLocations(summary);
  final selectedCustom =
      summary.selectedLocation?.kind == StorageLocationKind.custom
          ? summary.selectedLocation
          : null;
  final recentMenuLocation = selectedCustom ??
      (recentLocations.isNotEmpty ? recentLocations.first : null);
  final hasRecentFallback = recentMenuLocation != null &&
      !targetLocations.any(
        (location) => _samePath(location.path, recentMenuLocation.path),
      );
  return targetLocations.length + (hasRecentFallback ? 1 : 0);
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

String _formatScanTime(BuildContext context, int millisecondsSinceEpoch) {
  final value = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMMMd(locale).add_jm().format(value);
}
