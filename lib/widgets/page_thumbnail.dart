import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../data/thumbnail_cache.dart';
import 'app_image.dart';

/// By default, resolve a disk thumbnail before displaying it. Covers can show
/// the original on a miss and warm this same cache after their first frame.
class PageThumbnail extends StatefulWidget {
  const PageThumbnail(
      {super.key,
      required this.path,
      this.onImageReady,
      this.onImageProvider,
      this.cache,
      this.fit = BoxFit.cover,
      this.cacheWidth = 150,
      this.borderRadius = const BorderRadius.all(Radius.circular(12)),
      this.preserveAnimation = false,
      this.deferGenerationUntilReady = false,
      this.generationEnabled = true,
      this.previewOnMiss = false,
      this.priority = 0});
  final String path;
  final VoidCallback? onImageReady;
  final ValueChanged<ImageProvider>? onImageProvider;
  final ThumbnailCache? cache;
  final BoxFit fit;
  final int cacheWidth;
  final BorderRadius borderRadius;
  // PNG thumbnails contain one frame. Keep potentially animated covers on
  // their original provider; static WebP is conservatively included here.
  final bool preserveAnimation;
  final bool deferGenerationUntilReady;
  // Cache hits remain available even while generation is gated. Detail pages
  // enable a bounded first row early, then release the rest after the fade.
  final bool generationEnabled;
  final bool previewOnMiss;
  final int priority;
  @override
  State<PageThumbnail> createState() => _PageThumbnailState();
}

class _PageThumbnailState extends State<PageThumbnail> {
  ThumbnailCache get _cache => widget.cache ?? ThumbnailCache.instance;
  String? _resolved;
  int _generation = 0;
  bool _reported = false;
  bool _needsWarmup = false;

  @override
  void initState() {
    super.initState();
    _cache.retain(widget.path);
    _load();
  }

  @override
  void didUpdateWidget(covariant PageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.cache != widget.cache ||
        oldWidget.preserveAnimation != widget.preserveAnimation ||
        oldWidget.deferGenerationUntilReady !=
            widget.deferGenerationUntilReady) {
      (oldWidget.cache ?? ThumbnailCache.instance).release(oldWidget.path);
      _cache.retain(widget.path);
      _resolved = null;
      _reported = false;
      _needsWarmup = false;
      _load();
    } else if (!oldWidget.generationEnabled && widget.generationEnabled) {
      if (_resolved == null) {
        _load();
      } else if (_needsWarmup && _reported) {
        _needsWarmup = false;
        unawaited(_warmup());
      }
    }
  }

  // Evaluate against the viewport at dequeue time. Sliver cache items stay
  // lower priority; disposed requests are skipped entirely.
  int _priority() {
    if (!mounted) return 2;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return 2;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final viewport = Offset.zero & MediaQuery.sizeOf(context);
    if (rect.overlaps(viewport)) return widget.priority;
    return (rect.overlaps(viewport.inflate(box.size.height)) ? 2 : 3) +
        widget.priority;
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final source = widget.path;
    if (widget.preserveAnimation &&
        const {'.gif', '.webp'}.contains(p.extension(source).toLowerCase())) {
      _resolved = source;
      return;
    }
    final preview = widget.deferGenerationUntilReady || widget.previewOnMiss;
    if (!preview && widget.generationEnabled) {
      final result = await _cache.get(source,
          isNeeded: () =>
              mounted && generation == _generation && widget.generationEnabled,
          priority: _priority);
      if (mounted && generation == _generation && widget.generationEnabled) {
        setState(() => _resolved = result ?? source);
      }
      return;
    }
    final cached = await _cache.getExisting(source);
    if (!mounted || generation != _generation) return;
    if (cached != null) {
      setState(() => _resolved = cached);
      return;
    }
    if (preview) {
      setState(() {
        _needsWarmup = true;
        _resolved = source;
      });
    } else if (widget.generationEnabled) {
      final result = await _cache.get(source,
          isNeeded: () =>
              mounted && generation == _generation && widget.generationEnabled,
          priority: _priority);
      if (mounted && generation == _generation && widget.generationEnabled) {
        setState(() => _resolved = result ?? source);
      }
    }
  }

  Future<void> _warmup() async {
    final generation = _generation;
    final source = widget.path;
    final cache = _cache;
    // AppImage calls us after its first rendered frame. Yield out of that
    // callback; waiting for another endOfFrame can stall on an idle shelf.
    await Future<void>.delayed(Duration.zero);
    if (!mounted || generation != _generation) return;
    await cache.get(source,
        isNeeded: () =>
            mounted && generation == _generation && widget.generationEnabled,
        // Visible detail thumbnails take precedence over cover maintenance.
        priority: () =>
            _priority() + (widget.deferGenerationUntilReady ? 1 : 0));
    // Keep the displayed original. Swapping here would cause another decode
    // and could change an image during a Hero transition; use it next visit.
  }

  Future<void> _fallback() async {
    final cached = _resolved;
    if (cached == null || cached == widget.path) return;
    final source = widget.path;
    final cache = _cache;
    setState(() => _resolved = source);
    try {
      await cache.invalidate(source, cached);
    } catch (_) {/* retry next visit */}
  }

  @override
  void dispose() {
    _generation++;
    _cache.release(widget.path);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_resolved == null) {
      if (widget.deferGenerationUntilReady) return const SizedBox.expand();
      return DecoratedBox(
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: widget.borderRadius));
    }
    return AppImage(
      path: _resolved,
      onImageProvider: widget.onImageProvider,
      onImageReady: () {
        if (_needsWarmup && widget.generationEnabled) {
          _needsWarmup = false;
          unawaited(_warmup());
        }
        if (_reported) return;
        _reported = true;
        widget.onImageReady?.call();
      },
      onImageError: () => unawaited(_fallback()),
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      borderRadius: widget.borderRadius,
    );
  }
}
