import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gun_book/core/settings_provider.dart';
import 'package:gun_book/data/database_helper.dart';
import 'package:gun_book/models/library_item.dart';
import 'package:gun_book/screens/bookshelf/bookshelf_screen.dart';
import 'package:gun_book/screens/details/folder_detail_screen.dart';
import 'package:gun_book/widgets/book_card.dart';
import 'package:gun_book/widgets/drag_cover.dart';
import 'package:gun_book/widgets/folder_card.dart';
import 'support/sqlite_database.dart';

class MotionLibrary extends DatabaseHelper {
  MotionLibrary() : super.forTesting(SqliteDatabase(), 'unused');
  final items = <LibraryItem>[
    MangaBook(id: 'a', title: 'a', filePaths: []),
    MangaBook(id: 'b', title: 'b', filePaths: []),
    MangaFolder(id: 'f', title: 'folder'),
  ];
  final changes = StreamController<void>.broadcast();
  int reorders = 0;
  String? moved;
  @override
  Stream<void> get onDatabaseChanged => changes.stream;
  @override
  Future<List<LibraryItem>> fetchItems(
          {String? parentId, int limit = 50, int offset = 0}) async =>
      [...items];
  @override
  Future<List<MangaBook>> fetchFolderBooks(
          {required String folderId, int limit = 50, int offset = 0}) async =>
      items.whereType<MangaBook>().toList();
  @override
  Future<void> updateSortOrder(List<String> ids, {bool notify = true}) async {
    reorders++;
  }

  @override
  Future<void> moveItems(List<String> ids, String? folderId,
      {bool notify = true}) async {
    moved = folderId;
  }
}

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
        'real gestures reorder 10 times, merge, cancel and select reduced=$reduced',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = MotionLibrary();
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(ChangeNotifierProvider(
          create: (_) => SettingsProvider(),
          child: MaterialApp(
              navigatorKey: nav,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: reduced),
                  child: child!),
              home: BookshelfScreen(database: db))));
      await tester.pumpAndSettle();
      Finder book(String id) =>
          find.byWidgetPredicate((w) => w is BookCard && w.book.id == id).first;
      for (var i = 0; i < 10; i++) {
        final gesture = await tester.startGesture(tester.getCenter(book('a')));
        await tester.pump(const Duration(milliseconds: 310));
        expect(find.byType(PhysicsDragFeedback), findsOneWidget);
        await gesture.moveTo(tester.getCenter(book('b')));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.widget<BookCard>(book('b')).dragVisualMode,
            DragVisualMode.reorder);
        final cover =
            find.descendant(of: book('b'), matching: find.byType(DragCover));
        expect(tester.getRect(cover).bottom,
            lessThan(tester.getRect(book('b')).bottom - 36));
        expect(
            find.descendant(of: cover, matching: find.byIcon(Icons.swap_vert)),
            findsOneWidget);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(db.reorders, i + 1);
        expect(find.byType(PhysicsDragFeedback), findsNothing);
      }
      final merge = await tester.startGesture(tester.getCenter(book('a')));
      await tester.pump(const Duration(milliseconds: 310));
      await merge.moveTo(tester.getCenter(find.byType(FolderCard).first));
      await tester.pump(const Duration(milliseconds: 501));
      expect(
          tester
              .widget<FolderCard>(find.byType(FolderCard).first)
              .dragVisualMode,
          DragVisualMode.merge);
      expect(find.byIcon(Icons.create_new_folder), findsOneWidget);
      await merge.up();
      await tester.pumpAndSettle();
      expect(db.moved, 'f');
      final cancel = await tester.startGesture(tester.getCenter(book('a')));
      await tester.pump(const Duration(milliseconds: 310));
      await cancel.moveTo(tester.getCenter(book('b')));
      await tester.pump(const Duration(milliseconds: 501));
      expect(tester.widget<BookCard>(book('b')).dragVisualMode,
          DragVisualMode.merge);
      await cancel.moveTo(tester.getCenter(find.byType(FolderCard).first));
      await tester.pump(const Duration(milliseconds: 10));
      expect(tester.widget<BookCard>(book('b')).dragVisualMode,
          DragVisualMode.none);
      expect(
          tester
              .widget<FolderCard>(find.byType(FolderCard).first)
              .dragVisualMode,
          DragVisualMode.reorder);
      await cancel.cancel();
      await tester.pumpAndSettle();
      expect(find.byType(PhysicsDragFeedback), findsNothing);
      expect(db.reorders, 10);
      expect(
          tester
              .widget<FolderCard>(find.byType(FolderCard).first)
              .dragVisualMode,
          DragVisualMode.none);
      expect(tester.widget<BookCard>(book('a')).isSelected, isFalse);
      final folderDrag = await tester
          .startGesture(tester.getCenter(find.byType(FolderCard).first));
      await tester.pump(const Duration(milliseconds: 310));
      await folderDrag.moveTo(tester.getCenter(book('b')));
      await tester.pump(const Duration(milliseconds: 501));
      expect(tester.widget<BookCard>(book('b')).dragVisualMode,
          DragVisualMode.reorder);
      await folderDrag.up();
      await tester.pumpAndSettle();
      expect(db.reorders, 11);
      expect(find.byIcon(Icons.create_new_folder), findsNothing);
      final hold = await tester.startGesture(tester.getCenter(book('a')));
      await tester.pump(const Duration(milliseconds: 600));
      await hold.up();
      await tester.pumpAndSettle();
      expect(tester.widget<BookCard>(book('a')).isSelected, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await db.changes.close();
      await (await db.database).close();
    });
  }

  testWidgets(
      'folder drag preserves grid dimensions, Hero safety and stationary multi-select',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = MotionLibrary();
    await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: MaterialApp(
            home: FolderDetailScreen(
                folder: MangaFolder(id: 'f', title: 'folder'),
                database: db,
                onUpdate: () {}))));
    await tester.pumpAndSettle();
    expect(find.byType(FlexibleSpaceBar), findsNothing);
    expect(
        tester.widget<SliverAppBar>(find.byType(SliverAppBar)).expandedHeight,
        isNull);
    final originalSize = tester.getSize(find.byType(BookCard).first);
    final hold = await tester
        .startGesture(tester.getCenter(find.byType(BookCard).first));
    await tester.pump(const Duration(milliseconds: 310));
    final draggable = tester.widget<LongPressDraggable<int>>(
        find.byType(LongPressDraggable<int>).first);
    final feedback = draggable.feedback as HeroMode;
    expect(feedback.enabled, isFalse);
    expect(tester.getSize(find.byWidget(feedback)), originalSize);
    await hold.up();
    await tester.pumpAndSettle();
    expect(tester.widget<BookCard>(find.byType(BookCard).first).isSelected,
        isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.changes.close();
    await (await db.database).close();
  });

  testWidgets('leaving bookshelf during a live drag cleans feedback and timers',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = MotionLibrary();
    await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: MaterialApp(home: BookshelfScreen(database: db))));
    await tester.pumpAndSettle();
    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(BookCard).first));
    await tester.pump(const Duration(milliseconds: 310));
    await gesture.moveBy(const Offset(15, 10));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await db.changes.close();
    await (await db.database).close();
  });

  testWidgets(
      'feedback transforms only, clamps rotation and honors reduced motion',
      (tester) async {
    final tilt = ValueNotifier<double>(0);
    var builds = 0;
    final child = Builder(builder: (_) {
      builds++;
      return const SizedBox(width: 100, height: 150);
    });
    Widget app(bool reduced) => MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: PhysicsDragFeedback(tiltNotifier: tilt, child: child)));
    await tester.pumpWidget(app(false));
    final initial = builds;
    for (var i = 0; i < 20; i++) {
      tilt.value = i.isEven ? 0.5 : -0.5;
      await tester.pump(const Duration(milliseconds: 8));
    }
    await tester.pumpAndSettle();
    expect(builds, initial);
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    final transforms = tester.widgetList<Transform>(find.descendant(
        of: find.byType(PhysicsDragFeedback),
        matching: find.byType(Transform)));
    for (final transform in transforms) {
      expect(transform.transform.isIdentity(), isTrue);
    }
    await tester.pumpWidget(const SizedBox());
    tilt.dispose();
    expect(tester.takeException(), isNull);
  });
}
