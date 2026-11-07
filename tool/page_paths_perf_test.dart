import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/data/database_helper.dart';
import 'package:gun_book/models/library_item.dart';
import '../test/support/sqlite_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('repeat page-list queries with 5000 paths', () async {
    for (var run = 0; run < 3; run++) {
      final sql = SqliteDatabase();
      // ignore: invalid_use_of_visible_for_testing_member
      await DatabaseHelper.initializeSchemaForTesting(sql);
      final db = DatabaseHelper.forTesting(sql, 'unused-benchmark');
      final paths = List.generate(5000, (i) => '/synthetic/book/page$i.png');
      await db.saveBooksBatch(
          [MangaBook(id: 'book', title: 'synthetic', filePaths: paths)]);
      var queries = 0;
      sql.beforeStatement = (query) async {
        if (query.startsWith('SELECT') && query.contains('FROM pages')) {
          queries++;
        }
      };
      final first = Stopwatch()..start();
      final firstPaths = await db.getBookPages('book');
      first.stop();
      expect(firstPaths, paths);
      final repeat = Stopwatch()..start();
      final repeatPaths = await db.getBookPages('book');
      repeat.stop();
      expect(repeatPaths, paths);
      // ignore: avoid_print
      print(
          'GUNBOOK_PATHS_BENCH run=$run count=5000 cold_us=${first.elapsedMicroseconds} repeat_us=${repeat.elapsedMicroseconds} queries=$queries');
      await sql.close();
    }
  });
}
