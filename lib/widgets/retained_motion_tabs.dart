import 'package:flutter/material.dart';

/// Switch immediately while retaining both pages and their scroll positions.
class RetainedMotionTabs extends StatelessWidget {
  const RetainedMotionTabs(
      {super.key, required this.index, required this.children});
  final int index;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        for (var i = 0; i < children.length; i++)
          Offstage(
              offstage: i != index,
              child: TickerMode(enabled: i == index, child: children[i]))
      ]);
}
