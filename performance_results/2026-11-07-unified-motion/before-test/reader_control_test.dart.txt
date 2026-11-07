import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/data/latest_task.dart';
import 'package:gun_book/data/reading_progress.dart';
import 'package:gun_book/data/reader_image.dart';

void main() {
  test('actual image work is serial and an error does not block later images',
      () async {
    final queue = SerialImageWork();
    final gate = Completer<void>();
    final started = <int>[];
    final first = queue.run(() async {
      started.add(1);
      await gate.future;
    });
    final second = queue.run<void>(() async {
      started.add(2);
      throw StateError('bad image');
    });
    final failure = expectLater(second, throwsStateError);
    final third = queue.run(() async {
      started.add(3);
    });
    await Future<void>.delayed(Duration.zero);
    expect(started, [1]);
    gate.complete();
    await first;
    await failure;
    await third;
    expect(started, [1, 2, 3]);
  });
  test('page bounds and stable page selection after deletion', () {
    expect(validPage(99, 3), 2);
    expect(validPage(-1, 3), 0);
    expect(validPage(50, 0), 0);
    expect(pageAfterRemoval(['a', 'b', 'c'], ['b', 'c'], 2), 1);
    expect(pageAfterRemoval(['a', 'b', 'c'], ['a', 'c'], 1), 1);
    expect(pageAfterRemoval(['a', 'b', 'c'], ['a'], 2), 0);
    expect(pageAfterRemoval(['a'], [], 0), 0);
  });
  testWidgets('rapid requests replace queued prefetch without parallel decodes',
      (tester) async {
    final first = Completer<void>();
    final started = <int>[];
    var running = 0;
    var peak = 0;
    final worker = LatestTask<int>((target) async {
      started.add(target);
      running++;
      if (running > peak) peak = running;
      if (target == 1) await first.future;
      running--;
    }, delay: const Duration(milliseconds: 10));
    worker.schedule(1);
    await tester.pump(const Duration(milliseconds: 11));
    worker.schedule(2);
    worker.schedule(3);
    await tester.pump(const Duration(milliseconds: 11));
    expect(started, [1]);
    first.complete();
    await tester.pump();
    expect(started, [1, 3]);
    expect(peak, 1);
    worker.schedule(4);
    worker.cancelPending();
    await tester.pump(const Duration(milliseconds: 20));
    expect(started, [1, 3]);
    worker.dispose();
  });
  testWidgets(
      'dispose drops pending decode while allowing in-flight completion',
      (tester) async {
    final gate = Completer<void>();
    final started = <int>[];
    final worker = LatestTask<int>((target) async {
      started.add(target);
      await gate.future;
    }, delay: Duration.zero);
    worker.schedule(1);
    await tester.pump(const Duration(milliseconds: 1));
    worker.schedule(2);
    worker.dispose();
    gate.complete();
    await tester.pump();
    expect(started, [1]);
  });
  testWidgets('progress debounce persists the last page', (tester) async {
    final writes = <int>[];
    final progress = ReadingProgress((page) async => writes.add(page));
    progress.update(1);
    progress.update(2);
    await tester.pump(const Duration(milliseconds: 401));
    expect(writes, [2]);
    await progress.close();
  });
  test('background/exit flush serializes against an in-flight older write',
      () async {
    final gate = Completer<void>();
    final writes = <int>[];
    final progress = ReadingProgress((page) async {
      if (page == 1) await gate.future;
      writes.add(page);
    });
    progress.update(1);
    final old = progress.flush();
    await Future<void>.delayed(Duration.zero);
    progress.update(2);
    final finalWrite = progress.close();
    gate.complete();
    await Future.wait([old, finalWrite]);
    expect(writes, [1, 2]);
    progress.update(99);
    await progress.flush();
    expect(writes, [1, 2]);
  });
  test('failed progress write remains dirty and retries on exit', () async {
    var fail = true;
    final writes = <int>[];
    final progress = ReadingProgress((page) async {
      if (fail) {
        fail = false;
        throw StateError('disk unavailable');
      }
      writes.add(page);
    });
    progress.update(5);
    await expectLater(progress.flush(), throwsStateError);
    await progress.close();
    expect(writes, [5]);
  });
}
