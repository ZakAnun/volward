import 'package:flutter/material.dart';
import 'package:volward/theme/apple_tokens.dart';
import 'package:volward/theme/volward_tokens.dart';
import 'directory_section_layout.dart';

/// Skeleton shown while a snapshot is restoring or a folder is being prepared.
class DirectoryRestoreLoading extends StatelessWidget {
  const DirectoryRestoreLoading({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    Widget skeletonBar(
      double width, {
      double height = 10,
      double radius = AppleRadius.sm,
    }) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: v.inkMuted48.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: SizedBox(width: width, height: height),
      );
    }

    Widget skeletonIcon(IconData icon, {Color? color}) {
      return SizedBox(
        width: 20,
        height: 20,
        child: Icon(
          icon,
          size: 18,
          color: color ?? v.inkMuted48.withValues(alpha: 0.44),
        ),
      );
    }

    Widget skeletonChip(double width) {
      return skeletonBar(width, height: 24, radius: AppleRadius.pill);
    }

    Widget skeletonToolbar() {
      return padDirectorySection(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: v.primary,
                  ),
                ),
                const SizedBox(width: AppleSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: context.vwFinePrintInk),
                      const SizedBox(height: 4),
                      skeletonBar(280, height: 8),
                    ],
                  ),
                ),
                const SizedBox(width: AppleSpacing.xs),
                skeletonBar(44, height: 12),
                const SizedBox(width: AppleSpacing.xs),
                skeletonChip(82),
                const SizedBox(width: AppleSpacing.xxs),
                skeletonChip(62),
              ],
            ),
            const SizedBox(height: AppleSpacing.xxs),
            DecoratedBox(
              decoration: BoxDecoration(
                color: v.surfacePearl,
                borderRadius: BorderRadius.circular(AppleRadius.sm),
                border: Border.all(color: v.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppleSpacing.sm,
                  vertical: AppleSpacing.xxs,
                ),
                child: SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      skeletonChip(48),
                      const SizedBox(width: AppleSpacing.xxs),
                      skeletonChip(62),
                      const SizedBox(width: AppleSpacing.xxs),
                      skeletonChip(56),
                      const SizedBox(width: AppleSpacing.xxs),
                      skeletonChip(64),
                      const SizedBox(width: AppleSpacing.xxs),
                      skeletonChip(68),
                      const Spacer(),
                      skeletonChip(92),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppleSpacing.xxs),
            ClipRRect(
              borderRadius: const BorderRadius.all(
                Radius.circular(AppleRadius.pill),
              ),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: v.primary,
                backgroundColor: v.hairline,
              ),
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

    Widget skeletonColumn({required double width, required int rows}) {
      return Container(
        width: width,
        decoration: BoxDecoration(
          color: v.canvas,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          border: Border.all(color: v.hairline),
        ),
        padding: const EdgeInsets.all(AppleSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            skeletonBar(width * 0.55, height: 12),
            const SizedBox(height: AppleSpacing.sm),
            for (var i = 0; i < rows; i++) ...[
              Row(
                children: [
                  skeletonIcon(
                    Icons.folder_outlined,
                    color: v.folderIcon.withValues(alpha: 0.42),
                  ),
                  const SizedBox(width: AppleSpacing.xs),
                  Expanded(child: skeletonBar(width * (0.38 + (i % 4) * 0.09))),
                  const SizedBox(width: AppleSpacing.xs),
                  skeletonBar(34 + (i % 3) * 12, height: 8),
                ],
              ),
              if (i != rows - 1) const SizedBox(height: AppleSpacing.sm),
            ],
          ],
        ),
      );
    }

    Widget skeletonBrowser() {
      return padDirectorySectionExpanded(
        LayoutBuilder(
          builder: (context, constraints) {
            final browserHeight =
                constraints.maxHeight.isFinite && constraints.maxHeight > 0
                ? constraints.maxHeight
                : 360.0;

            int rowsFor(int target) {
              const rowHeight = 20.0;
              const chromeHeight =
                  AppleSpacing.sm * 2 + 12 + AppleSpacing.sm + 16;
              final available = browserHeight - chromeHeight;
              final maxRows =
                  ((available + AppleSpacing.sm) /
                          (rowHeight + AppleSpacing.sm))
                      .floor()
                      .clamp(3, 8);
              return target < maxRows ? target : maxRows;
            }

            return DecoratedBox(
              decoration: BoxDecoration(
                color: v.canvasParchment,
                borderRadius: BorderRadius.circular(AppleRadius.sm),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    skeletonColumn(width: 220, rows: rowsFor(7)),
                    const SizedBox(width: AppleSpacing.xs),
                    skeletonColumn(width: 220, rows: rowsFor(6)),
                    const SizedBox(width: AppleSpacing.xs),
                    skeletonColumn(width: 220, rows: rowsFor(5)),
                    const SizedBox(width: AppleSpacing.xs),
                    skeletonColumn(width: 220, rows: rowsFor(4)),
                  ],
                ),
              ),
            );
          },
        ),
        padding: const EdgeInsets.fromLTRB(
          directoryDetailHorizontalInset,
          0,
          directoryDetailHorizontalInset,
          AppleSpacing.xxs,
        ),
      );
    }

    Widget skeletonPreview() {
      return padDirectorySection(
        Material(
          color: v.canvas,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppleRadius.sm),
            side: BorderSide(color: v.hairline),
          ),
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppleSpacing.sm),
              child: Row(
                children: [
                  skeletonIcon(Icons.insert_drive_file_outlined),
                  const SizedBox(width: AppleSpacing.xs),
                  Expanded(child: skeletonBar(220, height: 10)),
                  const SizedBox(width: AppleSpacing.sm),
                  skeletonBar(88, height: 10),
                  const SizedBox(width: AppleSpacing.sm),
                  skeletonChip(96),
                ],
              ),
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          directoryDetailHorizontalInset,
          0,
          directoryDetailHorizontalInset,
          AppleSpacing.xxs,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        skeletonToolbar(),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: skeletonBrowser()),
              skeletonPreview(),
            ],
          ),
        ),
      ],
    );
  }
}
