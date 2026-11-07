import 'package:flutter/material.dart';

/// Paint-only motion: the controls keep a stable layout while sliding entirely
/// outside the viewport, including large text and system safe areas.
class ReaderControlsTransition extends StatelessWidget {
  const ReaderControlsTransition(
      {super.key,
      required this.visible,
      required this.fromTop,
      required this.child});
  final bool visible;
  final bool fromTop;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: AnimatedSlide(
            offset: visible ? Offset.zero : Offset(0, fromTop ? -1 : 1),
            duration: Duration.zero,
            curve: Curves.linear,
            child: TickerMode(enabled: visible, child: child),
          ),
        ),
      );
}
