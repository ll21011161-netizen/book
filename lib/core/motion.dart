import 'dart:math' as math;
import 'package:flutter/material.dart';

enum MotionCurve { linear, easeInOut, easeOut, spring }

enum PageMotion { none, fade, slide, scale, fadeSlide, zoomFade }

enum DetailMotion { followPage, containerTransform }

enum PressMotion { none, scale, spring }

/// Version-tolerant legacy storage. Keep names for safe old-data round trips.
/// MotionScope exposes only the enabled switch; retired options never run.
@immutable
class MotionSettings {
  const MotionSettings(
      {this.enabled = true,
      this.curve = MotionCurve.easeInOut,
      this.page = PageMotion.none,
      this.detail = DetailMotion.containerTransform,
      this.press = PressMotion.none,
      this.bounce = false,
      this.milliseconds = 250});
  final bool enabled, bounce;
  final MotionCurve curve;
  final PageMotion page;
  final DetailMotion detail;
  final PressMotion press;
  final int milliseconds;

  Curve get timingCurve => switch (curve) {
        MotionCurve.linear => Curves.linear,
        MotionCurve.easeInOut => Curves.easeInOut,
        MotionCurve.easeOut => Curves.easeOutCubic,
        MotionCurve.spring => const GentleSpring(),
      };
  Duration duration([double ratio = 1]) => enabled
      ? Duration(milliseconds: (milliseconds * ratio).round())
      : Duration.zero;
  // Old bounce preferences remain readable but no longer affect scrolling.
  ScrollPhysics get scrollPhysics =>
      const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  MotionSettings copyWith(
          {bool? enabled,
          bool? bounce,
          MotionCurve? curve,
          PageMotion? page,
          DetailMotion? detail,
          PressMotion? press,
          int? milliseconds}) =>
      MotionSettings(
          enabled: enabled ?? this.enabled,
          bounce: bounce ?? this.bounce,
          curve: curve ?? this.curve,
          page: page ?? this.page,
          detail: detail ?? this.detail,
          press: press ?? this.press,
          milliseconds: (milliseconds ?? this.milliseconds).clamp(100, 600));
  @override
  bool operator ==(Object other) =>
      other is MotionSettings &&
      enabled == other.enabled &&
      bounce == other.bounce &&
      curve == other.curve &&
      page == other.page &&
      detail == other.detail &&
      press == other.press &&
      milliseconds == other.milliseconds;
  @override
  int get hashCode =>
      Object.hash(enabled, bounce, curve, page, detail, press, milliseconds);

  Map<String, Object> toJson() => {
        'enabled': enabled,
        'bounce': bounce,
        'curve': curve.name,
        'page': page.name,
        'detail': detail.name,
        'press': press.name,
        'milliseconds': milliseconds
      };
  factory MotionSettings.fromJson(Map<String, dynamic> data) {
    T choice<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((e) => e.name == name).firstOrNull ?? fallback;
    final ms = data['milliseconds'];
    return MotionSettings(
        enabled: data['enabled'] is bool ? data['enabled'] as bool : true,
        bounce: data['bounce'] is bool ? data['bounce'] as bool : false,
        curve: choice(MotionCurve.values, data['curve'], MotionCurve.easeInOut),
        page: choice(PageMotion.values, data['page'], PageMotion.none),
        detail: choice(DetailMotion.values, data['detail'],
            DetailMotion.containerTransform),
        press: choice(PressMotion.values, data['press'], PressMotion.none),
        milliseconds: ms is int && ms >= 100 && ms <= 600 ? ms : 250);
  }
}

/// A single, strongly damped overshoot (< 0.5% page scale at 0.96 start).
class GentleSpring extends Curve {
  const GentleSpring();
  @override
  double transformInternal(double t) =>
      1 - math.exp(-7 * t) * math.cos(8 * t) + t * math.exp(-7) * math.cos(8);
}

class MotionScope extends InheritedWidget {
  const MotionScope({super.key, required this.settings, required super.child});
  final MotionSettings settings;
  static MotionSettings of(BuildContext context) {
    final value =
        context.dependOnInheritedWidgetOfExactType<MotionScope>()?.settings ??
            const MotionSettings();
    return MotionSettings(
        enabled: value.enabled && !MediaQuery.disableAnimationsOf(context));
  }

  @override
  bool updateShouldNotify(MotionScope oldWidget) =>
      oldWidget.settings != settings;
}
