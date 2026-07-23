import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/apple_tokens.dart';

enum AppleButtonVariant { primary, secondary, pearl, darkUtility }

class AppleButton extends StatefulWidget {
  const AppleButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = AppleButtonVariant.primary,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppleButtonVariant variant;
  final bool expanded;

  @override
  State<AppleButton> createState() => _AppleButtonState();
}

class _AppleButtonState extends State<AppleButton> {
  bool _pressed = false;

  (Color bg, Color fg, BorderSide? border, EdgeInsets padding, TextStyle textStyle)
      _style() {
    switch (widget.variant) {
      case AppleButtonVariant.primary:
        return (
          AppleColors.primary,
          AppleColors.onPrimary,
          null,
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          AppleTypography.captionStrong.copyWith(color: AppleColors.onPrimary, height: 1.2),
        );
      case AppleButtonVariant.secondary:
        return (
          AppleColors.canvas,
          AppleColors.primary,
          const BorderSide(color: AppleColors.primary),
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          AppleTypography.captionStrong.copyWith(color: AppleColors.primary, height: 1.2),
        );
      case AppleButtonVariant.pearl:
        return (
          AppleColors.surfacePearl,
          AppleColors.inkMuted80,
          const BorderSide(color: AppleColors.dividerSoft, width: 2),
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          AppleTypography.caption,
        );
      case AppleButtonVariant.darkUtility:
        return (
          AppleColors.ink,
          AppleColors.bodyOnDark,
          null,
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          AppleTypography.caption.copyWith(color: AppleColors.bodyOnDark),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border, padding, textStyle) = _style();
    final enabled = widget.onPressed != null;
    final radius = widget.variant == AppleButtonVariant.pearl ||
            widget.variant == AppleButtonVariant.darkUtility
        ? AppleRadius.sm
        : AppleRadius.pill;

    final child = AnimatedScale(
      scale: _pressed && enabled ? 0.95 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: Material(
        color: enabled ? bg : bg.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: border ?? BorderSide.none,
        ),
        child: InkWell(
          onTap: enabled ? widget.onPressed : null,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          borderRadius: BorderRadius.circular(radius),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: padding,
            child: Row(
              mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 16, color: enabled ? fg : fg.withValues(alpha: 0.5)),
                  const SizedBox(width: AppleSpacing.xs),
                ],
                Text(
                  widget.label,
                  style: textStyle.copyWith(
                    color: enabled ? fg : fg.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.expanded) {
      return SizedBox(width: double.infinity, child: child);
    }
    return child;
  }
}

class AppleUtilityCard extends StatelessWidget {
  const AppleUtilityCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppleSpacing.md),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppleColors.canvas,
        borderRadius: BorderRadius.circular(AppleRadius.lg),
        border: Border.all(color: AppleColors.hairline),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class AppleSectionHeader extends StatelessWidget {
  const AppleSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppleTypography.bodyStrong),
          if (subtitle != null) ...[
            const SizedBox(height: AppleSpacing.xxs),
            Text(subtitle!, style: AppleTypography.caption),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppleTypography.displayLg),
        if (subtitle != null) ...[
          const SizedBox(height: AppleSpacing.xs),
          Text(subtitle!, style: AppleTypography.lead.copyWith(fontSize: 21, height: 1.4)),
        ],
      ],
    );
  }
}

class AppleOptionChip extends StatelessWidget {
  const AppleOptionChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppleColors.canvas,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppleColors.primaryFocus : AppleColors.hairline,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => onSelected(!selected),
        customBorder: const StadiumBorder(),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: AppleTypography.finePrint.copyWith(
              color: selected ? AppleColors.ink : AppleColors.inkMuted80,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class AppleListRow extends StatelessWidget {
  const AppleListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.onTap,
    this.selected = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppleColors.canvasParchment : AppleColors.canvas,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: AppleColors.canvasParchment,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppleSpacing.md,
            vertical: AppleSpacing.xs,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppleSpacing.xs),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppleTypography.captionStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(subtitle!, style: AppleTypography.finePrint),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppleSpacing.sm),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ApplePageShell extends StatelessWidget {
  const ApplePageShell({
    super.key,
    required this.child,
    this.maxWidth = 980,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppleSpacing.xl,
      vertical: AppleSpacing.xxl,
    ),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppleColors.canvasParchment,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SingleChildScrollView(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class AppleStickyBar extends StatelessWidget {
  const AppleStickyBar({
    super.key,
    required this.leading,
    required this.action,
  });

  final Widget leading;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppleSpacing.lg, vertical: AppleSpacing.sm),
          decoration: BoxDecoration(
            color: AppleColors.canvasParchment.withValues(alpha: 0.8),
            border: const Border(top: BorderSide(color: AppleColors.hairline)),
          ),
          child: Row(
            children: [
              Expanded(child: leading),
              action,
            ],
          ),
        ),
      ),
    );
  }
}
