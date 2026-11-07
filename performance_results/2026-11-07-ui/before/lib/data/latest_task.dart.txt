import 'dart:async';

/// One running operation plus one replaceable pending target. Native image
/// decoding already in flight cannot be cancelled safely by Flutter.
class LatestTask<T> {
  LatestTask(this.run, {this.delay = const Duration(milliseconds: 120)});
  final Future<void> Function(T target) run;
  final Duration delay;
  Timer? _timer;
  T? _pending;
  T? _running;
  bool _disposed = false;
  bool _ready = false;

  void schedule(T target) {
    if (_disposed) return;
    _timer?.cancel();
    _ready = false;
    _pending = target == _running ? null : target;
    _timer = Timer(delay, () {
      _ready = true;
      unawaited(_pump());
    });
  }

  Future<void> _pump() async {
    if (_disposed || _running != null || !_ready || _pending == null) return;
    final target = _pending as T;
    _pending = null;
    _running = target;
    try {
      await run(target);
    } finally {
      _running = null;
      if (!_disposed && _pending != null && _ready) unawaited(_pump());
    }
  }

  void cancelPending() {
    _timer?.cancel();
    _pending = null;
    _ready = false;
  }

  void dispose() {
    _disposed = true;
    cancelPending();
  }
}
