import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;
import 'perf_log.dart';
import 'motion.dart';
import 'cover_origin.dart';
import 'constants.dart';
import '../widgets/cover_container_transition.dart';

class AnimRoute<T> extends DetailRoute<T> {
  AnimRoute({required super.context, required super.page});
}

/// Single cover transition retaining the Material route/back gesture lifecycle.
/// Android predictive events use the framework route gesture lifecycle.
class DetailRoute<T> extends MaterialPageRoute<T> {
  DetailRoute(
      {required BuildContext context,
      required Widget page,
      CoverOrigin? source})
      : _motion = MotionScope.of(context),
        super(
            builder: (_) => HeroMode(enabled: false, child: page),
            allowSnapshotting: false,
            settings: const RouteSettings(name: 'library_detail')) {
    if (_motion.enabled && source != null) {
      final rect = source.resolveRect();
      if (rect != null) {
        _cover = CoverSnapshot(
            origin: source, rect: rect, image: source.captureImage());
      }
    }
    if (PerfLog.enabled) _watch.start();
  }
  CoverSnapshot? _cover;
  bool get hasCoverTransform => _cover != null;
  @override
  void dispose() {
    _cover?.dispose();
    _cover = null;
    super.dispose();
  }

  final MotionSettings _motion;
  final Stopwatch _watch = Stopwatch();
  bool _firstFrameScheduled = false;

  @override
  Duration get transitionDuration =>
      hasCoverTransform ? AppConstants.coverEnterDuration : Duration.zero;
  @override
  Duration get reverseTransitionDuration =>
      hasCoverTransform ? AppConstants.coverExitDuration : Duration.zero;
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;
  @override
  DelegatedTransitionBuilder? get delegatedTransition => null;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    if (PerfLog.enabled && !_firstFrameScheduled) {
      _firstFrameScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator != null) {
          PerfLog.event('detail_route_first_frame',
              {'elapsed_us': _watch.elapsedMicroseconds});
        }
      });
    }
    return super.buildPage(context, animation, secondaryAnimation);
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      _DetailBackTransition(
          route: this,
          cover: _cover,
          animation: animation,
          settings: MotionScope.of(context),
          android: Theme.of(context).platform == TargetPlatform.android,
          child: child);
}

/// Bridge Android's predictive events to the framework's public route gesture
/// lifecycle, retaining interactive progress and avoiding a commit flash.
class _DetailBackTransition extends StatefulWidget {
  const _DetailBackTransition(
      {required this.route,
      this.cover,
      required this.animation,
      required this.settings,
      required this.android,
      required this.child});
  final CoverSnapshot? cover;
  final PageRoute<dynamic> route;
  final Animation<double> animation;
  final MotionSettings settings;
  final bool android;
  final Widget child;
  @override
  State<_DetailBackTransition> createState() => _DetailBackTransitionState();
}

class _DetailBackTransitionState extends State<_DetailBackTransition>
    with WidgetsBindingObserver {
  Animation<double>? _commit;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent event) {
    if (!widget.android ||
        event.isButtonEvent ||
        !widget.route.isCurrent ||
        !widget.route.popGestureEnabled) {
      return false;
    }
    _commit = null;
    widget.route.handleStartBackGesture(progress: 1 - event.progress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent event) =>
      widget.route
          .handleUpdateBackGestureProgress(progress: 1 - event.progress);
  @override
  void handleCancelBackGesture() {
    _commit = null;
    widget.route.handleCancelBackGesture();
  }

  @override
  void handleCommitBackGesture() {
    // The framework restarts the route's exit controller at 1 on commit. Map
    // that value to the gesture's current opacity to avoid a one-frame flash.
    _commit = widget.animation
        .drive(Tween<double>(begin: 0, end: widget.animation.value));
    widget.route.handleCommitBackGesture();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.route.popGestureInProgress
        ? (_commit ?? widget.animation)
        : widget.animation;
    if (widget.cover != null) {
      return CoverContainerTransition(
          animation: progress,
          snapshot: widget.cover!,
          enabled: widget.settings.enabled,
          gesture: widget.route.popGestureInProgress,
          child: widget.child);
    }
    return widget.child;
  }
}
