import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gun_book/core/settings_provider.dart';
import 'package:gun_book/data/database_helper.dart';
import 'package:gun_book/models/library_item.dart';
import 'package:gun_book/screens/details/folder_detail_screen.dart';
import 'package:gun_book/screens/details/category_detail_screen.dart';
import 'package:gun_book/widgets/book_card.dart';
import 'support/sqlite_database.dart';

class FolderDatabase extends DatabaseHelper {
  FolderDatabase() : super.forTesting(SqliteDatabase(), 'unused');
  final requests = <Completer<List<MangaBook>>>[];
  final offsets = <int>[];
  final limits = <int>[];
  final writes = <Completer<void>>[];
  List<String>? moved;
  @override
  Future<List<MangaBook>> fetchFolderBooks(
      {required String folderId, int limit = 50, int offset = 0}) {
    offsets.add(offset);
    limits.add(limit);
    final request = Completer<List<MangaBook>>();
    requests.add(request);
    return request.future;
  }

  Future<void> write() {
    final request = Completer<void>();
    writes.add(request);
    return request.future;
  }

  @override
  Future<void> moveItems(List<String> ids, String? folderId,
      {bool notify = true}) {
    moved = ids;
    return write();
  }

  @override
  Future<void> updateSortOrder(List<String> ids, {bool notify = true}) =>
      write();
  @override
  Future<void> updateTitle(String id, String title) => write();
  @override
  Future<void> updateFolderCovers(String id, List<String> covers) => write();
}

void main() {
  SharedPreferences.setMockInitialValues({});
  List<MangaBook> books(int count) => List.generate(
      count, (i) => MangaBook(id: '$i', title: 'book $i', filePaths: []));
  Future<void> open(WidgetTester tester, FolderDatabase db) async {
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(
            create: (_) => SettingsProvider(),
            child: FolderDetailScreen(
                folder:
                    MangaFolder(id: 'folder', title: 'folder', itemCount: 100),
                database: db,
                onUpdate: () {}))));
  }

  Future<void> close(WidgetTester tester, FolderDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    await (await db.database).close();
  }

  testWidgets('failed load stops spinner and retry recovers', (tester) async {
    final db = FolderDatabase();
    await open(tester, db);
    db.requests.single.completeError(StateError('database unavailable'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    db.requests.last.complete(books(2));
    await tester.pump();
    expect(find.byType(BookCard), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await close(tester, db);
  });
  testWidgets('stale refresh cannot replace a newer folder result',
      (tester) async {
    final db = FolderDatabase();
    await open(tester, db);
    db.requests.single.complete(books(1));
    await tester.pump();
    final card = tester.widget<BookCard>(find.byType(BookCard));
    card.onTap();
    await tester.pumpAndSettle();
    final detail =
        tester.widget<CategoryDetailScreen>(find.byType(CategoryDetailScreen));
    detail.onUpdate();
    detail.onUpdate();
    db.requests.last
        .complete([MangaBook(id: 'new', title: 'new', filePaths: [])]);
    await tester.pump();
    db.requests[1].complete(books(1));
    await tester.pump();
    Navigator.of(tester.element(find.byType(CategoryDetailScreen))).pop();
    await tester.pumpAndSettle();
    expect(tester.widget<BookCard>(find.byType(BookCard)).book.id, 'new');
    await close(tester, db);
  });
  testWidgets('query completion after dispose is harmless', (tester) async {
    for (final fail in [false, true]) {
      final db = FolderDatabase();
      await open(tester, db);
      await tester.pumpWidget(const SizedBox());
      if (fail) {
        db.requests.single.completeError(StateError('offline'));
      } else {
        db.requests.single.complete(books(1));
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
      await (await db.database).close();
    }
  });
  testWidgets(
      'pagination deduplicates loads and edit refresh preserves loaded window',
      (tester) async {
    final db = FolderDatabase();
    await open(tester, db);
    db.requests.single.complete(books(50));
    await tester.pump();
    final controller = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(db.requests, hasLength(2));
    expect(db.offsets.last, 50);
    db.requests.last.complete(List.generate(
        50,
        (i) => MangaBook(
            id: '${i + 50}', title: 'book ${i + 50}', filePaths: [])));
    await tester.pump();
    controller.jumpTo(0);
    await tester.pump();
    final target =
        tester.widgetList<DragTarget<int>>(find.byType(DragTarget<int>)).first;
    // ignore: deprecated_member_use
    target.onAccept!(1);
    db.writes.single.complete();
    await tester.pump();
    expect(db.limits.last, 100);
    expect(db.offsets.last, 0);
    db.requests.last.complete(books(100));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await close(tester, db);
  });
  testWidgets('failed reorder preserves order and ignores repeated writes',
      (tester) async {
    final db = FolderDatabase();
    await open(tester, db);
    db.requests.single.complete(books(3));
    await tester.pump();
    final target =
        tester.widgetList<DragTarget<int>>(find.byType(DragTarget<int>)).first;
    // Exercise the callback used by the existing drag UI.
    // ignore: deprecated_member_use
    target.onAccept!(2);
    // ignore: deprecated_member_use
    target.onAccept!(1);
    await tester.pump();
    expect(db.writes, hasLength(1));
    expect(
        tester
            .widgetList<BookCard>(find.byType(BookCard))
            .map((c) => c.book.id),
        ['0', '1', '2']);
    db.writes.single.completeError(StateError('disk full'));
    await tester.pump();
    db.requests.last.complete(books(3));
    await tester.pump();
    expect(
        tester
            .widgetList<BookCard>(find.byType(BookCard))
            .map((c) => c.book.id),
        ['0', '1', '2']);
    expect(tester.takeException(), isNull);
    await close(tester, db);
  });
  for (final operation in ['move', 'rename', 'covers']) {
    testWidgets('$operation completion after departure is safe',
        (tester) async {
      final db = FolderDatabase();
      await open(tester, db);
      db.requests.single.complete(books(2));
      await tester.pump();
      if (operation == 'covers') {
        await tester.tap(find.byTooltip('設定封面'));
        await tester.pump();
        await tester.tap(find.byTooltip('儲存封面'));
        await tester.pump();
      } else {
        tester.widget<BookCard>(find.byType(BookCard).first).onLongPress();
        await tester.pump();
        if (operation == 'move') {
          await tester.tap(find.byTooltip('移出資料夾'));
          await tester.pump();
        } else {
          await tester.tap(find.byIcon(Icons.edit));
          await tester.pumpAndSettle();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
        }
      }
      expect(db.writes, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      db.writes.single.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
      await (await db.database).close();
    });
  }
}
