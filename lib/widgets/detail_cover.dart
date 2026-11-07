import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../core/config.dart';
import 'app_image.dart';
import 'page_thumbnail.dart';

/// Keep a shelf-sized preview mounted underneath a later high-resolution image.
/// A decode miss/error cannot replace it with a blank/error frame.
class DetailCover extends StatefulWidget {
  const DetailCover(
      {super.key,
      required this.path,
      required this.upgrade,
      this.fit = BoxFit.cover,
      this.onImageProvider});
  final String path;
  final bool upgrade;
  final BoxFit fit;
  final ValueChanged<ImageProvider>? onImageProvider;
  @override
  State<DetailCover> createState() => _DetailCoverState();
}

class _DetailCoverState extends State<DetailCover> {
  bool _highReady = false;
  @override
  void didUpdateWidget(DetailCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _highReady = false;
  }

  @override
  Widget build(BuildContext context) {
    final canUpgrade = !const {'.gif', '.webp'}
        .contains(p.extension(widget.path).toLowerCase());
    return Stack(fit: StackFit.expand, children: [
      Offstage(
          offstage: _highReady,
          child: PageThumbnail(
              path: widget.path,
              fit: widget.fit,
              cacheWidth: AppConfig.thumbnailCacheWidth,
              borderRadius: BorderRadius.zero,
              preserveAnimation: true,
              deferGenerationUntilReady: true,
              generationEnabled: false,
              onImageProvider: widget.onImageProvider)),
      if (canUpgrade && (widget.upgrade || _highReady))
        AppImage(
            path: widget.path,
            fit: widget.fit,
            cacheWidth: AppConfig.detailCoverWidth,
            onImageReady: () {
              if (mounted && !_highReady) setState(() => _highReady = true);
            },
            errorPlaceholder: const SizedBox.expand()),
    ]);
  }
}
