import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:volward/l10n/l10n.dart';
import 'package:volward/theme/apple_tokens.dart';
import 'package:volward/theme/volward_tokens.dart';
import 'package:volward/widgets/apple_widgets.dart';
import 'directory_compact_chrome.dart';
import 'directory_section_layout.dart';

/// Empty/scan-pending section: target row, scan progress, status text and the
/// permission banner. Data in, callbacks out.
class DirectoryScanSection extends StatelessWidget {
  const DirectoryScanSection({
    super.key,
    required this.permissionBanner,
    required this.targetLabel,
    required this.scanRootsEmpty,
    required this.scanning,
    required this.scannedFraction,
    required this.elapsedLabel,
    required this.progressSummary,
    required this.scanStatus,
    required this.onPickFolder,
    required this.showHomeAction,
    required this.onBrowseHome,
    required this.onCancelScan,
  });

  final Widget? permissionBanner;
  final String targetLabel;
  final bool scanRootsEmpty;
  final bool scanning;
  final ValueListenable<double?> scannedFraction;
  final ValueListenable<String?> elapsedLabel;
  final String Function() progressSummary;
  final String? scanStatus;
  final VoidCallback onPickFolder;
  final bool showHomeAction;
  final VoidCallback onBrowseHome;
  final VoidCallback onCancelScan;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    final l10n = context.l10n;
    return padDirectorySection(
      AppleUtilityCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (permissionBanner != null) ...[
              permissionBanner!,
              const SizedBox(height: AppleSpacing.sm),
              Divider(height: 1, color: v.hairline),
              const SizedBox(height: AppleSpacing.sm),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.scanTargetTitle,
                        style: context.vwCaptionStrong,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        targetLabel,
                        style: context.vwCaption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppleSpacing.sm),
                Wrap(
                  spacing: AppleSpacing.xs,
                  runSpacing: AppleSpacing.xs,
                  alignment: WrapAlignment.end,
                  children: [
                    AppleButton(
                      key: directoryBrowseFolderActionKey,
                      label: l10n.scanActionFolder,
                      icon: Icons.folder_open_outlined,
                      variant: AppleButtonVariant.secondary,
                      onPressed: onPickFolder,
                    ),
                    if (showHomeAction)
                      AppleButton(
                        key: directoryBrowseHomeActionKey,
                        label: l10n.scanActionHome,
                        icon: Icons.home_outlined,
                        variant: AppleButtonVariant.pearl,
                        onPressed: onBrowseHome,
                      ),
                    if (scanning)
                      AppleButton(
                        label: l10n.scanActionCancel,
                        icon: Icons.stop_outlined,
                        variant: AppleButtonVariant.darkUtility,
                        onPressed: onCancelScan,
                      ),
                  ],
                ),
              ],
            ),
            if (scanning) ...[
              const SizedBox(height: AppleSpacing.sm),
              ValueListenableBuilder<double?>(
                valueListenable: scannedFraction,
                builder: (context, frac, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(AppleRadius.pill),
                        ),
                        child: LinearProgressIndicator(
                          value: frac,
                          minHeight: 3,
                        ),
                      ),
                      const SizedBox(height: AppleSpacing.xxs),
                      ValueListenableBuilder<String?>(
                        valueListenable: elapsedLabel,
                        builder: (context, _, __) {
                          return Text(
                            progressSummary(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.vwFinePrint,
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
              if (scanRootsEmpty) ...[
                const SizedBox(height: AppleSpacing.xxs),
                Text(l10n.scanHomeLongRunningHint, style: context.vwFinePrint),
              ],
            ] else if (scanStatus != null) ...[
              const SizedBox(height: AppleSpacing.xxs),
              Text(scanStatus!, style: context.vwFinePrint),
            ],
          ],
        ),
      ),
    );
  }
}
