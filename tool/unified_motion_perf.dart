import 'package:gun_book/core/cover_origin.dart';
// Run only as isolated applicationId .unifiedmotion20261107; synthetic images/in-memory DB.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:gun_book/core/anim_route.dart';
import 'package:gun_book/core/perf_log.dart';
import 'package:gun_book/data/database_helper.dart';
import 'package:gun_book/models/library_item.dart';
import 'package:gun_book/widgets/book_card.dart';
import 'package:gun_book/screens/details/category_detail_screen.dart';

const revision =
    String.fromEnvironment('DETAIL_REVISION', defaultValue: 'unified');
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    PerfLog.event('detail_bench_error', {'error': d.exceptionAsString()});
  };
  runApp(const MaterialApp(home: DetailBench()));
}

class DetailBench extends StatefulWidget {
  const DetailBench({super.key});
  @override
  State<DetailBench> createState() => _DetailBenchState();
}

class _DetailBenchState extends State<DetailBench> {
  MangaBook? book;
  DatabaseHelper? db;
  BuildContext? homeContext;
  final clock = Stopwatch()..start();
  int pointer = 1;
  final ScrollController homeScroll = ScrollController();
  List<Element> elements(bool Function(Widget) matches) {
    final out = <Element>[];
    void visit(Element e) {
      if (matches(e.widget)) out.add(e);
      e.visitChildElements(visit);
    }

    Navigator.of(homeContext!).context.visitChildElements(visit);
    return out;
  }

  Future<void> pause(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));
  @override
  void initState() {
    super.initState();
    unawaited(run());
  }

  Future<void> run() async {
    try {
      final tmp = await getTemporaryDirectory();
      final root = Directory(
          '${tmp.path}/detail-fixtures${const String.fromEnvironment('DETAIL_FIXTURE')}');
      await root.create(recursive: true);
      final paths = <String>[];
      for (var i = 0; i < 104; i++) {
        final f = File('${root.path}/page-$i.png');
        if (!await f.exists()) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawColor(Color(0xffe0d0c0 + i * 17), BlendMode.src);
          for (var j = 0; j < 180; j++) {
            canvas.drawRect(
                Rect.fromLTWH((j * 71 % 2048).toDouble(),
                    (j * 97 % 3072).toDouble(), 120, 170),
                Paint()
                  ..color =
                      Color(0xff000000 | ((j * 7919 + i * 31271) & 0xffffff)));
          }
          final picture = recorder.endRecording();
          final image = await picture.toImage(2048, 3072);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await f.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
          picture.dispose();
        }
        paths.add(f.path);
      }
      final sql = await openDatabase(inMemoryDatabasePath);
      await DatabaseHelper.initializeSchemaForTesting(sql);
      await sql.insert('items', {
        'id': 'fixture',
        'title': 'Synthetic 104 pages',
        'type': 'book',
        'total_pages': 104,
        'cover_path': paths.first
      });
      final batch = sql.batch();
      for (var i = 0; i < paths.length; i++) {
        batch.insert(
            'pages', {'book_id': 'fixture', 'path': paths[i], 'page_order': i});
      }
      await batch.commit(noResult: true);
      db = DatabaseHelper.forTesting(sql, '${root.path}/books');
      setState(() => book = MangaBook(
          id: 'fixture',
          title: 'Synthetic 104 pages',
          filePaths: [],
          coverPath: paths.first,
          totalPageCount: 104));
      await pause(1200);
      if (!mounted) return;
      PerfLog.event('detail_bench_fixture', {
        'revision': revision,
        'pages': 104,
        'width': 2048,
        'height': 3072,
        'refresh_hz': View.of(context).display.refreshRate
      });
      for (var i = 0; i < 11; i++) {
        if (i == 1 || i == 10) {
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
          await pause(300);
        }
        final frames = PerfFrames('detail_${revision}_${i}_enter');
        PerfLog.event('detail_bench_click',
            {'revision': revision, 'run': i, ...PerfLog.memory()});
        final element = elements((w) => w is BookCard).first;
        final box = element.findRenderObject()! as RenderBox;
        final at = box.localToGlobal(box.size.center(Offset.zero));
        GestureBinding.instance.handlePointerEvent(PointerDownEvent(
            pointer: pointer, position: at, timeStamp: clock.elapsed));
        await pause(60);
        GestureBinding.instance.handlePointerEvent(PointerUpEvent(
            pointer: pointer, position: at, timeStamp: clock.elapsed));
        pointer++;
        await pause(i == 2 ? 70 : 550);
        frames.dispose();
        if (i != 2) await pause(1300);
        if (i == 1) {
          final scrolling = PerfFrames('detail_${revision}_scroll');
          final scrollables = elements((w) => w is Scrollable);
          final controller =
              (scrollables.last as StatefulElement).state as ScrollableState;
          for (var j = 0; j < 8; j++) {
            await controller.position.animateTo(
                j.isEven ? controller.position.maxScrollExtent : 0,
                duration: const Duration(milliseconds: 230),
                curve: Curves.linear);
            await pause(100);
          }
          await pause(500);
          scrolling.dispose();
        }
        final back = PerfFrames('detail_${revision}_${i}_return');
        Navigator.of(homeContext!).pop();
        await pause(650);
        back.dispose();
        PerfLog.event('detail_bench_returned', {
          'revision': revision,
          'run': i,
          'home_scroll': homeScroll.offset,
          ...PerfLog.memory()
        });
      }
      await sql.close();
      PerfLog.event('detail_bench_complete', {'revision': revision});
    } catch (e, s) {
      PerfLog.event('detail_bench_failure', {'error': '$e', 'stack': '$s'});
    }
  }

  void open([CoverOrigin? source]) {
    Navigator.of(homeContext!).push(DetailRoute<void>(
        context: homeContext!,
        source: source,
        page: CategoryDetailScreen(
            category: book!, database: db, onUpdate: () {})));
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Builder(builder: (context) {
        homeContext = context;
        return book == null
            ? const Center(child: Text('Preparing isolated 104-page fixture'))
            : ListView(controller: homeScroll, children: [
                const SizedBox(height: 80),
                Center(
                    child: SizedBox(
                        width: 110,
                        height: 210,
                        child: BookCard(
                            book: book!,
                            onTap: open,
                            onOpen: open,
                            onLongPress: () {}))),
                const SizedBox(height: 1200)
              ]);
      }));
  @override
  void dispose() {
    homeScroll.dispose();
    super.dispose();
  }
}
