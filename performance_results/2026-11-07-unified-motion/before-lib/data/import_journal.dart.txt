import 'dart:io';
import 'package:path/path.dart' as p;

/// Only directories created by a recorded import may be reclaimed. Existing
/// books and arbitrary files under booksRoot are never inferred to be orphans.
class ImportJournal {
  static final _id =
      RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$');

  static Future<void> record(Directory session, String bookId) async {
    if (!_id.hasMatch(bookId)) throw ArgumentError.value(bookId);
    await session.create(recursive: true);
    // Persist ownership before creating or copying anything into the book dir.
    await File(p.join(session.path, bookId)).writeAsString('', flush: true);
  }

  static Future<void> recover(
    Directory booksRoot,
    Future<bool> Function(String id) isCommitted, {
    Directory? onlySession,
    Set<String> skipSessions = const {},
  }) async {
    final journalRoot = Directory(p.join(booksRoot.path, '.imports'));
    if (!await journalRoot.exists()) return;
    final sessions = onlySession == null
        ? await journalRoot.list(followLinks: false).toList()
        : <FileSystemEntity>[onlySession];
    for (final session in sessions.whereType<Directory>()) {
      if (skipSessions.contains(p.basename(session.path))) continue;
      if (p.dirname(p.normalize(session.path)) !=
          p.normalize(journalRoot.path)) {
        throw StateError('Invalid import session');
      }
      if (!await session.exists()) continue;
      await for (final marker in session.list(followLinks: false)) {
        final id = p.basename(marker.path);
        if (marker is! File || !_id.hasMatch(id)) continue;
        if (!await isCommitted(id)) {
          final target = Directory(p.join(booksRoot.path, id));
          // Do not follow symlinks, even if a journal has been tampered with.
          final type =
              await FileSystemEntity.type(target.path, followLinks: false);
          if (type == FileSystemEntityType.link) {
            throw FileSystemException(
                'Refusing to clean symbolic link', target.path);
          }
          if (type == FileSystemEntityType.directory) {
            await target.delete(recursive: true);
          }
        }
        await marker.delete();
      }
      if (await session.list().isEmpty) await session.delete();
    }
  }
}
