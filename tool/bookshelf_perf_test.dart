import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/data/database_helper.dart';
import '../test/support/sqlite_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('50 custom-cover folders in a 5000-book library', () async {
    final sql = SqliteDatabase();
    // ignore: invalid_use_of_visible_for_testing_member
    await DatabaseHelper.initializeSchemaForTesting(sql);
    final library = DatabaseHelper.forTesting(sql, 'unused-benchmark');
    for (var i = 0; i < 50; i++) {
      await sql.insert('items', {
        'id': 'folder$i',
        'title': 'Folder $i',
        'type': 'folder',
        'sort_order': i,
        'folder_cover_ids':
            jsonEncode(List.generate(4, (j) => 'book${i * 100 + j}')),
      });
      for (var j = 0; j < 100; j++) {
        final id = i * 100 + j;
        await sql.insert('items', {
          'id': 'book$id',
          'title': 'Book $id',
          'type': 'book',
          'parent_id': 'folder$i',
          'sort_order': j,
          'cover_path': '/synthetic/$id.jpg',
          'total_pages': 500,
        });
      }
    }
    for (final search in [false, true]) {
      for (var run = 0; run < 5; run++) {
        var queries = 0;
        sql.beforeStatement = (query) async {
          if (query.trimLeft().startsWith('SELECT')) queries++;
        };
        final watch = Stopwatch()..start();
        final rows = search
            ? await library.searchItems('Folder')
            : await library.fetchItems();
        watch.stop();
        expect(rows.length, 50);
        // ignore: avoid_print
        print(
            'GUNBOOK_SHELF_BENCH search=$search run=$run folders=50 books=5000 elapsed_us=${watch.elapsedMicroseconds} queries=$queries');
      }
    }
    await sql.close();
  });
}
