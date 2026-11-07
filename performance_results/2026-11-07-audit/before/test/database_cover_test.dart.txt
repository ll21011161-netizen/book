import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/data/database_helper.dart';
import 'package:gun_book/models/library_item.dart';
import 'support/sqlite_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqliteDatabase sql;
  late DatabaseHelper library;
  setUp(() async {
    sql = SqliteDatabase();
    await DatabaseHelper.initializeSchemaForTesting(sql);
    library = DatabaseHelper.forTesting(sql, 'unused-cover-test');
  });
  tearDown(() => sql.close());

  test('batched covers preserve legacy query order, duplicates and fallback',
      () async {
    for (var i = 0; i < 161; i++) {
      final ids = ['z$i', 'missing$i', 'a$i', 'z$i', 'null$i'];
      await sql.insert('items', {
        'id': 'folder$i',
        'title': 'Folder $i',
        'type': 'folder',
        'sort_order': i,
        'folder_cover_ids': jsonEncode(ids),
      });
      for (final prefix in ['z', 'a', 'null', 'auto']) {
        await sql.insert('items', {
          'id': '$prefix$i',
          'title': '$prefix$i',
          'type': 'book',
          'parent_id': 'folder$i',
          'sort_order': prefix == 'auto' ? 0 : 1,
          'cover_path': prefix == 'null'
              ? null
              : prefix == 'auto'
                  ? 'auto$i.jpg'
                  : 'shared$i.jpg',
        });
      }
    }
    final legacy = await sql.query('items',
        columns: ['cover_path'],
        where: 'id IN (?,?,?,?,?) AND cover_path IS NOT NULL',
        whereArgs: ['z0', 'missing0', 'a0', 'z0', 'null0']);
    var queries = 0;
    sql.beforeStatement = (query) async {
      if (query.trimLeft().startsWith('SELECT')) queries++;
    };
    final folders = (await library.fetchItems(limit: 200)).cast<MangaFolder>();
    expect(queries, 4); // one page SELECT + three bounded cover batches
    expect(folders.length, 161);
    expect(folders.first.thumbnails, [
      ...legacy.map((r) => r['cover_path']),
      'auto0.jpg',
    ]);
    expect(folders.last.thumbnails,
        ['shared160.jpg', 'shared160.jpg', 'auto160.jpg']);
    expect(folders.first.itemCount, 4);
    expect(folders.first.coverBookIds, ['z0', 'missing0', 'a0', 'z0', 'null0']);
    queries = 0;
    final search = (await library.searchItems('Folder')).cast<MangaFolder>();
    expect(search.length, 100);
    expect(search.first.thumbnails, folders.first.thumbnails);
    expect(queries, 3);
    final page = await library.fetchItems(limit: 1, offset: 160);
    expect(page.single.id, 'folder160');
  });

  test('automatic and malformed cover choices need only the page query',
      () async {
    for (final choice in [null, '[]', 'invalid', '[1]']) {
      await sql.insert('items', {
        'id': '$choice',
        'title': '$choice',
        'type': 'folder',
        'folder_cover_ids': choice
      });
    }
    var queries = 0;
    sql.beforeStatement = (query) async {
      if (query.trimLeft().startsWith('SELECT')) queries++;
    };
    expect((await library.fetchItems()).length, 4);
    expect(queries, 1);
  });
}
