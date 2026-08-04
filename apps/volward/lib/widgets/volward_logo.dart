import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/volward_tokens.dart';

class VolwardLogoMark extends StatelessWidget {
  const VolwardLogoMark({
    super.key,
    this.size = 24,
    this.showBackground = true,
  });

  final double size;
  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    final brightness = Theme.of(context).brightness;
    return Semantics(
      label: 'Volward',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _VolwardLogoPainter(
            tokens: tokens,
            brightness: brightness,
            showBackground: showBackground,
          ),
        ),
      ),
    );
  }
}

class _VolwardLogoPainter extends CustomPainter {
  const _VolwardLogoPainter({
    required this.tokens,
    required this.brightness,
    required this.showBackground,
  });

  final VolwardTokens tokens;
  final Brightness brightness;
  final bool showBackground;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rect = Offset.zero & size;
    final isDark = brightness == Brightness.dark;

    if (showBackground) {
      final bg = Paint()
        ..color = isDark ? tokens.surfacePearl : tokens.canvas
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(s * 0.22)),
        bg,
      );

      final border = Paint()
        ..color = isDark
            ? tokens.hairline.withValues(alpha: 0.9)
            : tokens.hairline.withValues(alpha: 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, s * 0.025);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            rect.deflate(s * 0.012), Radius.circular(s * 0.2)),
        border,
      );
    }

    final beamLeft = Path()
      ..moveTo(s * 0.30, s * 0.28)
      ..lineTo(s * 0.41, s * 0.22)
      ..lineTo(s * 0.56, s * 0.54)
      ..lineTo(s * 0.48, s * 0.62)
      ..close();
    final beamRight = Path()
      ..moveTo(s * 0.70, s * 0.28)
      ..lineTo(s * 0.59, s * 0.22)
      ..lineTo(s * 0.44, s * 0.54)
      ..lineTo(s * 0.52, s * 0.62)
      ..close();

    final leftPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Color.lerp(tokens.folderIcon, Colors.white, isDark ? 0.18 : 0.0) ??
              tokens.folderIcon,
          Color.lerp(tokens.folderIcon, tokens.primary, 0.18) ?? tokens.primary,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, s, s));
    final rightPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Color.lerp(tokens.primary, Colors.white, isDark ? 0.12 : 0.0) ??
              tokens.primary,
          Color.lerp(tokens.primary, tokens.folderIcon, 0.12) ?? tokens.primary,
        ],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ).createShader(Rect.fromLTWH(0, 0, s, s));

    canvas.drawPath(beamLeft, leftPaint);
    canvas.drawPath(beamRight, rightPaint);

    final tray = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.20, s * 0.63, s * 0.60, s * 0.19),
      Radius.circular(s * 0.08),
    );
    final trayFill = Paint()
      ..color = isDark ? const Color(0xFF203447) : const Color(0xFFEAF7FF)
      ..style = PaintingStyle.fill;
    final trayStroke = Paint()
      ..color = isDark
          ? const Color(0xFF79CFFF).withValues(alpha: 0.72)
          : const Color(0xFFA9DFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, s * 0.022);
    canvas.drawRRect(tray, trayFill);
    canvas.drawRRect(tray, trayStroke);

    final rail = Paint()
      ..color = isDark
          ? const Color(0xFF9AD7FF).withValues(alpha: 0.72)
          : const Color(0xFF94D7F8)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.2, s * 0.022);
    canvas.drawLine(
      Offset(s * 0.26, s * 0.71),
      Offset(s * 0.56, s * 0.71),
      rail,
    );

    final reclaim = Paint()
      ..color = const Color(0xFF34C759)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(1.6, s * 0.05);
    final arcRect = Rect.fromLTWH(s * 0.58, s * 0.70, s * 0.19, s * 0.12);
    canvas.drawArc(arcRect, math.pi * 0.15, math.pi * 0.9, false, reclaim);
    canvas.drawLine(
      Offset(s * 0.74, s * 0.74),
      Offset(s * 0.78, s * 0.72),
      reclaim,
    );
    canvas.drawLine(
      Offset(s * 0.74, s * 0.74),
      Offset(s * 0.76, s * 0.78),
      reclaim,
    );
  }

  @override
  bool shouldRepaint(covariant _VolwardLogoPainter oldDelegate) {
    return oldDelegate.brightness != brightness ||
        oldDelegate.showBackground != showBackground ||
        oldDelegate.tokens.primary != tokens.primary ||
        oldDelegate.tokens.folderIcon != tokens.folderIcon ||
        oldDelegate.tokens.surfacePearl != tokens.surfacePearl;
  }
}
