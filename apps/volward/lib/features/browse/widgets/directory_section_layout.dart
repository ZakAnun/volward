import 'package:flutter/material.dart';
import 'package:volward/theme/apple_tokens.dart';

const double directoryContentMaxWidth = double.infinity;
const double directoryDetailHorizontalInset = 24;

/// Constrains a section to the content column and applies its default inset.
Widget padDirectorySection(Widget child, {EdgeInsets? padding}) {
  return Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: directoryContentMaxWidth),
      child: Padding(
        padding:
            padding ??
            const EdgeInsets.fromLTRB(
              directoryDetailHorizontalInset,
              AppleSpacing.sm,
              directoryDetailHorizontalInset,
              0,
            ),
        child: child,
      ),
    ),
  );
}

/// Like [padDirectorySection] but fills the remaining vertical space (for the
/// column browser). The horizontal axis matches the sections above it.
Widget padDirectorySectionExpanded(
  Widget child, {
  required EdgeInsets padding,
}) {
  return Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: directoryContentMaxWidth),
      child: Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxH = constraints.maxHeight;
            if (!maxH.isFinite || maxH <= 0) {
              return const SizedBox.shrink();
            }
            return SizedBox(
              width: constraints.maxWidth,
              height: maxH,
              child: child,
            );
          },
        ),
      ),
    ),
  );
}
