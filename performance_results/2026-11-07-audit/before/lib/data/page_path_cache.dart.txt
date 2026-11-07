/// Bounded in-process cache. Mutations invalidate both cached and in-flight
/// entries; an older read may finish for its caller but cannot repopulate cache.
class PagePathCache {
  PagePathCache({this.maxBooks = 20, this.maxPaths = 20000});
  final int maxBooks;
  final int maxPaths;
  final Map<String, List<String>> _entries = {};
  final Map<String, Future<List<String>>> _pending = {};
  int _revision = 0;
  int _paths = 0;

  void clear() {
    _revision++;
    _entries.clear();
    _pending.clear();
    _paths = 0;
  }

  Future<List<String>> get(
      String id, Future<List<String>> Function() load) async {
    final hit = _entries.remove(id);
    if (hit != null) {
      _entries[id] = hit;
      return List.of(hit);
    }
    final revision = _revision;
    final request = _pending[id] ??= Future.sync(load);
    try {
      final paths = await request;
      if (revision == _revision && identical(_pending[id], request)) {
        if (paths.length <= maxPaths && maxBooks > 0) {
          while (_entries.isNotEmpty &&
              (_entries.length >= maxBooks ||
                  _paths + paths.length > maxPaths)) {
            _paths -= _entries.remove(_entries.keys.first)!.length;
          }
          _entries[id] = List.unmodifiable(paths);
          _paths += paths.length;
        }
      }
      return List.of(paths);
    } finally {
      if (identical(_pending[id], request)) _pending.remove(id);
    }
  }
}
