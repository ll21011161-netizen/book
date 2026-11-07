import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/data/reader_image.dart';
import 'support/test_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('missing, empty and corrupt pages fail without blocking the next decode',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('gunbook-reader-errors-');
    try {
      final files = [
        File('${directory.path}/missing.png'),
        await File('${directory.path}/empty.png').writeAsBytes([]),
        await File('${directory.path}/corrupt.png').writeAsBytes([1, 2, 3, 4]),
      ];
      for (final file in files) {
        final provider = ReaderFileImage(file);
        final stream = provider.resolve(ImageConfiguration.empty);
        final result = Completer<void>();
        final listener = ImageStreamListener((info, _) {
          info.dispose();
          if (!result.isCompleted) result.complete();
        }, onError: (Object error, StackTrace? stack) {
          if (!result.isCompleted) result.completeError(error, stack);
        });
        final failure = expectLater(result.future, throwsA(anything));
        stream.addListener(listener);
        await failure;
        stream.removeListener(listener);
        await provider.evict();
      }
      final good = await writeTestImage('${directory.path}/valid.png',
          width: 40, height: 60);
      final provider = ReaderFileImage(good);
      final stream = provider.resolve(ImageConfiguration.empty);
      final ready = Completer<void>();
      final listener = ImageStreamListener((info, _) {
        expect(info.image.width, 40);
        info.dispose();
        if (!ready.isCompleted) ready.complete();
      }, onError: ready.completeError);
      stream.addListener(listener);
      await ready.future;
      stream.removeListener(listener);
      await provider.evict();
    } finally {
      await directory.delete(recursive: true);
    }
  });
  test('high resolution reader pages retain all original pixels', () async {
    final directory =
        await Directory.systemTemp.createTemp('gunbook-reader-full-');
    final file = await writeTestImage('${directory.path}/large.png',
        width: 2048, height: 3072);
    final provider = ReaderFileImage(file);
    final stream = provider.resolve(ImageConfiguration.empty);
    final ready = Completer<Size>();
    final listener = ImageStreamListener((info, synchronous) {
      if (!ready.isCompleted) {
        ready.complete(
            Size(info.image.width.toDouble(), info.image.height.toDouble()));
      }
      info.dispose();
    }, onError: ready.completeError);
    stream.addListener(listener);
    try {
      expect(await ready.future, const Size(2048, 3072));
    } finally {
      stream.removeListener(listener);
      await provider.evict();
      await directory.delete(recursive: true);
    }
  });
  test(
      'reader decodes the complete original dimensions and reuses its cache key',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('gunbook-image-test-');
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff123456), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final original = await picture.toImage(321, 654);
    final png = await original.toByteData(format: ui.ImageByteFormat.png);
    final file = await File('${directory.path}/page.png')
        .writeAsBytes(png!.buffer.asUint8List());
    original.dispose();
    picture.dispose();
    final provider = ReaderFileImage(file);
    expect(provider, ReaderFileImage(File(file.path)));
    final stream = provider.resolve(ImageConfiguration.empty);
    final done = Completer<void>();
    final listener = ImageStreamListener((info, synchronous) {
      try {
        expect(info.image.width, 321);
        expect(info.image.height, 654);
        done.complete();
      } catch (error, stack) {
        done.completeError(error, stack);
      } finally {
        info.dispose();
      }
    }, onError: done.completeError);
    stream.addListener(listener);
    await done.future;
    stream.removeListener(listener);
    await provider.evict();
    await directory.delete(recursive: true);
  });
}
