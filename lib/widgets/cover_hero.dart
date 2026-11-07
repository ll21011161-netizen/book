import '../core/theme.dart';
import '../core/config.dart';
import 'page_thumbnail.dart';
import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import '../core/constants.dart';
import '../core/cover_origin.dart';
import 'package:flutter/material.dart';

typedef CoverImageReporter = void Function(
    int index, ImageProvider provider, BoxFit fit);

/// Route-local cover position and a bounded snapshot of already painted pixels.
/// Historical name retained; there is no Hero overlay or second image decode.
class CoverHero extends StatefulWidget {
  const CoverHero(
      {super.key,
      required this.tag,
      required this.identity,
      required this.builder});
  final String tag;
  final Object? identity;
  final Widget Function(CoverImageReporter report) builder;
  @override
  State<CoverHero> createState() => CoverHeroState();
}

class CoverHeroState extends State<CoverHero> {
  final _surface = GlobalKey();

  CoverOrigin get origin {
    final tag = widget.tag;
    final identity = widget.identity;
    final navigator = Navigator.of(context);
    Rect? resolve() {
      if (!mounted ||
          widget.tag != tag ||
          widget.identity != identity ||
          !navigator.mounted) {
        return null;
      }
      final surface = _surface.currentContext?.findRenderObject();
      final viewport = navigator.context.findRenderObject();
      if (surface is! RenderBox ||
          viewport is! RenderBox ||
          !surface.attached ||
          !surface.hasSize ||
          !viewport.attached ||
          !viewport.hasSize) {
        return null;
      }
      final rect = MatrixUtils.transformRect(
          surface.getTransformTo(viewport), Offset.zero & surface.size);
      final bounds = Offset.zero & viewport.size;
      if (!rect.isFinite || rect.isEmpty || !rect.overlaps(bounds)) {
        return null;
      }
      final scrollport = RenderAbstractViewport.maybeOf(surface);
      if (scrollport is RenderBox) {
        final box = scrollport as RenderBox;
        final visible = MatrixUtils.transformRect(
            box.getTransformTo(viewport), Offset.zero & box.size);
        if (!rect.overlaps(visible)) {
          return null;
        }
      }
      return rect;
    }

    return CoverOrigin(
        resolveRect: resolve,
        radius: AppTheme.cornerRadius,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        captureImage: () {
          if (resolve() == null) return null;
          final boundary = _surface.currentContext?.findRenderObject();
          if (boundary is! RenderRepaintBoundary) return null;
          var needsPaint = false;
          assert(() {
            needsPaint = boundary.debugNeedsPaint;
            return true;
          }());
          if (needsPaint) return null;
          try {
            final ratio = math.min(
                MediaQuery.devicePixelRatioOf(context),
                AppConstants.coverSnapshotMaxExtent /
                    math.max(boundary.size.width, boundary.size.height));
            return boundary.toImageSync(pixelRatio: ratio);
          } catch (_) {
            return null;
          } // Not painted or raster context unavailable.
        });
  }

  // Legacy builder callback: the raster snapshot replaces provider registries.
  void report(int index, ImageProvider provider, BoxFit fit) {}

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: _surface, child: widget.builder(report));
}

/// Existing cached four-tile folder cover.
class FolderCoverPreview extends StatelessWidget {
  const FolderCoverPreview(
      {super.key, required this.paths, this.onImageProvider});
  final List<String> paths;
  final void Function(int, ImageProvider)? onImageProvider;
  @override
  Widget build(BuildContext context) => paths.isEmpty
      ? const Center(child: Icon(Icons.folder_open, color: Colors.grey))
      : _FourTiles(
          tile: (i) => i < paths.length
              ? PageThumbnail(
                  path: paths[i],
                  fit: BoxFit.cover,
                  cacheWidth: AppConfig.microThumbnailCacheWidth,
                  borderRadius: BorderRadius.zero,
                  preserveAnimation: true,
                  deferGenerationUntilReady: true,
                  onImageProvider: (provider) =>
                      onImageProvider?.call(i, provider))
              : const ColoredBox(color: Color(0xffdddddd)));
}

class _FourTiles extends StatelessWidget {
  const _FourTiles({required this.tile});
  final Widget Function(int) tile;
  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
            child: Row(children: [
          Expanded(child: tile(0)),
          const SizedBox(width: 1),
          Expanded(child: tile(1))
        ])),
        const SizedBox(height: 1),
        Expanded(
            child: Row(children: [
          Expanded(child: tile(2)),
          const SizedBox(width: 1),
          Expanded(child: tile(3))
        ])),
      ]);
}
