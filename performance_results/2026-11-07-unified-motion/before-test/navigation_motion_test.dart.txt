import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/main.dart';
import 'package:gun_book/widgets/retained_motion_tabs.dart';

void main() {
  late BuildContext scrollContext;
  Widget app({bool reduced = false}) => MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!),
        home: MainScreen(pages: [
          Builder(builder: (context) {
            scrollContext = context;
            return SafeArea(
                child: ListView(children: const [SizedBox(height: 2000)]));
          }),
          const ColoredBox(color: Colors.blue),
        ]),
      );
  void scroll(double delta, {bool drag = true, double pixels = 100}) {
    ScrollUpdateNotification(
      metrics: FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 2000,
          pixels: pixels,
          viewportDimension: 600,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 1),
      context: scrollContext,
      scrollDelta: delta,
      dragDetails: drag ? DragUpdateDetails(globalPosition: Offset.zero) : null,
    ).dispatch(scrollContext);
  }

  testWidgets(
      'navigation ignores jitter and momentum; hiding preserves viewport',
      (tester) async {
    await tester.pumpWidget(app());
    final initialSize = tester.getSize(find.byType(RetainedMotionTabs));
    expect(initialSize.height,
        tester.view.physicalSize.height / tester.view.devicePixelRatio);
    expect(tester.getBottomRight(find.byType(ListView)).dy,
        tester.view.physicalSize.height / tester.view.devicePixelRatio);
    scroll(3);
    await tester.pump();
    expect(tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
        Offset.zero);
    scroll(21);
    await tester.pump();
    expect(
        tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset.dy, 1);
    expect(
        tester
            .widget<IgnorePointer>(find
                .ancestor(
                    of: find.byType(NavigationBar),
                    matching: find.byType(IgnorePointer))
                .first)
            .ignoring,
        isTrue);
    scroll(-3);
    await tester.pump();
    expect(
        tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset.dy, 1);
    scroll(-100, drag: false);
    await tester.pump();
    expect(
        tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset.dy, 1);
    scroll(-9);
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
        Offset.zero);
    expect(tester.getSize(find.byType(RetainedMotionTabs)), initialSize);
    scroll(30);
    await tester.pump();
    scroll(0, pixels: 0);
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
        Offset.zero);
  });
  testWidgets(
      'rapid navigation reversals keep the final selection and page aligned',
      (tester) async {
    await tester.pumpWidget(app());
    void select(int index) => tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(index);
    select(1);
    select(1);
    await tester.pump(const Duration(milliseconds: 60));
    select(0);
    await tester.pump(const Duration(milliseconds: 30));
    select(1);
    await tester.pumpAndSettle();
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1);
    expect(
        tester
            .widget<RetainedMotionTabs>(find.byType(RetainedMotionTabs))
            .index,
        1);
    select(0);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('reduced motion jumps to destination; resizing retains selection',
      (tester) async {
    await tester.pumpWidget(app(reduced: true));
    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(1);
    await tester.pump();
    expect(
        tester
            .widget<RetainedMotionTabs>(find.byType(RetainedMotionTabs))
            .index,
        1);
    expect(
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .animationDuration,
        Duration.zero);
    tester.view.physicalSize = const Size(600, 800);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pump();
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1);
    expect(tester.takeException(), isNull);
  });
}
