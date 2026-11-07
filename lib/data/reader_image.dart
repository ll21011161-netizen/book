import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import '../core/perf_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Limits actual codec creation AND first-frame decoding, not merely precache
/// requests. Includes subsequent frames of animated images in the same queue.
class SerialImageWork {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace stack) {});
    return result;
  }
}

class ReaderFileImage extends FileImage {
  const ReaderFileImage(super.file);
  static final work = SerialImageWork();

  @override
  ImageStreamCompleter loadImage(FileImage key, ImageDecoderCallback decode) {
    final queued = Stopwatch()..start();
    final codec = work.run<ui.Codec>(() async {
      final waitUs = queued.elapsedMicroseconds;
      final watch = Stopwatch()..start();
      try {
        if (await key.file.length() == 0) {
          throw FileSystemException('圖片是空檔案', key.file.path);
        }
        // No targetWidth/cacheWidth: preserve the full original resolution.
        final source =
            await decode(await ui.ImmutableBuffer.fromFilePath(key.file.path));
        try {
          final first = await source.getNextFrame();
          PerfLog.event('reader_decode', {
            'queue_us': waitUs,
            'decode_us': watch.elapsedMicroseconds,
            'width': first.image.width,
            'height': first.image.height,
            ...PerfLog.memory()
          });
          return _FirstFrameCodec(source, first);
        } catch (_) {
          source.dispose();
          rethrow;
        }
      } catch (_) {
        scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
        rethrow;
      }
    });
    return MultiFrameImageStreamCompleter(
        codec: codec, scale: key.scale, debugLabel: key.file.path);
  }
}

class _FirstFrameCodec implements ui.Codec {
  _FirstFrameCodec(this.source, this.first);
  final ui.Codec source;
  ui.FrameInfo? first;
  bool disposed = false;
  @override
  int get frameCount => source.frameCount;
  @override
  int get repetitionCount => source.repetitionCount;
  @override
  Future<ui.FrameInfo> getNextFrame() {
    if (disposed) return Future.error(StateError('Codec disposed'));
    final frame = first;
    if (frame != null) {
      first = null;
      return SynchronousFuture(frame);
    }
    return ReaderFileImage.work.run(() async {
      if (disposed) throw StateError('Codec disposed');
      return source.getNextFrame();
    });
  }

  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    first?.image.dispose();
    first = null;
    source.dispose();
  }
}
