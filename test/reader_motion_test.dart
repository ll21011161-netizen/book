import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gun_book/core/settings_provider.dart';
import 'package:gun_book/data/database_helper.dart';
import 'package:gun_book/models/library_item.dart';
import 'package:gun_book/screens/reader/manga_reader_screen.dart';
import 'package:gun_book/widgets/reader_controls_transition.dart';
import 'package:gun_book/widgets/glass_box.dart';
import 'support/sqlite_database.dart';
import 'support/test_image.dart';

class ReaderDatabase extends DatabaseHelper {
  ReaderDatabase() : super.forTesting(SqliteDatabase(), 'unused');
  final saved = <int>[];
  @override
  Future<void> updateProgress(String id, int page) async {
    saved.add(page);
  }
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('leaving reader restores system icon contrast dark=$dark',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = ReaderDatabase();
      await tester.pumpWidget(ChangeNotifierProvider(
          create: (_) => SettingsProvider(),
          child: MaterialApp(
              theme: dark ? ThemeData.dark() : ThemeData.light(),
              home: MangaReaderScreen(
                  book: MangaBook(id: 'empty', title: 'empty', filePaths: []),
                  initialPage: 0,
                  database: db))));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(SystemChrome.latestStyle?.systemNavigationBarIconBrightness,
          dark ? Brightness.light : Brightness.dark);
      await (await db.database).close();
    });
  }
  for (final rtl in [false, true]) {
    testWidgets('plain full-resolution paging and rapid controls rtl=$rtl',
        (tester) async {
      SharedPreferences.setMockInitialValues({'read_rtl': rtl ? 1 : 0});
      final directory = await tester.runAsync(
          () => Directory.systemTemp.createTemp('gunbook-ui-reader-'));
      final paths = <String>[];
      await tester.runAsync(() async {
        for (var n = 0; n < 3; n++) {
          paths.add((await writeTestImage('${directory!.path}/$n.png',
                  width: 1080, height: 1600))
              .path);
        }
      });
      final db = ReaderDatabase();
      await tester.pumpWidget(ChangeNotifierProvider(
          create: (_) => SettingsProvider(),
          child: MaterialApp(
              home: MangaReaderScreen(
                  book: MangaBook(id: 'test', title: 'test', filePaths: paths),
                  initialPage: 0,
                  database: db))));
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      final pager = find.byType(PageView);
      expect(tester.widget<PageView>(pager).reverse, rtl);
      expect(find.descendant(of: pager, matching: find.byType(Opacity)),
          findsNothing);
      expect(find.descendant(of: pager, matching: find.byType(AnimatedOpacity)),
          findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      final image = tester
          .widgetList<Image>(
              find.descendant(of: pager, matching: find.byType(Image)))
          .first;
      final slider = tester.widget<Slider>(find.byType(Slider));
      final pageState = tester.state(find.byType(InteractiveViewer).first);
      void toggle() => tester
          .widgetList<GestureDetector>(
              find.ancestor(of: pager, matching: find.byType(GestureDetector)))
          .firstWhere((w) => w.onTap != null)
          .onTap!();
      toggle();
      await tester.pump(const Duration(milliseconds: 40));
      toggle();
      await tester.pump(const Duration(milliseconds: 20));
      for (final transition in tester.widgetList<ReaderControlsTransition>(
          find.byType(ReaderControlsTransition))) {
        expect(transition.visible, isFalse);
      }
      expect(
          tester.state(find.byType(InteractiveViewer).first), same(pageState));
      expect(tester.widget<Slider>(find.byType(Slider)), same(slider));
      expect(
          tester
              .widgetList<Image>(
                  find.descendant(of: pager, matching: find.byType(Image)))
              .first
              .image,
          image.image);
      final center = tester.getCenter(pager);
      await tester.dragFrom(center, Offset(rtl ? 600 : -600, 0));
      await tester.pumpAndSettle();
      final controller = tester.widget<PageView>(pager).controller!;
      expect(controller.page, closeTo(1, .01));
      controller.jumpToPage(2);
      await tester.pumpAndSettle();
      expect(controller.page, closeTo(2, .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(db.saved.last, 2);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await tester.runAsync(() => directory!.delete(recursive: true));
      await (await db.database).close();
    });
  }
  testWidgets(
      'hidden controls reject touches and rapid reversal stays consistent',
      (tester) async {
    final visible = ValueNotifier(false);
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Stack(children: [
      ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, show, __) => ReaderControlsTransition(
              visible: show,
              fromTop: true,
              child: GlassBox(
                  blur: 0,
                  child: SizedBox(
                      height: 120,
                      child: TextButton(
                          onPressed: () => taps++,
                          child: const Text('controls')))))),
    ]))));
    visible.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    visible.value = false;
    await tester.pump();
    expect(
        tester
            .widget<IgnorePointer>(find
                .descendant(
                    of: find.byType(ReaderControlsTransition),
                    matching: find.byType(IgnorePointer))
                .first)
            .ignoring,
        isTrue);
    visible.value = true;
    await tester.pumpAndSettle();
    await tester.tap(find.text('controls'));
    expect(taps, 1);
    visible.value = false;
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    visible.dispose();
  });
}
