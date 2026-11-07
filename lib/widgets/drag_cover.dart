import 'package:flutter/material.dart';
import '../core/theme.dart';

enum DragVisualMode { none, reorder, merge }

/// Paint-only feedback: the card's layout and hit area remain unchanged.
class DragCover extends StatelessWidget {
  const DragCover({super.key, required this.mode, required this.child});
  final DragVisualMode mode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final merge = mode == DragVisualMode.merge;
    final active = mode != DragVisualMode.none;
    final color = merge ? Theme.of(context).colorScheme.primary : Colors.blue;
    return SizedBox(
      child: Stack(fit: StackFit.expand, children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
                color: color.withValues(alpha: active ? 0.12 : 0),
                border: Border.all(
                    color: active ? color : Colors.transparent,
                    width: merge ? 3 : 2),
              ),
              child: active
                  ? Center(
                      key: ValueKey(mode),
                      child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle),
                          child: Icon(
                              merge ? Icons.create_new_folder : Icons.swap_vert,
                              size: 22,
                              color: Colors.white)))
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ]),
    );
  }
}
