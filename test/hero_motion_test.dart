import 'package:gun_book/core/cover_origin.dart';
import 'package:gun_book/core/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gun_book/core/anim_route.dart';
import 'package:gun_book/core/settings_provider.dart';
import 'package:gun_book/data/database_helper.dart';
import 'package:gun_book/models/library_item.dart';
import 'package:gun_book/screens/details/category_detail_screen.dart';
import 'package:gun_book/screens/details/folder_detail_screen.dart';
import 'package:gun_book/widgets/book_card.dart';
import 'package:gun_book/widgets/folder_card.dart';
import 'support/sqlite_database.dart';

class HeroDatabase extends DatabaseHelper {
  HeroDatabase() : super.forTesting(SqliteDatabase(), 'unused');
  @override
  Future<List<String>> getBookPages(String id) async => [];
  @override
  Future<List<MangaBook>> fetchFolderBooks(
          {required String folderId, int limit = 50, int offset = 0}) async =>
      [];
}

void main() {
  for (final folder in [false, true]) {
    for (final reduced in [false, true]) {
      for (final container in [false, true]) {
        testWidgets(
            'card route tolerates interrupted return folder=$folder reduced=$reduced container=$container',
            (tester) async {
          SharedPreferences.setMockInitialValues({});
          final db = HeroDatabase();
          final book = MangaBook(
              id: 'book', title: 'very long title ' * 20, filePaths: []);
          final navigator = GlobalKey<NavigatorState>();
          final mangaFolder = MangaFolder(id: 'folder', title: 'Folder');
          void open([CoverOrigin? source]) =>
              navigator.currentState!.push(DetailRoute<void>(
                  context: navigator.currentContext!,
                  source: source,
                  page: folder
                      ? FolderDetailScreen(
                          folder: mangaFolder, database: db, onUpdate: () {})
                      : CategoryDetailScreen(
                          category: book, database: db, onUpdate: () {})));
          await tester.pumpWidget(ChangeNotifierProvider(
              create: (_) => SettingsProvider(),
              child: MaterialApp(
                  navigatorKey: navigator,
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(disableAnimations: reduced),
                      child: MotionScope(
                          settings: MotionSettings(
                              detail: container
                                  ? DetailMotion.containerTransform
                                  : DetailMotion.followPage),
                          child: child!)),
                  home: Scaffold(
                      body: Center(
                          child: SizedBox(
                              width: 110,
                              height: 200,
                              child: folder
                                  ? FolderCard(
                                      folder: mangaFolder,
                                      onLongPress: () {},
                                      onOpen: open,
                                      onTap: open)
                                  : BookCard(
                                      book: book,
                                      onLongPress: () {},
                                      onOpen: open,
                                      onTap: open)))))));
          await tester.pump();
          final card = folder ? find.byType(FolderCard) : find.byType(BookCard);
          final gesture = await tester.startGesture(tester.getCenter(card));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          await gesture.up();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 70));
          expect(
              folder
                  ? find.byType(FolderDetailScreen)
                  : find.byType(CategoryDetailScreen),
              findsOneWidget);
          navigator.currentState!.pop();
          await tester.pumpAndSettle();
          expect(card, findsOneWidget);
          expect(
              find.descendant(of: card, matching: find.byType(ScaleTransition)),
              findsNothing);
          expect(find.byType(Hero), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          await (await db.database).close();
        });
      }
    }
  }
}
