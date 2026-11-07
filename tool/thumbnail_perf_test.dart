import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/data/thumbnail_cache.dart';
import '../test/support/test_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bounded thumbnail workers: cold generation and warm disk hits',
      () async {
    final root = await Directory.systemTemp.createTemp('gunbook-thumb-bench-');
    try {
      final sources = <String>[];
      for (var i = 0; i < 24; i++) {
        final file = await writeTestImage('${root.path}/page$i.png',
            width: 2048, height: 3072);
        sources.add(file.path);
      }
      for (var run = 0; run < 3; run++) {
        // Alternate worker order to reduce ordering bias.
        for (final workers in run.isEven ? [1, 2] : [2, 1]) {
          final cache = ThumbnailCache(
              directory: () async =>
                  Directory('${root.path}/cache-$workers-$run'),
              maxConcurrent: workers);
          final cold = Stopwatch()..start();
          final paths = await Future.wait(sources.map(cache.get));
          expect(paths.every((path) => path != null), isTrue);
          cold.stop();
          final warm = Stopwatch()..start();
          await Future.wait(sources.map(cache.get));
          warm.stop();
          // This is an end-of-run RSS sample, not a peak measurement.
          // ignore: avoid_print
          print(
              'GUNBOOK_THUMB_BENCH run=$run workers=$workers count=24 cold_us=${cold.elapsedMicroseconds} warm_us=${warm.elapsedMicroseconds} rss_bytes=${ProcessInfo.currentRss}');
          await cache.trim();
        }
      }
    } finally {
      await root.delete(recursive: true);
    }
  });
}
