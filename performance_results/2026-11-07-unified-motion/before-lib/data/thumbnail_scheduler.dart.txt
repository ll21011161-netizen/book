import 'dart:async';

/// Priority is evaluated at dequeue time, allowing scrolling to promote work.
class ThumbnailScheduler {
  ThumbnailScheduler({this.maxConcurrent = 1}) {
    if (maxConcurrent < 1 || maxConcurrent > 2) {
      throw RangeError.range(maxConcurrent, 1, 2, 'maxConcurrent');
    }
  }
  final int maxConcurrent;
  final List<_Work> _queue = [];
  int _running = 0;

  Future<String?> run(Future<String?> Function() operation,
      {required bool Function() isNeeded, required int Function() priority}) {
    final work = _Work(operation, isNeeded, priority);
    _queue.add(work);
    _pump();
    return work.result.future;
  }

  void _pump() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      for (final work in _queue.toList()) {
        if (!work.isNeeded()) {
          _queue.remove(work);
          work.result.complete(null);
        }
      }
      if (_queue.isEmpty) return;
      var next = _queue.first;
      for (final work in _queue.skip(1)) {
        if (work.priority() < next.priority()) next = work;
      }
      _queue.remove(next);
      _running++;
      unawaited(_execute(next));
    }
  }

  Future<void> _execute(_Work work) async {
    try {
      work.result.complete(await work.operation());
    } catch (_) {
      work.result.complete(null);
    } finally {
      _running--;
      _pump();
    }
  }
}

class _Work {
  _Work(this.operation, this.isNeeded, this.priority);
  final Future<String?> Function() operation;
  final bool Function() isNeeded;
  final int Function() priority;
  final result = Completer<String?>();
}
