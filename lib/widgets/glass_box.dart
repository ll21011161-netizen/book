import 'dart:ui';
import 'package:flutter/material.dart';

class GlassBox extends StatelessWidget {
  final Widget child;
  final double blur, opacity;
  final Color color;
  final Border? border;
  const GlassBox(
      {super.key,
      required this.child,
      this.blur = 10,
      this.opacity = 0.7,
      this.color = Colors.white,
      this.border});
  @override
  Widget build(BuildContext context) {
    final surface = DecoratedBox(
      decoration: BoxDecoration(
          color: color.withValues(alpha: opacity), border: border),
      child: child,
    );
    if (blur <= 0) return surface;
    return ClipRect(
        child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: surface));
  }
}
