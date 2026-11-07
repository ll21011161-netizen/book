import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:gun_book/data/database_helper.dart';
import 'package:gun_book/data/import_journal.dart';
import 'package:gun_book/data/import_service.dart';
import 'package:gun_book/models/import_args.dart';
import 'package:gun_book/models/library_item.dart';
import 'support/sqlite_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqliteDatabase sql;
  late DatabaseHelper library;
  late Directory sandbox;
  late Directory books;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('gunbook-safety-test-');
    books = await Directory(p.join(sandbox.path, 'books')).create();
    sql = SqliteDatabase();
    await sql.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.initializeSchemaForTesting(sql);
    library = DatabaseHelper.forTesting(sql, books.path);
  });
  tearDown(() async {
    await sql.close();
    // This directory was created by this test; never a real application path.
    await sandbox.delete(recursive: true);
  });

  Future<MangaBook> addBook(String id, {int pages = 3}) async {
    final dir = await Directory(p.join(books.path, id)).create();
    final paths = <String>[];
    for (var i = 0; i < pages; i++) {
      paths.add(
          (await File(p.join(dir.path, '$i.jpg')).writeAsBytes([i, 1, 2, 3]))
              .path);
    }
    final book =
        MangaBook(id: id, title: id, filePaths: paths, coverPath: paths.first);
    await library.saveBook(book);
    return book;
  }

  test('book summary keeps progress without loading page paths', () async {
    final book = await addBook('summary');
    await library.updateProgress(book.id, 2);
    final summary = await library.getBookSummary(book.id);
    expect(summary.filePaths, isEmpty);
    expect(summary.totalPageCount, 3);
    expect(summary.lastReadPage, 2);
    expect((await library.getBookFull(book.id)).filePaths, book.filePaths);
  });

  test('recent summary skips removed IDs and keeps history order', () async {
    await addBook('first');
    await addBook('second');
    expect(
        (await library.getRecentBookSummary(['missing', 'second', 'first']))!
            .id,
        'second');
    expect(await library.getRecentBookSummary(['missing']), isNull);
  });

  test('page cache invalidates after save, delete and item removal', () async {
    final book = await addBook('cached');
    expect(await library.getBookPages(book.id), book.filePaths);
    final changed = MangaBook(
        id: book.id,
        title: book.title,
        filePaths: book.filePaths.take(2).toList());
    await library.saveBook(changed);
    expect(await library.getBookPages(book.id), changed.filePaths);
    await library.deletePages(book.id, {changed.filePaths.last});
    expect(await library.getBookPages(book.id), [changed.filePaths.first]);
    await library.deleteItem(book.id);
    expect(await library.getBookPages(book.id), isEmpty);
  });

  test('v9 upgrade is additive and preserves existing pages/progress',
      () async {
    final book = await addBook('old');
    await library.updateProgress(book.id, 2);
    await sql.execute('DROP TABLE file_cleanup');
    await DatabaseHelper.initializeSchemaForTesting(sql, oldVersion: 9);
    expect((await library.getBookFull(book.id)).lastReadPage, 2);
    expect(await library.getBookPages(book.id), book.filePaths);
    expect(await sql.query('file_cleanup'), isEmpty);
  });

  test('reject self/nested/invalid folder moves atomically', () async {
    await addBook('a');
    await library.createFolder(MangaFolder(id: 'f', title: 'folder'));
    await library.createFolder(MangaFolder(id: 'g', title: 'other'));
    for (final ids in [
      ['f'],
      ['a', 'f']
    ]) {
      await expectLater(library.moveItems(ids, 'f'), throwsStateError);
    }
    await expectLater(library.moveItems(['f'], 'g'), throwsStateError);
    await expectLater(library.moveItems(['a'], 'missing'), throwsStateError);
    expect(
        (await sql.query('items', where: 'id = ?', whereArgs: ['a']))
            .single['parent_id'],
        isNull);
    await library.moveItems(['a'], 'f');
    expect((await library.fetchFolderBooks(folderId: 'f')).single.id, 'a');
  });

  test('folder creation and merge rollback together for stale IDs', () async {
    await addBook('a');
    await expectLater(
        library.createFolder(MangaFolder(id: 'f', title: 'new'),
            itemIds: ['a', 'missing']),
        throwsStateError);
    expect(
        await sql.query('items', where: 'id = ?', whereArgs: ['f']), isEmpty);
    expect(
        (await sql.query('items', where: 'id = ?', whereArgs: ['a']))
            .single['parent_id'],
        isNull);
  });

  test('failed item deletion commit preserves every file and DB row', () async {
    final book = await addBook('a');
    sql.failCommit = true;
    await expectLater(library.deleteItem(book.id), throwsStateError);
    expect(await library.containsBook(book.id), isTrue);
    expect(await File(book.filePaths.first).exists(), isTrue);
    expect(await sql.query('file_cleanup'), isEmpty);
  });

  test('subtree deletion is atomic and cycle-safe', () async {
    await addBook('a');
    await library
        .createFolder(MangaFolder(id: 'f', title: 'folder'), itemIds: ['a']);
    // Legacy corrupted self-reference must not cause recursion forever.
    await sql.update('items', {'parent_id': 'f'},
        where: 'id = ?', whereArgs: ['f']);
    await library.deleteItem('f');
    expect(await sql.query('items'), isEmpty);
    expect(await sql.query('pages'), isEmpty);
    expect(await Directory(p.join(books.path, 'a')).exists(), isFalse);
  });

  test('failed page deletion commit preserves files and progress', () async {
    final book = await addBook('a');
    await library.updateProgress('a', 2);
    sql.failCommit = true;
    await expectLater(
        library.deletePages('a', {book.filePaths[0]}), throwsStateError);
    expect(await File(book.filePaths[0]).exists(), isTrue);
    expect((await library.getBookFull('a')).lastReadPage, 2);
    expect(await library.getBookPages('a'), book.filePaths);
  });

  test('page deletion preserves the current content and fixes count/cover',
      () async {
    final book = await addBook('a');
    await library.updateProgress('a', 2);
    final updated = await library.deletePages('a', {book.filePaths[0]});
    expect(updated.filePaths[updated.lastReadPage], book.filePaths[2]);
    expect(updated.totalPageCount, 2);
    expect(updated.coverPath, book.filePaths[1]);
    final empty = await library.deletePages('a', updated.filePaths.toSet());
    expect(empty.lastReadPage, 0);
    expect(empty.totalPageCount, 0);
    expect(empty.coverPath, isNull);
    await library.updateProgress('a', 100);
    expect((await library.getBookFull('a')).lastReadPage, 0);
  });

  test('cleanup failure remains durable and retries after reopen', () async {
    final book = await addBook('a');
    final path = book.filePaths[0];
    await File(path).delete();
    // A file path that became a directory cannot be safely deleted as a file.
    await Directory(path).create();
    await library.deletePages('a', {path});
    expect((await sql.query('file_cleanup')).single['path'], path);
    await Directory(path).delete();
    await File(path).writeAsString('retry');
    final reopened = DatabaseHelper.forTesting(sql, books.path);
    await reopened.retryFileCleanup();
    expect(await File(path).exists(), isFalse);
    expect(await sql.query('file_cleanup'), isEmpty);
  });

  test('external legacy page sources are never deleted', () async {
    final external = await File(p.join(sandbox.path, 'source.jpg'))
        .writeAsString('original');
    await library.saveBook(
        MangaBook(id: 'legacy', title: 'legacy', filePaths: [external.path]));
    await library.deletePages('legacy', {external.path});
    expect(await external.readAsString(), 'original');
    await library.deleteItem('legacy');
    expect(await external.exists(), isTrue);
  });

  test(
      'cleanup query failure cannot turn a committed edit into a fake rollback',
      () async {
    final book = await addBook('a');
    sql.beforeStatement = (statement) async {
      if (statement.contains('FROM file_cleanup')) {
        throw StateError('cleanup temporarily unavailable');
      }
    };
    final updated = await library.deletePages('a', {book.filePaths.first});
    expect(updated.totalPageCount, 2);
    expect(await File(book.filePaths.first).exists(), isTrue);
    sql.beforeStatement = null;
    await library.retryFileCleanup();
    expect(await File(book.filePaths.first).exists(), isFalse);
  });

  test('update futures and notifications wait for the actual SQLite write',
      () async {
    await addBook('a');
    final gate = Completer<void>();
    sql.beforeStatement = (statement) async {
      if (statement.startsWith('UPDATE items SET title')) await gate.future;
    };
    var completed = false;
    var notified = false;
    final subscription =
        library.onDatabaseChanged.listen((_) => notified = true);
    final operation =
        library.updateTitle('a', 'renamed').then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(notified, isFalse);
    gate.complete();
    await operation;
    await Future<void>.delayed(Duration.zero);
    expect(notified, isTrue);
    expect((await library.getBookFull('a')).title, 'renamed');
    await subscription.cancel();
    sql.beforeStatement = (statement) async {
      if (statement.startsWith('UPDATE'))
        throw StateError('injected write failure');
    };
    await expectLater(library.updateCover('a', 'x'), throwsStateError);
    await expectLater(library.updateFolderCovers('a', ['x']), throwsStateError);
    await expectLater(library.updateProgress('a', 1), throwsStateError);
  });

  Future<Directory> source() async {
    final directory = await Directory(p.join(sandbox.path, 'source')).create();
    await File(p.join(directory.path, '10.jpg')).writeAsBytes([10, 20, 30]);
    await File(p.join(directory.path, '2.jpg')).writeAsBytes([2, 3, 4]);
    return directory;
  }

  Future<List<MangaBook>> import(Directory from, CancelToken cancel,
      {Future<void> Function(File, String)? copy}) async {
    final text = ValueNotifier<String>('');
    final value = ValueNotifier<double>(0);
    try {
      return await ImportService.importBooks(
          ImportArgs(from.path, books.path), text, cancel,
          progressValue: value, database: library, copyFile: copy);
    } finally {
      text.dispose();
      value.dispose();
    }
  }

  Future<void> expectNoImportedDirectories() async {
    expect(
        (await books.list().toList())
            .whereType<Directory>()
            .where((d) => !p.basename(d.path).startsWith('.')),
        isEmpty);
    expect(await sql.query('items'), isEmpty);
  }

  test('copy failure cannot commit a partial book or leave owned directories',
      () async {
    final from = await source();
    var count = 0;
    await expectLater(
        import(from, CancelToken(), copy: (file, target) async {
          if (++count == 2) throw const FileSystemException('disk full');
          await file.copy(target);
        }),
        throwsA(isA<FileSystemException>()));
    await expectNoImportedDirectories();
    expect(await File(p.join(from.path, '10.jpg')).readAsBytes(), [10, 20, 30]);
  });

  test('cancel during copy rolls back the complete import session', () async {
    final cancel = CancelToken();
    await expectLater(
        import(await source(), cancel, copy: (file, target) async {
          await file.copy(target);
          cancel.cancel();
        }),
        throwsA(isA<ImportCancelled>()));
    await expectNoImportedDirectories();
  });

  test('retry after failure/cancellation preserves an existing library',
      () async {
    final existing = await addBook('existing');
    final before = await File(existing.filePaths.first).readAsBytes();
    final from = await source();
    await expectLater(
        import(from, CancelToken(), copy: (_, __) async {
          throw const FileSystemException('disk full');
        }),
        throwsA(isA<FileSystemException>()));
    final cancel = CancelToken();
    await expectLater(
        import(from, cancel, copy: (file, target) async {
          await file.copy(target);
          cancel.cancel();
        }),
        throwsA(isA<ImportCancelled>()));
    final retried = await import(from, CancelToken());
    expect(retried.single.filePaths, hasLength(2));
    expect(await library.getBookPages(existing.id), existing.filePaths);
    expect(await File(existing.filePaths.first).readAsBytes(), before);
  });

  test('commit failure after copies cleans uncommitted files', () async {
    sql.failCommit = true;
    await expectLater(import(await source(), CancelToken()), throwsStateError);
    await expectNoImportedDirectories();
  });

  test('cancellation inside a multi-batch DB transaction rolls back all rows',
      () async {
    final cancel = CancelToken();
    final book = MangaBook(
        id: 'bulk',
        title: 'bulk',
        filePaths: List.generate(600, (i) => '/fixture/$i.jpg'));
    var inserts = 0;
    sql.beforeStatement = (statement) async {
      if (statement.startsWith('INSERT INTO pages') && ++inserts == 270)
        cancel.cancel();
    };
    await expectLater(library.saveBooksBatch([book], cancelToken: cancel),
        throwsA(isA<ImportCancelled>()));
    expect(await sql.query('items'), isEmpty);
    expect(await sql.query('pages'), isEmpty);
  });

  test('successful import preserves bytes and natural page order', () async {
    final result = await import(await source(), CancelToken());
    expect(result, hasLength(1));
    expect(await File(result.single.filePaths[0]).readAsBytes(), [2, 3, 4]);
    expect(await File(result.single.filePaths[1]).readAsBytes(), [10, 20, 30]);
    expect(
        await library.getBookPages(result.single.id), result.single.filePaths);
    expect(
        await Directory(p.join(books.path, '.imports')).list().isEmpty, isTrue);
  });

  test('recovery removes only journal-owned uncommitted books', () async {
    const committed = '00000000-0000-4000-8000-000000000001';
    const abandoned = '00000000-0000-4000-8000-000000000002';
    await addBook(committed);
    final session = Directory(p.join(books.path, '.imports', 'session'));
    await ImportJournal.record(session, committed);
    await ImportJournal.record(session, abandoned);
    await Directory(p.join(books.path, abandoned)).create();
    final unknown =
        await Directory(p.join(books.path, 'old-untracked')).create();
    await ImportJournal.recover(books, (id) => library.containsBook(id),
        skipSessions: {'session'});
    expect(await Directory(p.join(books.path, abandoned)).exists(), isTrue);
    await ImportJournal.recover(books, (id) => library.containsBook(id));
    expect(await Directory(p.join(books.path, committed)).exists(), isTrue);
    expect(await Directory(p.join(books.path, abandoned)).exists(), isFalse);
    expect(await unknown.exists(), isTrue);
    expect(await session.exists(), isFalse);
  });

  test(
      'SAF URI stays opaque and DB commit happens only after native completion',
      () async {
    const uri = 'content://test.documents/tree/opaque%3Aprovider-id';
    final calls = <MethodCall>[];
    final terminal = Completer<List<Map<String, Object>>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ImportService.channel, (call) async {
      calls.add(call);
      if (call.method == 'importTree') {
        expect((call.arguments as Map)['uri'], uri);
        return terminal.future;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ImportService.channel, null));
    final cancel = CancelToken();
    final text = ValueNotifier<String>('');
    final operation = ImportService.importBooks(
        ImportArgs(uri, books.path), text, cancel,
        database: library);
    while (!calls.any((c) => c.method == 'importTree')) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    cancel.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(calls.any((c) => c.method == 'cancelImport'), isTrue);
    expect(await sql.query('items'), isEmpty);
    terminal.complete([]);
    await expectLater(operation, throwsA(isA<ImportCancelled>()));
    expect(calls.last.method, 'releaseDirectory');
    text.dispose();
  });
}
