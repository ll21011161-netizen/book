import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/data/thumbnail_cache.dart';
import '../test/support/test_image.dart';

Future<void> decode(String source) async {
  final codec = await ui.instantiateImageCodecFromBuffer(
      await ui.ImmutableBuffer.fromFilePath(source),
      targetWidth: 150,
      allowUpscaling: false);
  try {
    final frame = await codec.getNextFrame();
    frame.image.dispose();
  } finally {
    codec.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('12 original covers vs first generation and fresh-instance disk hits',
      () async {
    final root = await Directory.systemTemp.createTemp('gunbook-covers-');
    try {
      final sources = <String>[];
      for (var i = 0; i < 12; i++) {
        sources.add((await writeTestImage('${root.path}/page$i.png',
                width: 2048, height: 3072))
            .path);
      }
      for (var run = 0; run < 5; run++) {
        for (final mode in run.isEven
            ? ['original', 'cold', 'disk', 'deferred']
            : ['cold', 'disk', 'original', 'deferred']) {
          var directoryCalls = 0;
          final cache = ThumbnailCache(directory: () async {
            directoryCalls++;
            return Directory(
                '${root.path}/${mode == 'deferred' ? 'miss' : 'cache'}$run');
          });
          final watch = Stopwatch()..start();
          final targets = mode == 'original'
              ? sources
              : mode == 'deferred'
                  ? await Future.wait(sources.map(
                      (path) async => await cache.getExisting(path) ?? path))
                  : (await Future.wait(sources.map(cache.get))).cast<String>();
          await Future.wait(targets.map(decode));
          watch.stop();
          // ignore: avoid_print
          print(
              'GUNBOOK_COVER_BENCH run=$run mode=$mode count=12 elapsed_us=${watch.elapsedMicroseconds} directory_calls=$directoryCalls rss_bytes=${ProcessInfo.currentRss}');
          if (mode == 'deferred') await Future.wait(sources.map(cache.get));
          await cache.trim();
        }
      }
    } finally {
      await root.delete(recursive: true);
    }
  });
}
