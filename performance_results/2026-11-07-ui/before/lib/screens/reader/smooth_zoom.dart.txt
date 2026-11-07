// lib/screens/reader/smooth_zoom.dart
import 'package:flutter/material.dart';
import '../../core/constants.dart'; // 🌟 引入動畫常數

class SmoothScopeZoom extends StatefulWidget {
  final Widget child;
  final double zoomScale;
  final double sensitivity;

  const SmoothScopeZoom({
    super.key,
    required this.child,
    this.zoomScale = 2.5,
    this.sensitivity = 1.0, 
  });

  @override
  State<SmoothScopeZoom> createState() => _SmoothScopeZoomState();
}

class _SmoothScopeZoomState extends State<SmoothScopeZoom> with SingleTickerProviderStateMixin {
  final ValueNotifier<Matrix4> _matrixNotifier = ValueNotifier(Matrix4.identity());
  late AnimationController _controller;
  late Animation<Matrix4> _animation;
  
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // 🌟 統一使用 Normal 動畫長度
      duration: AppConstants.animDurationNormal,
    );
    _animation = Matrix4Tween(begin: Matrix4.identity(), end: Matrix4.identity()).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    _matrixNotifier.dispose();
    super.dispose();
  }

  void _updateMatrix(Offset touchPosition) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    
    final Size childSize = box.size;
    final Size viewportSize = MediaQuery.of(context).size;
    final Offset center = childSize.center(Offset.zero);

    double dx = (center.dx - touchPosition.dx) * (widget.sensitivity - 1);
    double dy = (center.dy - touchPosition.dy) * (widget.sensitivity - 1);

    final Matrix4 newMatrix = Matrix4.identity()
      ..translate(touchPosition.dx + dx, touchPosition.dy + dy) 
      ..scale(widget.zoomScale)
      ..translate(-touchPosition.dx, -touchPosition.dy);

    if (widget.zoomScale > 1.0) {
      double tx = newMatrix.getTranslation().x;
      double ty = newMatrix.getTranslation().y;
      
      final double ox = (viewportSize.width - childSize.width) / 2;
      final double oy = (viewportSize.height - childSize.height) / 2;
      
      final double scaledWidth = childSize.width * widget.zoomScale;
      final double scaledHeight = childSize.height * widget.zoomScale;

      final double scaledOx = ox * widget.zoomScale;
      final double scaledOy = oy * widget.zoomScale;

      double minTx, maxTx;
      if (scaledWidth > viewportSize.width) {
        minTx = viewportSize.width - scaledOx - scaledWidth;
        maxTx = -scaledOx;
      } else {
        minTx = (viewportSize.width - scaledWidth) / 2 - scaledOx;
        maxTx = minTx;
      }

      double minTy, maxTy;
      if (scaledHeight > viewportSize.height) {
        minTy = viewportSize.height - scaledOy - scaledHeight;
        maxTy = -scaledOy;
      } else {
        minTy = (viewportSize.height - scaledHeight) / 2 - scaledOy;
        maxTy = minTy;
      }

      tx = tx.clamp(minTx, maxTx);
      ty = ty.clamp(minTy, maxTy);
      
      newMatrix.setTranslationRaw(tx, ty, 0.0);
    }

    _matrixNotifier.value = newMatrix;
  }

  void _onLongPressStart(LongPressStartDetails details) {
    _isActive = true;
    _controller.stop();
    _updateMatrix(details.localPosition);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isActive) return;
    _updateMatrix(details.localPosition);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    _isActive = false;
    _animation = Matrix4Tween(
      begin: _matrixNotifier.value,
      end: Matrix4.identity(),
    // 🌟 回彈動畫統一使用 Standard 曲線
    ).animate(CurveTween(curve: AppConstants.animCurveStandard).animate(_controller));

    _controller
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: () => _onLongPressEnd(const LongPressEndDetails()),
      behavior: HitTestBehavior.translucent,
      child: AnimatedBuilder(
        animation: Listenable.merge([_controller, _matrixNotifier]),
        builder: (context, child) {
          Matrix4 currentMatrix;
          if (_isActive) {
            currentMatrix = _matrixNotifier.value;
          } else {
            currentMatrix = _controller.isAnimating ? _animation.value : Matrix4.identity();
          }

          return Transform(
            transform: currentMatrix,
            alignment: Alignment.topLeft, 
            child: widget.child,
          );
        },
      ),
    );
  }
}