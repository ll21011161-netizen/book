import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/data/page_path_cache.dart';

void main() {
  test(
      'deduplicates reads, protects cached list and invalidates in-flight reads',
      () async {
    final cache = PagePathCache();
    var calls = 0;
    final pending = Completer<List<String>>();
    Future<List<String>> load() {
      calls++;
      return pending.future;
    }

    final first = cache.get('book', load);
    final second = cache.get('book', load);
    pending.complete(['one']);
    (await first).clear();
    expect(await second, ['one']);
    expect(await cache.get('book', load), ['one']);
    expect(calls, 1);
    cache.clear();
    final stale = Completer<List<String>>();
    final old = cache.get('book', () => stale.future);
    cache.clear();
    expect(await cache.get('book', () async => ['new']), ['new']);
    stale.complete(['stale']);
    expect(await old, ['stale']);
    expect(await cache.get('book', load), ['new']);
  });
  test('bounded LRU and failed-query retry', () async {
    final cache = PagePathCache(maxBooks: 1, maxPaths: 2);
    var calls = 0;
    Future<List<String>> load() async {
      calls++;
      return ['page'];
    }

    await cache.get('a', load);
    await cache.get('b', load);
    await cache.get('a', load);
    expect(calls, 3);
    await expectLater(cache.get('bad', () async => throw StateError('sqlite')),
        throwsStateError);
    expect(await cache.get('bad', load), ['page']);
  });
}
