// Run explicitly, not as a normal regression test. Uses temporary synthetic data.
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/data/database_helper.dart';
import 'package:gun_book/data/import_service.dart';
import 'package:gun_book/models/import_args.dart';
import 'package:path/path.dart' as p;
import '../test/support/sqlite_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('synthetic local import benchmark', () async {
    final temp = await Directory.systemTemp.createTemp('gunbook-perf-fixture-');
    try {
      final source = await Directory(p.join(temp.path, 'source')).create();
      const count = int.fromEnvironment('BENCH_FILES', defaultValue: 80);
      const size = int.fromEnvironment('BENCH_BYTES', defaultValue: 65536);
      final data = Uint8List.fromList(List.generate(size, (i) => i % 251));
      for (var i = 0; i < count; i++) {
        await File(p.join(source.path, '$i.jpg')).writeAsBytes(data);
      }
      for (var run = 0; run < 3; run++) {
        final books = await Directory(p.join(temp.path, 'books$run')).create();
        final sql = SqliteDatabase();
        // ignore: invalid_use_of_visible_for_testing_member
        await DatabaseHelper.initializeSchemaForTesting(sql);
        final db = DatabaseHelper.forTesting(sql, books.path);
        final text = ValueNotifier('');
        var notifications = 0;
        text.addListener(() => notifications++);
        final watch = Stopwatch()..start();
        final imported = await ImportService.importBooks(
          ImportArgs(source.path, books.path),
          text,
          CancelToken(),
          database: db,
        );
        watch.stop();
        expect(imported.single.filePaths.length, count);
        // ignore: avoid_print
        print(
            'GUNBOOK_BENCH run=$run total_ms=${watch.elapsedMilliseconds} pages=$count bytes=${count * data.length} notifications=$notifications');
        text.dispose();
        await sql.close();
      }
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
