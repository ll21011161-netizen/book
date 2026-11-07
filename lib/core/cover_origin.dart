import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// A route-local source, never a global tag registry. Position is resolved again
/// at pop time, so scrolling/reordering is accounted for. No image is decoded.
class CoverOrigin {
  CoverOrigin(
      {required this.resolveRect,
      required this.captureImage,
      required this.radius,
      required this.color});
  final Rect? Function() resolveRect;
  final ui.Image? Function() captureImage;
  final double radius;
  final Color color;
}

/// The route owns this small raster of the already painted cover. It cannot
/// change when a thumbnail resolves later, a GIF advances, or a cache is evicted.
class CoverSnapshot {
  CoverSnapshot({required this.origin, required this.rect, this.image});
  final CoverOrigin origin;
  final Rect rect;
  final ui.Image? image;
  void dispose() => image?.dispose();
}
