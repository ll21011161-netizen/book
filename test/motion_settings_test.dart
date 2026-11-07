import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gun_book/core/motion.dart';
import 'package:gun_book/core/settings_provider.dart';
import 'package:gun_book/core/anim_route.dart';
import 'package:gun_book/widgets/motion_settings_panel.dart';
import 'package:gun_book/widgets/retained_motion_tabs.dart';
import 'package:gun_book/widgets/spring_press.dart';

void main() {
  Future<SettingsProvider> load() async {
    final settings = SettingsProvider();
    while (!settings.isLoaded) {
      await Future<void>.value();
    }
    return settings;
  }

  test('old, corrupt and unknown preferences recover safely', () async {
    for (final raw in [
      null,
      'bad json',
      123,
      jsonEncode({
        'curve': 'future',
        'page': 2,
        'press': null,
        'milliseconds': 999,
        'bounce': 'yes'
      })
    ]) {
      SharedPreferences.setMockInitialValues(
          {if (raw != null) 'motion_v1': raw});
      final settings = await load();
      expect(settings.motion, const MotionSettings());
      settings.dispose();
    }
  });
  test(
      'all preferences round trip; latest write/reset wins; other values survive',
      () async {
    SharedPreferences.setMockInitialValues({'shelf_columns': 5, 'read_rtl': 1});
    final settings = await load();
    for (final curve in MotionCurve.values) {
      for (final page in PageMotion.values) {
        final value = MotionSettings(
            curve: curve,
            page: page,
            press: PressMotion.spring,
            bounce: true,
            milliseconds: 570);
        settings.setMotion(value);
        await settings.flushMotionSettings();
        final restored = await load();
        expect(restored.motion, value);
        expect(restored.bookshelfColumns, 5);
        expect(restored.rtlMode, isTrue);
        restored.dispose();
      }
    }
    for (var i = 100; i <= 600; i += 10) {
      settings.setMotion(settings.motion.copyWith(milliseconds: i));
    }
    settings.resetMotion();
    await settings.flushMotionSettings();
    final restored = await load();
    expect(restored.motion, const MotionSettings());
    restored.dispose();
    settings.dispose();
  });
  test('editing before async restore wins and disposal during load is safe',
      () async {
    SharedPreferences.setMockInitialValues({
      'motion_v1': jsonEncode({'milliseconds': 600})
    });
    final settings = SettingsProvider();
    settings.setMotion(const MotionSettings(milliseconds: 150));
    await settings.flushMotionSettings();
    expect(settings.motion.milliseconds, 150);
    settings.dispose();
    SettingsProvider().dispose();
    await Future<void>.delayed(Duration.zero);
  });
  testWidgets('legacy effects are inert and scrolling always clamps',
      (tester) async {
    const legacy = MotionSettings(
        page: PageMotion.slide,
        detail: DetailMotion.followPage,
        press: PressMotion.spring,
        curve: MotionCurve.spring,
        bounce: true,
        milliseconds: 600);
    late MotionSettings active;
    await tester.pumpWidget(MaterialApp(
        home: MotionScope(
            settings: legacy,
            child: Builder(builder: (context) {
              active = MotionScope.of(context);
              return const SizedBox();
            }))));
    expect(active, const MotionSettings());
    expect(active.scrollPhysics, isA<ClampingScrollPhysics>());
    expect(legacy.scrollPhysics, isA<ClampingScrollPhysics>());
    expect(MotionSettings.fromJson(legacy.toJson()), legacy);
  });
  test('spring is damped and has bounded single visible overshoot', () {
    final samples = [
      for (var i = 0; i <= 1000; i++) const GentleSpring().transform(i / 1000)
    ];
    expect(samples.first, 0);
    expect(samples.last, 1);
    expect(samples.reduce((a, b) => a > b ? a : b), inExclusiveRange(1, 1.11));
    expect(samples.every((v) => v >= 0), isTrue);
  });
  for (final page in PageMotion.values) {
    for (final curve in MotionCurve.values) {
      testWidgets('$page $curve renders and returns mid transition safely',
          (tester) async {
        final motion =
            MotionSettings(page: page, curve: curve, milliseconds: 150);
        final nav = GlobalKey<NavigatorState>();
        late BuildContext home;
        await tester.pumpWidget(MaterialApp(
            navigatorKey: nav,
            builder: (_, child) => MotionScope(settings: motion, child: child!),
            home: Builder(builder: (context) {
              home = context;
              return const Text('home');
            })));
        final route = DetailRoute<void>(
            context: home, page: const Scaffold(body: Text('detail')));
        nav.currentState!.push(route);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        for (final fade
            in tester.widgetList<FadeTransition>(find.byType(FadeTransition))) {
          expect(fade.opacity.value, inInclusiveRange(0, 1));
        }
        expect(route.transitionDuration, Duration.zero);
        nav.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.text('home'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final disabled in [false, true]) {
    testWidgets('system reduce motion overrides settings=$disabled',
        (tester) async {
      late BuildContext home;
      await tester.pumpWidget(MaterialApp(
          home: MotionScope(
              settings: MotionSettings(enabled: !disabled),
              child: MediaQuery(
                  data: const MediaQueryData(disableAnimations: true),
                  child: Builder(builder: (context) {
                    home = context;
                    return const SizedBox();
                  })))));
      expect(MotionScope.of(home).enabled, isFalse);
      expect(
          DetailRoute<void>(context: home, page: const SizedBox())
              .transitionDuration,
          Duration.zero);
    });
  }
  for (final page in PageMotion.values.where((p) => p != PageMotion.none)) {
    testWidgets('predictive back cancels/commits with $page and spring',
        (tester) async {
      final nav = GlobalKey<NavigatorState>();
      late BuildContext home;
      await tester.pumpWidget(MaterialApp(
          navigatorKey: nav,
          theme: ThemeData(platform: TargetPlatform.android),
          builder: (_, child) => MotionScope(
              settings: MotionSettings(page: page, curve: MotionCurve.spring),
              child: child!),
          home: Builder(builder: (context) {
            home = context;
            return const Text('home');
          })));
      final route =
          DetailRoute<void>(context: home, page: const Text('detail'));
      nav.currentState!.push(route);
      await tester.pumpAndSettle();
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
      await event('updateBackGestureProgress', .45);
      await tester.pump();
      expect(route.animation!.value, closeTo(.55, .001));
      await event('cancelBackGesture');
      await tester.pumpAndSettle();
      expect(route.isCurrent, isTrue);
      expect(route.animation!.value, 1);
      expect(await event('startBackGesture', 0), isTrue);
      await tester.pump();
      await event('updateBackGestureProgress', .7);
      await tester.pump();
      await event('commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(find.text('detail'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('both tab scroll offsets survive rapid switching',
      (tester) async {
    final index = ValueNotifier(0);
    final scrolls = [ScrollController(), ScrollController()];
    final pages = [
      for (var i = 0; i < 2; i++)
        ListView(
            controller: scrolls[i], children: const [SizedBox(height: 2500)])
    ];
    await tester.pumpWidget(MaterialApp(
        home: ValueListenableBuilder<int>(
            valueListenable: index,
            builder: (_, i, child) =>
                RetainedMotionTabs(index: i, children: pages))));
    scrolls[0].jumpTo(320);
    scrolls[1].jumpTo(510);
    for (var i = 0; i < 30; i++) {
      index.value = i % 2;
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(scrolls[0].offset, 320);
    expect(scrolls[1].offset, 510);
    await tester.pumpWidget(const SizedBox());
    for (final s in scrolls) {
      s.dispose();
    }
    index.dispose();
    expect(tester.takeException(), isNull);
  });
  testWidgets('only cover switch remains and saves safely', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await load();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: settings,
        child: const MaterialApp(home: Scaffold(body: MotionSettingsPanel()))));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(SwitchListTile), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await settings.flushMotionSettings();
    final restored = await load();
    expect(restored.motion.enabled, isFalse);
    restored.dispose();
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
  for (final press in PressMotion.values) {
    testWidgets('press $press obeys selection and releases at rest',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
          home: MotionScope(
              settings: MotionSettings(press: press),
              child: Center(
                  child: SpringPress(
                      onTap: () => taps++,
                      child: const SizedBox(width: 100, height: 100))))));
      final hold =
          await tester.startGesture(tester.getCenter(find.byType(SpringPress)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(AnimatedScale), findsNothing);
      await hold.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(find.byType(AnimatedScale), findsNothing);
    });
  }
}
