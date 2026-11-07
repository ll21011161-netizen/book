import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/core/anim_route.dart';
import 'package:gun_book/widgets/page_thumbnail.dart';
import 'package:gun_book/widgets/app_image.dart';
import 'package:gun_book/data/thumbnail_cache.dart';

class GateCache extends ThumbnailCache {
  int generated = 0;
  bool hit = false;
  @override
  Future<String?> getExisting(String path) async => hit ? 'cached.png' : null;
  @override
  Future<String?> get(String path,
      {bool Function()? isNeeded, int Function()? priority}) async {
    if (isNeeded?.call() ?? true) generated++;
    return 'cached.png';
  }
}

void main() {
  testWidgets(
      'detail route uses 250/200ms, and predictive back cancels and commits',
      (tester) async {
    final nav = GlobalKey<NavigatorState>();
    late BuildContext home;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        theme: ThemeData(platform: TargetPlatform.android),
        home: Builder(builder: (context) {
          home = context;
          return const Scaffold(body: Text('Home'));
        })));
    final route = DetailRoute<void>(
        context: home, page: const Scaffold(body: Text('Detail')));
    nav.currentState!.push(route);
    await tester.pumpAndSettle();
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    Future<dynamic> event(String name, [double? progress]) async {
      final result = Completer<dynamic>();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.backGesture.name,
          SystemChannels.backGesture.codec.encodeMethodCall(MethodCall(
              name,
              progress == null
                  ? null
                  : {
                      'progress': progress,
                      'touchOffset': [8.0, 250.0],
                      'swipeEdge': 0
                    })),
          (reply) => result.complete(
              SystemChannels.backGesture.codec.decodeEnvelope(reply!)));
      return result.future;
    }

    expect(await event('startBackGesture', 0), isTrue);
    await tester.pump();
    await event('updateBackGestureProgress', .35);
    await tester.pump();
    expect(route.popGestureInProgress, isTrue);
    expect(route.animation!.value, closeTo(.65, .001));
    expect(
        find.ancestor(
            of: find.text('Detail'), matching: find.byType(FadeTransition)),
        findsNothing);
    await event('cancelBackGesture');
    await tester.pumpAndSettle();
    expect(route.isCurrent, isTrue);
    expect(route.animation!.value, 1);
    expect(await event('startBackGesture', 0), isTrue);
    await tester.pump();
    await event('updateBackGestureProgress', .7);
    await tester.pump();
    await event('commitBackGesture');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('ten detail returns retain the source scroll position',
      (tester) async {
    final controller = ScrollController();
    final nav = GlobalKey<NavigatorState>();
    late BuildContext home;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: Builder(builder: (context) {
          home = context;
          return ListView(
              controller: controller, children: const [SizedBox(height: 2000)]);
        })));
    controller.jumpTo(180);
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      nav.currentState!.push(DetailRoute<void>(
          context: home, page: const Scaffold(body: Text('Detail'))));
      await tester.pumpAndSettle();
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(controller.offset, 180);
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion has zero detail route durations', (tester) async {
    late BuildContext home;
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(builder: (context) {
              home = context;
              return const SizedBox();
            }))));
    final route = DetailRoute<void>(context: home, page: const SizedBox());
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
  });
  testWidgets(
      'cache hits bypass transition gate; misses wait; first-row preview stays stable',
      (tester) async {
    final cache = GateCache();
    Widget app(bool enabled, {bool preview = false}) => MaterialApp(
        home: PageThumbnail(
            path: 'source.png',
            cache: cache,
            generationEnabled: enabled,
            previewOnMiss: preview,
            cacheWidth: 120));
    await tester.pumpWidget(app(false));
    await tester.pump();
    expect(find.byType(AppImage), findsNothing);
    expect(cache.generated, 0);
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(cache.generated, 1);
    await tester.pumpWidget(const SizedBox());
    cache.hit = true;
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(tester.widget<AppImage>(find.byType(AppImage)).path, 'cached.png');
    await tester.pumpWidget(const SizedBox());
    cache.hit = false;
    cache.generated = 0;
    await tester.pumpWidget(app(false, preview: true));
    await tester.pump();
    final image = tester.widget<AppImage>(find.byType(AppImage));
    expect(image.path, 'source.png');
    expect(image.cacheWidth, 120);
    image.onImageReady!();
    await tester.pump(const Duration(milliseconds: 1));
    expect(cache.generated, 0);
    await tester.pumpWidget(app(true, preview: true));
    await tester.pump(const Duration(milliseconds: 1));
    expect(cache.generated, 1);
    expect(tester.widget<AppImage>(find.byType(AppImage)).path, 'source.png');
    expect(tester.takeException(), isNull);
  });
}
