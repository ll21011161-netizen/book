import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/widgets/app_image.dart';
import 'package:gun_book/widgets/page_thumbnail.dart';
import 'package:gun_book/data/thumbnail_cache.dart';
import 'support/test_image.dart';

class _ControlledCoverCache extends ThumbnailCache {
  int warmups = 0;
  @override
  Future<String?> getExisting(String source) async => null;
  @override
  Future<String?> get(String source,
      {bool Function()? isNeeded, int Function()? priority}) async {
    if (isNeeded?.call() ?? true) warmups++;
    return 'generated.png';
  }
}

void main() {
  testWidgets(
      'cold covers render originals before warming and never swap the visible image',
      (tester) async {
    final cache = _ControlledCoverCache();
    await tester.pumpWidget(MaterialApp(
        home: PageThumbnail(
      path: 'original.png',
      cache: cache,
      deferGenerationUntilReady: true,
    )));
    await tester.pump();
    final image = tester.widget<AppImage>(find.byType(AppImage));
    expect(image.path, 'original.png');
    expect(cache.warmups, 0);
    image.onImageReady!();
    await tester.pump(const Duration(milliseconds: 1));
    expect(cache.warmups, 1);
    expect(tester.widget<AppImage>(find.byType(AppImage)).path, 'original.png');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disposed cold covers abandon warming before it starts',
      (tester) async {
    final cache = _ControlledCoverCache();
    await tester.pumpWidget(MaterialApp(
        home: PageThumbnail(
      path: 'original.png',
      cache: cache,
      deferGenerationUntilReady: true,
    )));
    await tester.pump();
    tester.widget<AppImage>(find.byType(AppImage)).onImageReady!();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    expect(cache.warmups, 0);
  });
  testWidgets('cover options retain sampling, crop and animated originals',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('gunbook-cover-options-');
    final source = '${root.path}/cover.png';
    final cache =
        ThumbnailCache(directory: () async => Directory('${root.path}/cache'));
    await tester.runAsync(() async {
      await writeTestImage(source);
      await cache.get(source);
    });
    await tester.pumpWidget(MaterialApp(
        home: PageThumbnail(
      path: source,
      cache: cache,
      fit: BoxFit.contain,
      cacheWidth: 80,
      borderRadius: BorderRadius.zero,
      preserveAnimation: true,
    )));
    for (var i = 0; i < 50 && find.byType(AppImage).evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    final image = tester.widget<AppImage>(find.byType(AppImage));
    expect(image.path, isNot(source));
    expect(image.fit, BoxFit.contain);
    expect(image.cacheWidth, 80);
    expect(image.borderRadius, BorderRadius.zero);
    for (final extension in ['GIF', 'webp']) {
      final animated = '${root.path}/animated.$extension';
      await tester.pumpWidget(MaterialApp(
          home: PageThumbnail(
        path: animated,
        cache: cache,
        preserveAnimation: true,
      )));
      expect(tester.widget<AppImage>(find.byType(AppImage)).path, animated);
    }
    await tester.pumpWidget(const SizedBox());
    PaintingBinding.instance.imageCache.clear();
    await tester.runAsync(() async {
      await cache.trim();
      await root.delete(recursive: true);
    });
  });
  testWidgets(
      'ready reports once, handles synchronous hits, resets on path change and ignores stale callbacks',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('gunbook-widget-');
    final path = '${root.path}/one.png';
    final other = '${root.path}/two.png';
    await tester.runAsync(() async {
      await writeTestImage(path);
      await writeTestImage(other);
    });
    var calls = 0;
    Widget host(String source, {Key? key}) => Directionality(
        textDirection: TextDirection.ltr,
        child: AppImage(key: key, path: source, onImageReady: () => calls++));
    await tester.pumpWidget(host(path));
    // Exercise frameBuilder deterministically, including animated/rebuild calls.
    var image = tester.widget<Image>(find.byType(Image));
    image.frameBuilder!(
        tester.element(find.byType(Image)), const SizedBox(), 0, false);
    image.frameBuilder!(
        tester.element(find.byType(Image)), const SizedBox(), 1, false);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(calls, 1);
    await tester.pumpWidget(host(path));
    image = tester.widget<Image>(find.byType(Image));
    image.frameBuilder!(
        tester.element(find.byType(Image)), const SizedBox(), 0, true);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(calls, 1);
    await tester.pumpWidget(host(other));
    image = tester.widget<Image>(find.byType(Image));
    image.frameBuilder!(
        tester.element(find.byType(Image)), const SizedBox(), 0, true);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(calls, 2);
    await tester.pumpWidget(host(path, key: const ValueKey('fresh')));
    image = tester.widget<Image>(find.byType(Image));
    image.frameBuilder!(
        tester.element(find.byType(Image)), const SizedBox(), 0, true);
    await tester.pumpWidget(const SizedBox());
    expect(calls, 2);
    PaintingBinding.instance.imageCache.clear();
    await tester.runAsync(() => root.delete(recursive: true));
  });

  testWidgets(
      'page thumbnail waits for cache and never displays original on success',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('gunbook-page-widget-');
    final source = '${root.path}/page.png';
    final cache =
        ThumbnailCache(directory: () async => Directory('${root.path}/cache'));
    await tester.runAsync(() async {
      await writeTestImage(source);
      await cache.get(source);
    });
    await tester.pumpWidget(
        MaterialApp(home: PageThumbnail(path: source, cache: cache)));
    expect(find.byType(AppImage), findsNothing);
    for (var i = 0; i < 30 && find.byType(AppImage).evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(find.byType(AppImage), findsOneWidget);
    expect(tester.widget<AppImage>(find.byType(AppImage)).path, isNot(source));
    await tester.pumpWidget(const SizedBox());
    PaintingBinding.instance.imageCache.clear();
    await tester.runAsync(() => root.delete(recursive: true));
  });

  testWidgets(
      'missing and corrupt originals display an error without unhandled exceptions',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('gunbook-broken-widget-');
    final bad = File('${root.path}/bad.png')..writeAsBytesSync([1, 2, 3]);
    final cache =
        ThumbnailCache(directory: () async => Directory('${root.path}/cache'));
    for (final source in ['${root.path}/missing.png', bad.path]) {
      await tester.pumpWidget(MaterialApp(
          home: PageThumbnail(
              key: ValueKey(source), path: source, cache: cache)));
      for (var i = 0;
          i < 30 && find.byIcon(Icons.broken_image).evaluate().isEmpty;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(find.byIcon(Icons.broken_image), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.runAsync(() async {
      await cache.trim();
      await root.delete(recursive: true);
    });
  });
}
