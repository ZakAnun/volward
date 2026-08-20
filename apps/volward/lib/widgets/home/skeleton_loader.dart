import 'package:flutter/material.dart';

/// A simple skeleton loading indicator with subtle shimmer animation
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8.0,
    this.animate = true,
  });

  final double width;
  final double height;
  final double borderRadius;
  final bool animate;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    // Only animate when explicitly enabled (defaults to true in production)
    if (widget.animate) {
      _controller.repeat();
    }
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              // Base color: always visible as a solid shape
              color: Colors.white.withValues(alpha: 0.12),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.30),
                  Colors.white.withValues(alpha: 0.12),
                ],
                stops: [
                  (_animation.value - 0.3).clamp(0.0, 1.0),
                  _animation.value.clamp(0.0, 1.0),
                  (_animation.value + 0.3).clamp(0.0, 1.0),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
