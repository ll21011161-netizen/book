import 'package:flutter/material.dart';

/// Immediate gestures with a stable hit region; no press controller or timer.
/// The name and arguments remain compatible with existing cards and buttons.
class SpringPress extends StatelessWidget {
  const SpringPress(
      {super.key,
      required this.child,
      required this.onTap,
      this.onLongPress,
      this.suppressMotion = false});
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool suppressMotion;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!TickerMode.of(context) ||
              ModalRoute.of(context)?.isCurrent == false) return;
          onTap();
        },
        onLongPress: onLongPress,
        child: child,
      );
}
