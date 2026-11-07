import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gun_book/core/settings_provider.dart';
import 'package:gun_book/data/database_helper.dart';
import 'package:gun_book/models/library_item.dart';
import 'package:gun_book/screens/bookshelf/bookshelf_screen.dart';
import 'package:gun_book/widgets/bookshelf_header.dart';
import 'support/sqlite_database.dart';

class RecentDatabase extends DatabaseHelper {
  RecentDatabase() : super.forTesting(SqliteDatabase(), 'unused');
  final book = MangaBook(id: 'recent', title: 'recent', filePaths: []);
  final requests = <Completer<MangaBook>>[];
  bool failCount = false;
  @override
  Future<List<LibraryItem>> fetchItems(
          {String? parentId, int limit = 50, int offset = 0}) async =>
      [book];
  @override
  Future<MangaBook> getBookFull(String id) {
    final request = Completer<MangaBook>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<void> incrementReadCount(String id) async {
    if (failCount) throw StateError('sqlite failure');
  }
}

// Return a real Navigator route without starting a reader against real storage.
class ReturnObserver extends NavigatorObserver {
  int readers = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      readers++;
      scheduleMicrotask(() => navigator!.removeRoute(route));
    }
  }
}

void main() {
  for (final outcome in ['empty', 'missing', 'count failure', 'return']) {
    testWidgets('recent reader unlocks after $outcome', (tester) async {
      SharedPreferences.setMockInitialValues({
        'recent_read_book_ids': ['recent']
      });
      final db = RecentDatabase();
      final observer = ReturnObserver();
      await tester.pumpWidget(ChangeNotifierProvider(
          create: (_) => SettingsProvider(),
          child: MaterialApp(
              navigatorObservers: [observer],
              home: BookshelfScreen(database: db))));
      await tester.pumpAndSettle();
      void open() => tester
          .widget<BookshelfHeader>(find.byType(BookshelfHeader))
          .onContinue!();
      open();
      open();
      expect(db.requests, hasLength(1));
      if (outcome == 'missing') {
        db.requests.first.completeError(StateError('book removed'));
      } else {
        db.failCount = outcome == 'count failure';
        db.requests.first.complete(MangaBook(
            id: 'recent',
            title: 'recent',
            filePaths: outcome == 'empty' ? [] : ['synthetic.png']));
      }
      await tester.pumpAndSettle();
      open();
      expect(db.requests, hasLength(2));
      db.requests.last.complete(db.book);
      await tester.pumpAndSettle();
      if (outcome == 'return') expect(observer.readers, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await (await db.database).close();
    });
  }
  testWidgets('recent request failure after disposal is handled',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'recent_read_book_ids': ['recent']
    });
    final db = RecentDatabase();
    await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: MaterialApp(home: BookshelfScreen(database: db))));
    await tester.pumpAndSettle();
    tester.widget<BookshelfHeader>(find.byType(BookshelfHeader)).onContinue!();
    await tester.pumpWidget(const SizedBox());
    db.requests.single.completeError(StateError('offline'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await (await db.database).close();
  });
}
