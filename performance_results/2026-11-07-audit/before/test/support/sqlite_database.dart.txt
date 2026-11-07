// Test-only adapter: runs the production SQL against the OS SQLite engine.
// No new package dependency and no access to the application's database path.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
// Reuse the pinned sqflite SQL builder rather than implementing SQL in a fake.
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:sqflite_common/src/sql_builder.dart' show SqlBuilder;

class SqliteDatabase implements Database, Transaction {
  SqliteDatabase() {
    final output = allocate(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
    final name = string(':memory:');
    try {
      if (open(name, output) != 0) throw StateError('Cannot open test SQLite');
      handle = output.value;
    } finally {
      free(name.cast());
      free(output.cast());
    }
  }
  static final library = DynamicLibrary.open(Platform.isWindows
      ? 'winsqlite3.dll'
      : Platform.isMacOS
          ? '/usr/lib/libsqlite3.dylib'
          : 'libsqlite3.so.0');
  static final allocate = library.lookupFunction<Pointer<Void> Function(Int32),
      Pointer<Void> Function(int)>('sqlite3_malloc');
  static final free = library.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('sqlite3_free');
  static final open = library.lookupFunction<
      Int32 Function(Pointer<Uint8>, Pointer<Pointer<Void>>),
      int Function(Pointer<Uint8>, Pointer<Pointer<Void>>)>('sqlite3_open');
  static final shutdown = library.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('sqlite3_close');
  static final prepare = library.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32,
          Pointer<Pointer<Void>>, Pointer<Pointer<Uint8>>),
      int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Pointer<Void>>,
          Pointer<Pointer<Uint8>>)>('sqlite3_prepare_v2');
  static final step = library.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('sqlite3_step');
  static final finalize = library.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('sqlite3_finalize');
  static final bindNull = library.lookupFunction<
      Int32 Function(Pointer<Void>, Int32),
      int Function(Pointer<Void>, int)>('sqlite3_bind_null');
  static final bindInt = library.lookupFunction<
      Int32 Function(Pointer<Void>, Int32, Int64),
      int Function(Pointer<Void>, int, int)>('sqlite3_bind_int64');
  static final bindText = library.lookupFunction<
      Int32 Function(
          Pointer<Void>, Int32, Pointer<Uint8>, Int32, Pointer<Void>),
      int Function(Pointer<Void>, int, Pointer<Uint8>, int,
          Pointer<Void>)>('sqlite3_bind_text');
  static final columnCount = library.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('sqlite3_column_count');
  static final columnName = library.lookupFunction<
      Pointer<Uint8> Function(Pointer<Void>, Int32),
      Pointer<Uint8> Function(Pointer<Void>, int)>('sqlite3_column_name');
  static final columnType = library.lookupFunction<
      Int32 Function(Pointer<Void>, Int32),
      int Function(Pointer<Void>, int)>('sqlite3_column_type');
  static final columnInt = library.lookupFunction<
      Int64 Function(Pointer<Void>, Int32),
      int Function(Pointer<Void>, int)>('sqlite3_column_int64');
  static final columnText = library.lookupFunction<
      Pointer<Uint8> Function(Pointer<Void>, Int32),
      Pointer<Uint8> Function(Pointer<Void>, int)>('sqlite3_column_text');
  static final errorText = library.lookupFunction<
      Pointer<Uint8> Function(Pointer<Void>),
      Pointer<Uint8> Function(Pointer<Void>)>('sqlite3_errmsg');
  static final lastId = library.lookupFunction<Int64 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('sqlite3_last_insert_rowid');
  static final changed = library.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('sqlite3_changes');
  static Pointer<Uint8> string(String value) {
    final bytes = utf8.encode(value);
    final result = allocate(bytes.length + 1).cast<Uint8>();
    result.asTypedList(bytes.length + 1).setAll(0, [...bytes, 0]);
    return result;
  }

  static String read(Pointer<Uint8> pointer) {
    if (pointer == nullptr) return '';
    var length = 0;
    while (pointer[length] != 0) {
      length++;
    }
    return utf8.decode(pointer.asTypedList(length));
  }

  late Pointer<Void> handle;
  Future<void> Function(String sql)? beforeStatement;
  bool failCommit = false;
  @override
  bool isOpen = true;
  @override
  String get path => ':memory:';
  @override
  Database get database => this;

  Future<List<Map<String, Object?>>> run(String sql,
      [List<Object?>? args]) async {
    await beforeStatement?.call(sql);
    if (sql == 'COMMIT' && failCommit)
      throw StateError('Injected commit failure');
    final text = string(sql);
    final out = allocate(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
    Pointer<Void> statement = nullptr;
    final strings = <Pointer<Uint8>>[];
    try {
      if (prepare(handle, text, -1, out, nullptr) != 0)
        throw StateError(read(errorText(handle)));
      statement = out.value;
      for (var i = 0; i < (args?.length ?? 0); i++) {
        final value = args![i];
        if (value == null) {
          bindNull(statement, i + 1);
        } else if (value is int) {
          bindInt(statement, i + 1, value);
        } else if (value is String) {
          final bytes = string(value);
          strings.add(bytes);
          bindText(statement, i + 1, bytes, -1, nullptr);
        } else {
          throw UnsupportedError('Unsupported test binding: $value');
        }
      }
      final rows = <Map<String, Object?>>[];
      while (true) {
        final code = step(statement);
        if (code == 101) break;
        if (code != 100) throw StateError('${read(errorText(handle))}: $sql');
        final row = <String, Object?>{};
        for (var i = 0; i < columnCount(statement); i++) {
          row[read(columnName(statement, i))] =
              switch (columnType(statement, i)) {
            1 => columnInt(statement, i),
            3 => read(columnText(statement, i)),
            5 => null,
            _ => throw UnsupportedError('Unsupported test result'),
          };
        }
        rows.add(row);
      }
      return rows;
    } finally {
      if (statement != nullptr) finalize(statement);
      for (final pointer in strings) {
        free(pointer.cast());
      }
      free(text.cast());
      free(out.cast());
    }
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    await run(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
          [List<Object?>? arguments]) =>
      run(sql, arguments);
  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    await run(sql, arguments);
    return lastId(handle);
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    await run(sql, arguments);
    return changed(handle);
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) =>
      rawUpdate(sql, arguments);
  @override
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) {
    final query = SqlBuilder.insert(table, values,
        nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);
    return rawInsert(query.sql, query.arguments);
  }

  @override
  Future<int> update(String table, Map<String, Object?> values,
      {String? where,
      List<Object?>? whereArgs,
      ConflictAlgorithm? conflictAlgorithm}) {
    final query = SqlBuilder.update(table, values,
        where: where,
        whereArgs: whereArgs,
        conflictAlgorithm: conflictAlgorithm);
    return rawUpdate(query.sql, query.arguments);
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) {
    final query = SqlBuilder.delete(table, where: where, whereArgs: whereArgs);
    return rawDelete(query.sql, query.arguments);
  }

  @override
  Future<List<Map<String, Object?>>> query(String table,
      {bool? distinct,
      List<String>? columns,
      String? where,
      List<Object?>? whereArgs,
      String? groupBy,
      String? having,
      String? orderBy,
      int? limit,
      int? offset}) {
    final query = SqlBuilder.query(table,
        distinct: distinct,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy,
        having: having,
        orderBy: orderBy,
        limit: limit,
        offset: offset);
    return rawQuery(query.sql, query.arguments);
  }

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action,
      {bool? exclusive}) async {
    await execute('BEGIN');
    try {
      final result = await action(this);
      await execute('COMMIT');
      return result;
    } catch (_) {
      await execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Batch batch() => _Batch(this);
  @override
  Future<void> close() async {
    shutdown(handle);
    isOpen = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Batch implements Batch {
  _Batch(this.db);
  final SqliteDatabase db;
  final operations = <Future<void> Function()>[];
  @override
  void insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) {
    operations.add(() async {
      await db.insert(table, values,
          nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);
    });
  }

  @override
  Future<List<Object?>> commit(
      {bool? exclusive, bool? noResult, bool? continueOnError}) async {
    for (final operation in operations) {
      await operation();
    }
    operations.clear();
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
