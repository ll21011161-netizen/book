import 'dart:io';
import 'package:flutter/material.dart';
import '../core/config.dart';

class AppImage extends StatefulWidget {
  final String? path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final int? cacheWidth;
  final VoidCallback? onImageReady;
  final VoidCallback? onImageError;
  final Widget? errorPlaceholder;
  final ValueChanged<ImageProvider>? onImageProvider;

  const AppImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.cacheWidth,
    this.onImageReady,
    this.onImageError,
    this.errorPlaceholder,
    this.onImageProvider,
  });

  @override
  State<AppImage> createState() => _AppImageState();
}

class _AppImageState extends State<AppImage> {
  bool _ready = false;
  bool _error = false;
  int _generation = 0;
  ImageProvider? _provider;

  @override
  void didUpdateWidget(covariant AppImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.cacheWidth != widget.cacheWidth) {
      _generation++;
      _ready = false;
      _error = false;
    } else if (_ready && oldWidget.onImageProvider != widget.onImageProvider) {
      final generation = _generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation && _provider != null) {
          widget.onImageProvider?.call(_provider!);
        }
      });
    }
  }

  void _notify(bool success) {
    if (success ? _ready : _error) return;
    if (success) {
      _ready = true;
    } else {
      _error = true;
    }
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      if (success) {
        if (_provider != null) widget.onImageProvider?.call(_provider!);
        widget.onImageReady?.call();
      } else {
        widget.onImageError?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.zero;
    final int optimizedCacheWidth =
        widget.cacheWidth ?? AppConfig.thumbnailCacheWidth;

    if (widget.path == null || widget.path!.isEmpty) {
      return ClipRRect(borderRadius: radius, child: _buildError());
    }

    final provider = ResizeImage.resizeIfNeeded(
        optimizedCacheWidth, null, FileImage(File(widget.path!)));
    _provider = provider;
    return ClipRRect(
      borderRadius: radius,
      child: Image(
        image: provider,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        // Keep the existing thumbnail sampling policy.
        filterQuality: FilterQuality.low,
        // [優化] 如果不需要 AnimatedOpacity，可以直接回傳 child 減少 GPU 負擔
        frameBuilder: (context, child, frame, wasSync) {
          if (wasSync || frame != null) _notify(true);
          return child;
        },
        errorBuilder: (_, __, ___) {
          _notify(false);
          return _buildError();
        },
      ),
    );
  }

  Widget _buildError() {
    return widget.errorPlaceholder ??
        Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey[800],
          child: const Icon(Icons.broken_image, color: Colors.white24),
        );
  }
}
