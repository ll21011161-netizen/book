import 'package:gun_book/screens/details/folder_detail_screen.dart';
import 'package:gun_book/core/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gun_book/core/cover_origin.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';
import 'package:gun_book/widgets/page_thumbnail.dart';
import 'package:gun_book/widgets/detail_cover.dart';
import 'package:gun_book/core/anim_route.dart';
import 'package:gun_book/data/database_helper.dart';
import 'package:gun_book/models/library_item.dart';
import 'package:gun_book/screens/details/category_detail_screen.dart';
import 'support/sqlite_database.dart';

class DetailDatabase extends DatabaseHelper {
  DetailDatabase() : super.forTesting(SqliteDatabase(), 'unused');
  final requests = <Completer<List<String>>>[];
  @override
  Future<List<String>> getBookPages(String id) {
    final request = Completer<List<String>>();
    requests.add(request);
    return request.future;
  }
}

class RefreshDetailDatabase extends DetailDatabase {
  final changes = StreamController<void>.broadcast();
  @override
  Stream<void> get onDatabaseChanged => changes.stream;
}

class FolderPreviewDatabase extends DetailDatabase {
  @override
  Future<List<MangaBook>> fetchFolderBooks(
          {required String folderId, int limit = 50, int offset = 0}) async =>
      [
        MangaBook(id: 'child', title: 'Child', filePaths: ['missing.png'])
      ];
}

void main() {
  testWidgets('cover transition defers thumbnail generation until completed',
      (tester) async {
    final db = DetailDatabase();
    final nav = GlobalKey<NavigatorState>();
    late BuildContext home;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: Builder(builder: (context) {
          home = context;
          return const Scaffold();
        })));
    final pages = List.generate(104, (i) => 'missing-$i.png');
    final route = DetailRoute<void>(
        context: home,
        source: CoverOrigin(
            resolveRect: () => const Rect.fromLTWH(20, 20, 100, 150),
            captureImage: () => null,
            radius: 12,
            color: Colors.grey),
        page: CategoryDetailScreen(
            category: MangaBook(id: 'early', title: 'Book', filePaths: pages),
            database: db,
            onUpdate: () {}));
    nav.currentState!.push(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(route.animation!.isCompleted, isFalse);
    expect(find.byType(PageThumbnail),
        findsNothing); // Includes warm-cache decodes.
    expect(
        find.text('1'), findsOneWidget); // Stable grid/labels during expansion.
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<PageThumbnail>(find.byType(PageThumbnail))
            .every((w) => w.generationEnabled),
        isTrue);
    final activeThumbnails =
        tester.elementList(find.byType(PageThumbnail)).toList();
    expect(activeThumbnails, isNotEmpty);
    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.elementList(find.byType(PageThumbnail)).toList(),
        activeThumbnails);
    await tester.pumpAndSettle();
    db.requests.single.complete(pages);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await (await db.database).close();
    expect(tester.takeException(), isNull);
  });

  testWidgets('folder cover images wait for expansion and stay on return',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = FolderPreviewDatabase();
    final settings = SettingsProvider();
    final nav = GlobalKey<NavigatorState>();
    late BuildContext home;
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
            navigatorKey: nav,
            home: Builder(builder: (context) {
              home = context;
              return const Scaffold();
            }))));
    nav.currentState!.push(DetailRoute<void>(
        context: home,
        source: CoverOrigin(
            resolveRect: () => const Rect.fromLTWH(10, 10, 100, 150),
            captureImage: () => null,
            radius: 12,
            color: Colors.grey),
        page: FolderDetailScreen(
            folder: MangaFolder(id: 'folder', title: 'Folder'),
            database: db,
            onUpdate: () {})));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byType(PageThumbnail), findsNothing);
    await tester.pumpAndSettle();
    final active = tester.elementList(find.byType(PageThumbnail)).toList();
    expect(active, isNotEmpty);
    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.elementList(find.byType(PageThumbnail)).toList(), active);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
    await (await db.database).close();
    expect(tester.takeException(), isNull);
  });
  testWidgets('covered detail stops queued generation and resumes on return',
      (tester) async {
    final db = DetailDatabase();
    final nav = GlobalKey<NavigatorState>();
    final pages = List.generate(8, (i) => 'missing-$i.png');
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: CategoryDetailScreen(
            category: MangaBook(id: 'covered', title: 'Book', filePaths: pages),
            database: db,
            onUpdate: () {})));
    db.requests.single.complete(pages);
    await tester.pumpAndSettle();
    Iterable<PageThumbnail> grid() => tester
        .widgetList<PageThumbnail>(
            find.byType(PageThumbnail, skipOffstage: false))
        .where((w) => w.priority == 1);
    expect(grid(), isNotEmpty);
    expect(grid().every((w) => w.generationEnabled), isTrue);
    nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page'))));
    await tester.pumpAndSettle();
    expect(grid().every((w) => !w.generationEnabled), isTrue);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(grid().every((w) => w.generationEnabled), isTrue);
    await tester.pumpWidget(const SizedBox());
    await (await db.database).close();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'page labels update after reorder, deletion and insertion without file names',
      (tester) async {
    final db = RefreshDetailDatabase();
    final book = MangaBook(
        id: 'labels',
        title: 'Book title',
        filePaths: ['long-file-a.png', 'long-file-b.png', 'long-file-c.png']);
    await tester.pumpWidget(MaterialApp(
        home: CategoryDetailScreen(
            category: book, database: db, onUpdate: () {})));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('long-file-a.png'), findsNothing);
    for (final thumb
        in tester.widgetList<PageThumbnail>(find.byType(PageThumbnail))) {
      thumb.onImageReady?.call();
    }
    await tester.pump();
    expect(find.byType(DetailCover), findsNothing);
    expect(find.byType(FlexibleSpaceBar), findsNothing);
    final labelRect = tester.getRect(find.text('1'));
    final imageRect = tester.getRect(find.byType(PageThumbnail).first);
    expect(labelRect.top, greaterThanOrEqualTo(imageRect.bottom));
    db.requests.single.complete(['long-file-c.png', 'long-file-a.png']);
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsNothing);
    final tile = find
        .ancestor(of: find.text('1'), matching: find.byType(GestureDetector))
        .first;
    final thumbnail = tester.widget<PageThumbnail>(
        find.descendant(of: tile, matching: find.byType(PageThumbnail)));
    expect(thumbnail.path, 'long-file-c.png');
    expect(book.filePaths, ['long-file-c.png', 'long-file-a.png']);
    expect(book.title, 'Book title');
    db.changes.add(null);
    await tester.pump();
    expect(db.requests.length, 2); // One existing data refresh, no label scans.
    const inserted = [
      'new-page.webp',
      'long-file-a.png',
      'long-file-c.png',
      'last.webp'
    ];
    db.requests.last.complete(inserted);
    await tester.pumpAndSettle();
    for (var i = 0; i < inserted.length; i++) {
      final label = find.text('${i + 1}');
      final cell = find
          .ancestor(of: label, matching: find.byType(GestureDetector))
          .first;
      final image =
          find.descendant(of: cell, matching: find.byType(PageThumbnail));
      expect(tester.widget<PageThumbnail>(image).path, inserted[i]);
      expect(
          tester.getCenter(label).dx, closeTo(tester.getCenter(image).dx, .01));
      expect(find.text(inserted[i]), findsNothing);
    }
    expect(find.text('5'), findsNothing);
    expect(book.filePaths, inserted);

    await tester.pumpWidget(const SizedBox());
    await db.changes.close();
    await (await db.database).close();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'query failure exits shimmer, retries and distinguishes empty book',
      (tester) async {
    final db = DetailDatabase();
    final book =
        MangaBook(id: 'book', title: 'test', filePaths: [], totalPageCount: 20);
    await tester.pumpWidget(MaterialApp(
        home: CategoryDetailScreen(
            category: book, database: db, onUpdate: () {})));
    expect(find.byType(Shimmer), findsWidgets);
    db.requests.single.completeError(StateError('sqlite failure'));
    await tester.pump();
    expect(find.byType(Shimmer), findsNothing);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(db.requests.length, 2);
    db.requests.last.complete([]);
    await tester.pump();
    expect(find.byType(Shimmer), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(book.totalPageCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await (await db.database).close();
  });
  testWidgets('quick departure ignores query completion and errors',
      (tester) async {
    final db = DetailDatabase();
    for (final fail in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          home: CategoryDetailScreen(
              category: MangaBook(
                  id: 'book', title: 'test', filePaths: [], totalPageCount: 2),
              database: db,
              onUpdate: () {})));
      await tester.pumpWidget(const SizedBox());
      if (fail) {
        db.requests.last.completeError(StateError('sqlite'));
      } else {
        db.requests.last.complete(['missing.png']);
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    await (await db.database).close();
  });

  testWidgets(
      'existing pages stay visible during refresh and large grid remains lazy',
      (tester) async {
    final db = DetailDatabase();
    final pages = List.generate(1000, (i) => 'missing-fixture-$i.png');
    final book = MangaBook(id: 'book', title: 'test', filePaths: pages);
    await tester.pumpWidget(MaterialApp(
        home: CategoryDetailScreen(
            category: book, database: db, onUpdate: () {})));
    expect(find.byType(Shimmer), findsNothing);
    final built = find.byType(PageThumbnail).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(1000));
    db.requests.single.completeError(StateError('sqlite'));
    await tester.pump();
    expect(find.byType(Shimmer), findsNothing);
    expect(find.byType(PageThumbnail), findsWidgets);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(tester.takeException(), isNull);
    await (await db.database).close();
  });
}
