import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/library_item.dart';
import '../core/perf_log.dart';
import '../models/import_args.dart';
import 'database_helper.dart';
import 'file_scanner.dart';
import 'import_journal.dart';

class ImportService {
  static const channel = MethodChannel('com.gunbook.storage');
  static bool _busy = false;

  static Future<String?> pickDirectory() =>
      channel.invokeMethod<String>('pickDirectory');

  static Future<List<MangaBook>> importBooks(
    ImportArgs args,
    ValueNotifier<String> progressText,
    CancelToken cancelToken, {
    ValueNotifier<double>? progressValue,
    DatabaseHelper? database,
    Future<void> Function(File source, String target)? copyFile,
  }) async {
    if (_busy) throw StateError('已有匯入作業進行中');
    _busy = true;
    final totalWatch = Stopwatch()..start();
    var outcome = 'failed';
    final db = database ?? DatabaseHelper.instance;
    final root = Directory(args.appBooksPath);
    final session = Directory(p.join(root.path, '.imports', const Uuid().v4()));
    final sessionId = p.basename(session.path);
    Timer? cancelTimer;
    var nativeRunning = false;
    var cancelSent = false;
    var journalReady = false;
    try {
      await db.database;
      if (p.normalize(p.absolute((await db.booksRoot).path)) !=
          p.normalize(p.absolute(root.path))) {
        throw StateError('匯入位置不符合書庫儲存位置');
      }
      await root.create(recursive: true);
      await File(p.join(root.path, '.nomedia')).writeAsString('', flush: true);
      final active = Platform.isAndroid
          ? (await channel.invokeListMethod<String>('activeImportSessions'))!
              .toSet()
          : <String>{};
      if (active.isNotEmpty) throw StateError('前一次匯入仍在停止中，請稍後再試');
      await ImportJournal.recover(root, (id) => db.containsBook(id));
      await session.create(recursive: true);
      journalReady = true;
      cancelToken.throwIfCancelled();
      List<MangaBook> books;
      if (args.sourcePath.startsWith('content://')) {
        ImportService.channel.setMethodCallHandler((call) async {
          if (call.method != 'progress') return;
          final data = Map<Object?, Object?>.from(call.arguments as Map);
          if (data['sessionId'] != sessionId) return;
          progressText.value = data['text'] as String;
          progressValue?.value = (data['value'] as num).toDouble();
        });
        cancelTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
          if (cancelToken.isCancelled && nativeRunning && !cancelSent) {
            cancelSent = true;
            // The worker must acknowledge termination before cleanup can run.
            unawaited(channel.invokeMethod<void>('cancelImport', {
              'sessionId': sessionId,
            }).catchError((Object error) {
              cancelSent = false;
              debugPrint('Cancel request will retry: $error');
            }));
          }
        });
        nativeRunning = true;
        List<dynamic>? raw;
        try {
          raw = await channel.invokeMethod<List<dynamic>>('importTree', {
            'uri': args.sourcePath,
            'booksRoot': root.path,
            'sessionId': sessionId,
            'perf': PerfLog.enabled,
          });
        } on PlatformException catch (error) {
          if (error.code == 'CANCELLED') throw const ImportCancelled();
          rethrow;
        } finally {
          nativeRunning = false;
        }
        books = (raw ?? const []).map((value) {
          final book = Map<Object?, Object?>.from(value as Map);
          return MangaBook(
              id: book['id'] as String,
              title: book['title'] as String,
              coverPath: book['coverPath'] as String,
              filePaths: List<String>.from(book['filePaths'] as List));
        }).toList();
      } else {
        books = await _copyLocal(
            args, session, progressText, progressValue, cancelToken, copyFile);
      }
      cancelToken.throwIfCancelled();
      if (books.isEmpty) throw StateError('所選資料夾沒有支援的圖片');
      progressText.value = '儲存資料中…';
      // The entire session commits atomically, using bounded batches inside it.
      final dbWatch = Stopwatch()..start();
      await db.saveBooksBatch(books, cancelToken: cancelToken);
      PerfLog.event('import_database', {
        'elapsed_ms': dbWatch.elapsedMilliseconds,
        'books': books.length,
        'pages': books.fold<int>(0, (n, b) => n + b.filePaths.length)
      });
      progressValue?.value = 1;
      outcome = 'success';
      return books;
    } finally {
      cancelTimer?.cancel();
      if (args.sourcePath.startsWith('content://')) {
        channel.setMethodCallHandler(null);
        try {
          await channel
              .invokeMethod<void>('releaseDirectory', {'uri': args.sourcePath});
        } catch (error) {
          debugPrint('Directory grant release deferred: $error');
        }
      }
      try {
        // A committed book is always preserved, even if cancellation arrived
        // immediately after commit. Failed cleanup retains ownership markers.
        if (journalReady) {
          await ImportJournal.recover(root, (id) => db.containsBook(id),
              onlySession: session);
        }
      } catch (error) {
        debugPrint('Import recovery pending until next open: $error');
      } finally {
        _busy = false;
        PerfLog.event('import_total', {
          'elapsed_ms': totalWatch.elapsedMilliseconds,
          'outcome': cancelToken.isCancelled && outcome != 'success'
              ? 'cancelled'
              : outcome
        });
      }
    }
  }

  static Future<List<MangaBook>> _copyLocal(
    ImportArgs args,
    Directory session,
    ValueNotifier<String> text,
    ValueNotifier<double>? value,
    CancelToken cancel,
    Future<void> Function(File, String)? copyFile,
  ) async {
    text.value = '掃描圖片中…';
    final sourcePath = args.sourcePath;
    final scanWatch = Stopwatch()..start();
    final folders = await compute(_scanLocal, sourcePath);
    PerfLog.event('import_scan_local', {
      'elapsed_ms': scanWatch.elapsedMilliseconds,
      'folders': folders.length,
      'pages': folders.values.fold<int>(0, (n, p) => n + p.length)
    });
    final copyWatch = Stopwatch()..start();
    var totalBytes = 0;
    cancel.throwIfCancelled();
    final books = <MangaBook>[];
    var completed = 0;
    final progressWatch = Stopwatch()..start();
    final count = folders.values.fold<int>(0, (n, paths) => n + paths.length);
    for (final entry in folders.entries) {
      final id = const Uuid().v4();
      await ImportJournal.record(session, id);
      final target = Directory(p.join(args.appBooksPath, id));
      await target.create();
      final paths = <String>[];
      for (var i = 0; i < entry.value.length; i++) {
        cancel.throwIfCancelled();
        final source = File(entry.value[i]);
        final destination = p.join(target.path, p.basename(source.path));
        final expected = await source.length();
        totalBytes += expected;
        if (expected == 0) throw FileSystemException('圖片是空檔案', source.path);
        try {
          if (copyFile == null) {
            await source.copy(destination);
          } else {
            await copyFile(source, destination);
          }
          if (await File(destination).length() != expected) {
            throw FileSystemException('複製大小不符', source.path);
          }
        } catch (error) {
          throw FileSystemException('圖片複製失敗，這次匯入未提交：$error', source.path);
        }
        cancel.throwIfCancelled();
        paths.add(destination);
        completed++;
        if (progressWatch.elapsedMilliseconds >= 100 || completed == count) {
          text.value = '複製中：${p.basename(entry.key)} ($completed/$count)';
          value?.value = count == 0 ? 0 : completed / count;
          progressWatch.reset();
        }
      }
      books.add(MangaBook(
          id: id,
          title: p.basename(entry.key),
          filePaths: paths,
          coverPath: paths.first));
    }
    PerfLog.event('import_copy_local', {
      'elapsed_ms': copyWatch.elapsedMilliseconds,
      'bytes': totalBytes,
      'pages': completed,
      'mib_per_second': copyWatch.elapsedMicroseconds == 0
          ? 0
          : totalBytes * 1000000 / copyWatch.elapsedMicroseconds / (1024 * 1024)
    });
    return books;
  }
}

Map<String, List<String>> _scanLocal(String source) {
  final grouped = <String, List<String>>{};
  final pending = <Directory>[Directory(source)];
  while (pending.isNotEmpty) {
    final directory = pending.removeLast();
    for (final entity in directory.listSync(followLinks: false)) {
      if (p.basename(entity.path).startsWith('.')) continue;
      if (entity is Directory) {
        pending.add(entity);
      } else if (entity is File &&
          const {
            '.jpg',
            '.jpeg',
            '.png',
            '.webp',
            '.bmp',
            '.gif',
            '.heic',
            '.jfif',
          }.contains(p.extension(entity.path).toLowerCase())) {
        grouped.putIfAbsent(directory.path, () => []).add(entity.path);
      }
    }
  }
  final keys = grouped.keys.toList()..sort(FileScanner.compareNatural);
  return {
    for (final key in keys) key: grouped[key]!..sort(FileScanner.compareNatural)
  };
}
