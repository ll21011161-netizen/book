import 'package:flutter/material.dart';
import 'motion.dart';

/// Baseline action ratios (250 ms = 1). MotionSettings owns user preferences.
class AppConstants {
  static const coverEnterDuration = Duration(milliseconds: 380);
  static const coverExitDuration = Duration(milliseconds: 300);
  static const coverSnapshotMaxExtent = 512.0;
  static const coverContentFadeStart = .45;
  static const coverContentFadeEnd = .9;
  static const pressDuration = Duration(milliseconds: 100);
  // Only the visual release is delayed. Navigation and callbacks are immediate.
  static const pressMinDuration = Duration(milliseconds: 48);
  static const pressScale = .97;
  static const dialogDuration = Duration(milliseconds: 250);
  static const dialogDismissDuration = Duration(milliseconds: 150);
  static const dragLiftDuration = Duration(milliseconds: 170);
  static const dragTiltDuration = Duration(milliseconds: 100);
  static const dragScale = 1.045;
  static const dragMaxTilt = .05;
  static const controlsDuration = Duration(milliseconds: 200);
  static const animDurationNormal = Duration(milliseconds: 250);

  // Image transforms deliberately use a bounded curve and independent timing:
  // an overshooting matrix could fight image-bound correction and user gestures.
  static const zoomDuration = Duration(milliseconds: 200);
  static const animCurveStandard = Curves.easeOutCubic;

  static Duration motionDuration(BuildContext context, Duration baseline) =>
      MotionScope.of(context).duration(baseline.inMilliseconds / 250);
}
