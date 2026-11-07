import 'package:flutter/material.dart';
import '../core/cover_origin.dart';
import '../core/constants.dart';

/// Container geometry is independent of page layout. The detail subtree gets
/// full viewport constraints once; FittedBox only transforms its painted layer.
/// A route owns the one small source snapshot and the existing route animation.
class CoverContainerTransition extends StatefulWidget {
  const CoverContainerTransition(
      {super.key,
      required this.animation,
      required this.snapshot,
      required this.enabled,
      required this.gesture,
      required this.child});
  final Animation<double> animation;
  final CoverSnapshot snapshot;
  final bool enabled, gesture;
  final Widget child;
  @override
  State<CoverContainerTransition> createState() =>
      _CoverContainerTransitionState();
}

class _CoverContainerTransitionState extends State<CoverContainerTransition> {
  double _lastRaw = 0, _startRaw = 0;
  double _body = 0, _cover = 1, _alpha = 1;
  double _startBody = 0, _startCover = 1, _startAlpha = 1;
  Rect? _rect, _startRect, _target;
  bool _exiting = false, _fallback = false;

  void _rebase(double raw) {
    _startRaw = raw;
    _startRect = _rect;
    _startBody = _body;
    _startCover = _cover;
    _startAlpha = _alpha;
  }

  static double _mix(double a, double b, double t) => a + (b - a) * t;
  // Continuous position and velocity, one gentle settle (~0.48% overshoot).
  // This approximates the recording's visual rhythm, not its unknown curve.
  static double _enter(double t) => 1 + (1.4 * t - 1) * (1 - t) * (1 - t);

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        final full = Offset.zero & size;
        final fallbackRect = Rect.fromCenter(
            center: full.center,
            width: full.width * .96,
            height: full.height * .96);
        return AnimatedBuilder(
            animation: widget.animation,
            child: RepaintBoundary(
                child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: widget.child)),
            builder: (context, child) {
              final raw = widget.animation.value.clamp(0.0, 1.0);
              _rect ??= widget.snapshot.rect;
              _startRect ??= widget.snapshot.rect;
              final reversing =
                  widget.animation.status == AnimationStatus.reverse ||
                      (widget.gesture && raw < _lastRaw);
              final resuming = !reversing && raw > _lastRaw;
              if (!_exiting && reversing) {
                _rebase(_lastRaw);
                _exiting = true;
                _target = widget.snapshot.origin.resolveRect();
                _fallback = _target == null;
                _target ??= fallbackRect;
              } else if (_exiting && resuming) {
                _rebase(_lastRaw);
                _exiting = false;
              }
              if (_exiting) {
                if (!_fallback &&
                    widget.snapshot.origin.resolveRect() == null) {
                  // A deleted/virtualized target during pop fades from the CURRENT
                  // rectangle instead of jumping to a centered scale transition.
                  _rebase(_lastRaw);
                  _fallback = true;
                  _target = fallbackRect;
                }
                final ratio =
                    _startRaw <= 0 ? 0.0 : (raw / _startRaw).clamp(0.0, 1.0);
                final t = widget.gesture ? ratio : 1 - _enter(1 - ratio);
                _rect = Rect.lerp(_target, _startRect, t)!;
                _body = _fallback
                    ? _startBody
                    : _startBody *
                        const Interval(.65, 1, curve: Curves.easeInOut)
                            .transform(ratio);
                _cover = _fallback
                    ? _startCover * t
                    : _mix(1, _startCover,
                        const Interval(.35, 1).transform(ratio));
                _alpha = _fallback ? _startAlpha * t : 1;
              } else {
                final ratio = _startRaw >= 1
                    ? 1.0
                    : ((raw - _startRaw) / (1 - _startRaw)).clamp(0.0, 1.0);
                final t = widget.gesture ? ratio : _enter(ratio);
                _rect = Rect.lerp(_startRect, full, t)!;
                _body = _mix(
                    _startBody,
                    1,
                    const Interval(AppConstants.coverContentFadeStart,
                            AppConstants.coverContentFadeEnd,
                            curve: Curves.easeInOut)
                        .transform(ratio));
                _cover = _mix(
                    _startCover, 0, const Interval(.15, .65).transform(ratio));
                _alpha = 1;
              }
              _lastRaw = raw;
              // Keep the same element tree even at endpoints / reduced motion.
              final rect = widget.enabled ? _rect! : full;
              final radius = widget.enabled
                  ? widget.snapshot.origin.radius * (1 - raw)
                  : 0.0;
              return Stack(fit: StackFit.expand, children: [
                Positioned.fromRect(
                    rect: rect,
                    child: Opacity(
                        opacity: widget.enabled ? _alpha.clamp(0.0, 1.0) : 1,
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(radius),
                            child: ColoredBox(
                                color: Color.lerp(
                                    widget.snapshot.origin.color,
                                    Theme.of(context).colorScheme.surface,
                                    raw)!,
                                child: Stack(fit: StackFit.expand, children: [
                                  Opacity(
                                      opacity: widget.enabled
                                          ? _body.clamp(0.0, 1.0)
                                          : 1,
                                      child: FittedBox(
                                          fit: BoxFit.fill, child: child)),
                                  if (widget.snapshot.image != null)
                                    IgnorePointer(
                                        child: Opacity(
                                            opacity: widget.enabled
                                                ? _cover.clamp(0.0, 1.0)
                                                : 0,
                                            child: RawImage(
                                                image: widget.snapshot.image,
                                                fit: BoxFit.cover,
                                                filterQuality:
                                                    FilterQuality.low))),
                                ]))))),
              ]);
            });
      });
}
