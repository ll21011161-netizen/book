import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gun_book/core/settings_provider.dart';
import 'package:gun_book/data/database_helper.dart';
import 'package:gun_book/models/library_item.dart';
import 'package:gun_book/screens/bookshelf/bookshelf_screen.dart';
import 'support/sqlite_database.dart';

class ControlledLibrary extends DatabaseHelper {
  ControlledLibrary() : super.forTesting(SqliteDatabase(), 'unused-test-path');
  final limits = <int>[];
  final offsets = <int>[];
  final requests = <Completer<List<LibraryItem>>>[];
  final changes = StreamController<void>.broadcast();
  @override
  Stream<void> get onDatabaseChanged => changes.stream;
  final moving = Completer<void>();
  final moveStarted = Completer<void>();
  List<String>? movedIds;
  String? destination;
  @override
  Future<List<LibraryItem>> fetchItems(
      {String? parentId, int limit = 50, int offset = 0}) {
    limits.add(limit);
    offsets.add(offset);
    final reply = Completer<List<LibraryItem>>();
    requests.add(reply);
    return reply.future;
  }

  @override
  Future<void> moveItems(List<String> ids, String? folderId,
      {bool notify = true}) async {
    movedIds = ids;
    destination = folderId;
    moveStarted.complete();
    await moving.future;
  }
}

void main() {
  SharedPreferences.setMockInitialValues({});
  testWidgets('a burst of database notifications triggers one refresh',
      (tester) async {
    final library = ControlledLibrary();
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(
            create: (_) => SettingsProvider(),
            child: BookshelfScreen(database: library))));
    library.requests.single.complete([]);
    await tester.pump();
    library.changes.add(null);
    library.changes.add(null);
    library.changes.add(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 41));
    expect(library.requests.length, 2);
    library.requests.last.complete([]);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await library.changes.close();
    await (await library.database).close();
  });

  testWidgets('old refresh cannot overwrite a newer result', (tester) async {
    final library = ControlledLibrary();
    final key = GlobalKey<BookshelfScreenState>();
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(
            create: (_) => SettingsProvider(),
            child: BookshelfScreen(key: key, database: library))));
    final newer = key.currentState!.loadData(refresh: true);
    library.requests[1].complete([MangaFolder(id: 'new', title: 'new result')]);
    await newer;
    await tester.pump();
    library.requests[0]
        .complete([MangaFolder(id: 'old', title: 'stale result')]);
    await tester.pump();
    expect(find.text('new result'), findsOneWidget);
    expect(find.text('stale result'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await (await library.database).close();
  });

  testWidgets('merge completion cannot remove a refreshed list by old index',
      (tester) async {
    final library = ControlledLibrary();
    final key = GlobalKey<BookshelfScreenState>();
    final book = MangaBook(id: 'book', title: 'original book', filePaths: []);
    final folder = MangaFolder(id: 'folder', title: 'destination');
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(
            create: (_) => SettingsProvider(),
            child: BookshelfScreen(key: key, database: library))));
    library.requests[0].complete([book, folder]);
    await tester.pump();
    final target = tester
        .widgetList<DragTarget<String>>(find.byType(DragTarget<String>))
        .last;
    target.onWillAccept!('book');
    await tester.pump(const Duration(milliseconds: 501));
    target.onAccept!('book');
    await tester.pump();
    expect(library.moveStarted.isCompleted, isTrue);
    final refresh = key.currentState!.loadData(refresh: true);
    library.requests[1]
        .complete([MangaFolder(id: 'replacement', title: 'replacement item')]);
    await refresh;
    await tester.pump();
    library.moving.complete();
    await tester.pump();
    expect(library.movedIds, ['book']);
    expect(library.destination, 'folder');
    expect(find.text('replacement item'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await (await library.database).close();
  });

  testWidgets(
      'pagination blocks duplicate loads and refresh retains loaded window',
      (tester) async {
    final library = ControlledLibrary();
    final key = GlobalKey<BookshelfScreenState>();
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(
            create: (_) => SettingsProvider(),
            child: BookshelfScreen(key: key, database: library))));
    List<LibraryItem> items(int start) => List.generate(50,
        (i) => MangaFolder(id: '${start + i}', title: 'folder ${start + i}'));
    library.requests[0].complete(items(0));
    await tester.pump();
    final next = key.currentState!.loadData();
    await key.currentState!.loadData();
    expect(library.requests.length, 2);
    expect(library.offsets.last, 50);
    library.requests[1].complete(items(50));
    await next;
    await tester.pump();
    final refresh = key.currentState!.loadData(refresh: true);
    expect(library.limits.last, 100);
    expect(library.offsets.last, 0);
    library.requests.last.complete([...items(0), ...items(50)]);
    await refresh;
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await (await library.database).close();
  });
}
