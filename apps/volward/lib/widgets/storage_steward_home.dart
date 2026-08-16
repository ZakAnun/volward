import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../storage_home_summary.dart';
import '../storage_overview.dart';
import '../theme/volward_tokens.dart';
import 'volward_logo.dart';

const _dashboardInk = Color(0xFF111113);
const _dashboardSoft = Color(0xFF1A1A1E);
const _meterStart = Color(0xFF8FD2FF);
const _meterEnd = Color(0xFF2997FF);
const _onDashboard = Color(0xFFF4F4F5);
const _liveChipFill = Color(0x2934C759);
const _liveChipLine = Color(0x3834C759);
const _liveChipText = Color(0xFFD5FFD9);
const _volumeFocusOrder = 0.0;
const _targetFocusOrderStart = 100.0;
const _chooseFolderFocusOrder = 10000.0;
const _browseFocusOrder = 10001.0;
const _scanFocusOrder = 10002.0;
const _settingsFocusOrder = 10003.0;

Color _glass(double whiteAlpha) {
  return Color.alphaBlend(
    Colors.white.withValues(alpha: whiteAlpha),
    _dashboardInk,
  );
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
  static const actionsKey = Key('storage-overview-actions');
  static const settingsKey = Key('storage-overview-settings');

  final StorageHomeSummary summary;
  final VoidCallback onBrowse;
  final VoidCallback onChooseFolder;
  final ValueChanged<StorageLocationInfo> onSelectTarget;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;
  final VoidCallback? onOpenSettings;

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
  });

  final StorageHomeSummary summary;
  final bool compact;
  final VoidCallback onBrowse;
  final VoidCallback? onChooseFolder;
  final ValueChanged<StorageLocationInfo> onSelectTarget;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;
  final VoidCallback? onOpenSettings;

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
            )
          : _WideBoard(
              summary: summary,
              onSelectTarget: onSelectTarget,
              onBrowse: onBrowse,
              onScan: onScan,
              onCancelScan: onCancelScan,
            ),
    );

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Semantics(
        key: StorageStewardHome.panelKey,
        container: true,
        explicitChildNodes: true,
        child: GestureDetector(
          key: StorageStewardHome.panelBackgroundKey,
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: onBrowse,
          child: DecoratedBox(
            key: StorageStewardHome.dashboardSurfaceKey,
            decoration: const BoxDecoration(
              color: _dashboardInk,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_dashboardInk, _dashboardSoft, Color(0x570066CC)],
                stops: [0, 0.55, 1],
              ),
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
  });

  final StorageHomeSummary summary;
  final ValueChanged<StorageLocationInfo> onSelectTarget;
  final VoidCallback onBrowse;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 216,
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
            onBrowse: onBrowse,
            onScan: onScan,
            onCancelScan: onCancelScan,
          ),
        ),
      ],
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
  });

  final StorageHomeSummary summary;
  final ValueChanged<StorageLocationInfo> onSelectTarget;
  final VoidCallback onBrowse;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;

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
          onBrowse: onBrowse,
          onScan: onScan,
          onCancelScan: onCancelScan,
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
    Widget targetTile(int index) {
      final location = targetLocations[index];
      return FocusTraversalOrder(
        order: NumericFocusOrder(_targetFocusOrderStart + index),
        child: _TargetTile(
          location: location,
          selected: _samePath(
            location.path,
            summary.selectedLocation?.path ?? '',
          ),
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
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: _glass(0.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const SizedBox(
                height: 104,
                child: Center(child: VolwardLogoMark(size: 72)),
              ),
            ),
            const SizedBox(height: 18),
            for (var index = 0; index < targetLocations.length; index++) ...[
              targetTile(index),
              if (index < targetLocations.length - 1)
                const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _MainPane extends StatelessWidget {
  const _MainPane({
    required this.summary,
    required this.compact,
    required this.onBrowse,
    required this.onScan,
    required this.onCancelScan,
  });

  final StorageHomeSummary summary;
  final bool compact;
  final VoidCallback onBrowse;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: StorageStewardHome.capacityKey,
          child: _StatPanel(summary: summary, compact: compact),
        ),
        const SizedBox(height: 14),
        _HeroMeter(summary: summary),
        const SizedBox(height: 14),
        _BrowseCard(
          summary: summary,
          compact: compact,
          onBrowse: onBrowse,
          onScan: onScan,
          onCancelScan: onCancelScan,
        ),
        if (!compact && summary.categories.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final category in summary.categories) ...[
            const SizedBox(height: 10),
            _CategoryRow(category: category),
          ],
        ],
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
          child: Padding(
            padding: EdgeInsets.all(compact ? 18 : 22),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        key: StorageStewardHome.capacityMeterKey,
        height: 12,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: _glass(0.08)),
            if (progress != null)
              FractionallySizedBox(
                widthFactor: progress.clamp(0, 1),
                alignment: Alignment.centerLeft,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [_meterStart, _meterEnd]),
                  ),
                ),
              ),
          ],
        ),
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
  });

  final StorageHomeSummary summary;
  final bool compact;
  final VoidCallback onBrowse;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;

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
        final details = Padding(
          padding: EdgeInsets.fromLTRB(20, 18, stackedCard ? 20 : 12, 18),
          child: _ScanSummary(summary: summary),
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
                          semanticColor: summary.scanning
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: context.vwFinePrint.copyWith(color: foreground),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category});

  final StorageHomeCategorySummary category;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _glass(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _localizedCategory(context, category.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.vwCaption.copyWith(
                  color: Colors.white.withValues(alpha: 0.86),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              NumberFormat.decimalPattern(locale).format(category.count),
              style: context.vwCaptionStrong.copyWith(color: _onDashboard),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanSummary extends StatelessWidget {
  const _ScanSummary({required this.summary});

  final StorageHomeSummary summary;

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
            child: LinearProgressIndicator(
              key: const ValueKey('storage-scan-progress'),
              value: summary.scanProgress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.10),
              color: context.volward.primary,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: foreground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.vwCaptionStrong.copyWith(
                        color: foreground,
                      ),
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

Color _highestContrastForeground(Color background) {
  final luminance = background.computeLuminance();
  final blackContrast = (luminance + 0.05) / 0.05;
  final whiteContrast = 1.05 / (luminance + 0.05);
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}

class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.location,
    required this.selected,
    required this.enabled,
    required this.onSelectTarget,
  });

  final StorageLocationInfo location;
  final bool selected;
  final bool enabled;
  final ValueChanged<StorageLocationInfo> onSelectTarget;

  @override
  Widget build(BuildContext context) {
    final label = localizedLocationLabel(context, location);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: enabled ? null : () {},
      child: Material(
        color: selected
            ? const Color(0x2E0066CC)
            : Colors.white.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected
                ? const Color(0x668FD2FF)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Tooltip(
          message: location.path,
          child: InkWell(
            key: ValueKey('storage-target-${location.id}'),
            onTap: enabled ? () => onSelectTarget(location) : null,
            borderRadius: BorderRadius.circular(16),
            child: Semantics(
              key: ValueKey('storage-target-semantics-${location.id}'),
              selected: selected,
              button: true,
              enabled: enabled,
              label: label,
              value: location.path,
              onTap: enabled ? () => onSelectTarget(location) : null,
              child: ExcludeSemantics(
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
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
                ),
              ),
            ),
          ),
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
    _ => name,
  };
}

String _localizedScanPhase(BuildContext context, String? phase) {
  final l10n = context.l10n;
  return switch (phase) {
    'DiscoveringRoots' => l10n.scanPhaseDiscoveringRoots,
    'Walking' => l10n.scanPhaseWalking,
    'Classifying' => l10n.scanPhaseClassifying,
    'Aggregating' => l10n.scanPhaseAggregating,
    'SavingResults' => l10n.scanPhaseSavingResults,
    'LoadingResults' => l10n.scanPhaseLoadingResults,
    'Done' => l10n.scanPhaseDone,
    _ => phase == null || phase.isEmpty ? l10n.scanStatusScanning : phase,
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

String _formatScanTime(BuildContext context, int millisecondsSinceEpoch) {
  final value = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMMMd(locale).add_jm().format(value);
}
