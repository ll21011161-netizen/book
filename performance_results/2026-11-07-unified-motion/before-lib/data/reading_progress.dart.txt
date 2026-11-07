import 'dart:async';

int validPage(int page, int count) => count == 0 ? 0 : page.clamp(0, count - 1);

int pageAfterRemoval(List<String> before, List<String> after, int oldPage) {
  if (after.isEmpty) return 0;
  final oldIndex = validPage(oldPage, before.length);
  if (before.isNotEmpty) {
    final samePage = after.indexOf(before[oldIndex]);
    if (samePage >= 0) return samePage;
    for (var i = oldIndex + 1; i < before.length; i++) {
      final next = after.indexOf(before[i]);
      if (next >= 0) return next;
    }
  }
  return after.length - 1;
}

/// Writes are serialized; a failed write stays dirty and can be retried.
class ReadingProgress {
  ReadingProgress(this.write, {this.delay = const Duration(milliseconds: 400)});
  final Future<void> Function(int page) write;
  final Duration delay;
  Timer? _timer;
  Future<void> _tail = Future<void>.value();
  int? _latest;
  int? _saved;
  bool _closed = false;
  void Function(Object error)? onError;

  void update(int page) {
    if (_closed) return;
    _latest = page;
    _timer?.cancel();
    _timer = Timer(delay, () {
      unawaited(flush().catchError((Object error) {
        onError?.call(error);
      }));
    });
  }

  Future<void> flush() {
    _timer?.cancel();
    final operation = _tail.then((_) async {
      while (_latest != null && _latest != _saved) {
        final page = _latest!;
        await write(page);
        _saved = page;
      }
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> close() {
    _closed = true;
    return flush();
  }
}
