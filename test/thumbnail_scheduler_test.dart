import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/data/thumbnail_scheduler.dart';

void main() {
  test(
      'visible work overtakes background; disposed work is skipped; errors recover',
      () async {
    final queue = ThumbnailScheduler();
    final gate = Completer<String?>();
    final order = <String>[];
    Future<String?> enqueue(String name, int priority, {bool needed = true}) =>
        queue.run(() async {
          order.add(name);
          if (name == 'error') throw StateError('decode');
          return name;
        }, isNeeded: () => needed, priority: () => priority);
    final first =
        queue.run(() => gate.future, isNeeded: () => true, priority: () => 0);
    final background = enqueue('background', 2);
    final gone = enqueue('gone', 0, needed: false);
    final visible = enqueue('visible', 0);
    final error = enqueue('error', 1);
    gate.complete('first');
    expect(await first, 'first');
    expect(await visible, 'visible');
    expect(await gone, isNull);
    expect(await error, isNull);
    expect(await background, 'background');
    expect(order, ['visible', 'error', 'background']);
  });

  test('two workers never run more than two jobs', () async {
    final queue = ThumbnailScheduler(maxConcurrent: 2);
    final gates = List.generate(5, (_) => Completer<String?>());
    var running = 0, peak = 0;
    final results = <Future<String?>>[];
    for (var i = 0; i < 5; i++) {
      results.add(queue.run(() async {
        running++;
        if (running > peak) peak = running;
        final result = await gates[i].future;
        running--;
        return result;
      }, isNeeded: () => true, priority: () => 0));
    }
    expect(running, 2);
    for (final gate in gates) {
      gate.complete('ok');
    }
    await Future.wait(results);
    expect(peak, 2);
  });
}
