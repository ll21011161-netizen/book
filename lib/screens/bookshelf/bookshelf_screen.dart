import '../../core/cover_origin.dart';
import '../../core/motion.dart';
import '../../widgets/drag_cover.dart';
// lib/screens/bookshelf/bookshelf_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/bookshelf_header.dart';
import '../reader/manga_reader_screen.dart';

import '../../core/constants.dart';
import '../../core/perf_log.dart';
import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/anim_route.dart';
import '../../data/database_helper.dart';
import '../../models/library_item.dart';
import '../../widgets/book_card.dart';
import '../../widgets/folder_card.dart';
import '../../widgets/smooth_input_dialog.dart';

import '../details/category_detail_screen.dart';
import '../details/folder_detail_screen.dart';
import 'search_delegate.dart';

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({super.key, this.database});
  final DatabaseHelper? database;

  @override
  State<BookshelfScreen> createState() => BookshelfScreenState();
}

class BookshelfScreenState extends State<BookshelfScreen>
    with AutomaticKeepAliveClientMixin {
  DatabaseHelper get _database => widget.database ?? DatabaseHelper.instance;

  @override
  bool get wantKeepAlive => true;

  late final PerfFrames _frames;
  final Stopwatch _firstLoad = Stopwatch();
  bool _firstLoadLogged = false;
  List<LibraryItem> _items = [];
  int _filter = 0;
  List<String> _recentIds = [];
  MangaBook? _recentBook;
  int _recentGeneration = 0;

  Future<void> _loadRecent(int generation) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || generation != _recentGeneration) return;
      final ids = prefs.getStringList('recent_read_book_ids') ?? <String>[];
      MangaBook? book;
      if (ids.isNotEmpty) {
        book = _items
            .whereType<MangaBook>()
            .where((b) => b.id == ids.first)
            .firstOrNull;
        book ??= await _database.getRecentBookSummary(ids);
      }
      if (mounted && generation == _recentGeneration) {
        setState(() {
          _recentIds = ids;
          _recentBook = book;
        });
      }
    } catch (error) {
      // Keep an existing panel during transient preferences/database failures.
      if (mounted && generation == _recentGeneration) {
        context.showSnackBar('最近閱讀載入失敗：$error');
      }
    }
  }

  List<LibraryItem> get _visibleItems {
    switch (_filter) {
      case 1:
        final books = _items
            .whereType<MangaBook>()
            .where((b) => _recentIds.contains(b.id))
            .toList();
        books.sort((a, b) =>
            _recentIds.indexOf(a.id).compareTo(_recentIds.indexOf(b.id)));
        return books;
      case 2:
        return _items.whereType<MangaFolder>().toList();
      case 3:
        return _items
            .whereType<MangaBook>()
            .where((b) => b.readCount == 0)
            .toList();
      default:
        return _items;
    }
  }

  Future<void> _continueReading(MangaBook book) async {
    if (_openingReader) return;
    _openingReader = true;
    try {
      final full = await _database.getBookFull(book.id);
      if (!mounted) return;
      if (full.filePaths.isEmpty) {
        context.showSnackBar('漫畫沒有可閱讀的頁面');
        return;
      }
      await _database.incrementReadCount(book.id);
      if (!mounted) return;
      await Navigator.push(
          context,
          AnimRoute<void>(
              context: context,
              page: MangaReaderScreen(
                  book: full, initialPage: full.lastReadPage)));
      if (mounted) loadData(refresh: true);
    } catch (_) {
      if (mounted) context.showSnackBar('無法開啟漫畫，請稍後重試');
    } finally {
      _openingReader = false;
    }
  }

  final ValueNotifier<bool> _selModeNotifier = ValueNotifier(false);
  final ValueNotifier<Set<String>> _selIdsNotifier = ValueNotifier({});
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _dragTiltNotifier = ValueNotifier(0);
  final Stopwatch _dragClock = Stopwatch();
  int _lastDragMicros = 0;
  double _filteredDragVelocity = 0;
  double _dragTravel = 0;
  bool _dragCancelled = false;

  void _resetDrag() {
    if (!mounted) return;
    _hoverTimer?.cancel();
    _hoverTimer = null;
    _hoverIndexNotifier.value = null;
    _isMergeModeNotifier.value = false;
    _dragTiltNotifier.value = 0;
    _dragClock.stop();
    _lastDragMicros = 0;
    _filteredDragVelocity = 0;
  }

  void _updateDrag(DragUpdateDetails details) {
    if (!mounted || !_dragClock.isRunning) return;
    _dragTravel += details.delta.distance;
    if (MediaQuery.disableAnimationsOf(context)) return;
    final now = _dragClock.elapsedMicroseconds;
    final elapsed = now - _lastDragMicros;
    _lastDragMicros = now;
    if (elapsed <= 0) return;
    final seconds = elapsed / 1000000;
    final velocity = (details.delta.dx / seconds).clamp(-2000.0, 2000.0);
    // Time-based smoothing is independent of the display/pointer frequency.
    final weight = 1 - math.exp(-seconds / 0.055);
    _filteredDragVelocity += (velocity - _filteredDragVelocity) * weight;
    final angle = (_filteredDragVelocity * 0.00004)
        .clamp(-AppConstants.dragMaxTilt, AppConstants.dragMaxTilt);
    // Ignore sub-pixel angular noise; only the feedback listens to this value.
    final quantized = (angle * 1000).round() / 1000;
    if (_dragTiltNotifier.value != quantized)
      _dragTiltNotifier.value = quantized;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.of(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resetDrag();
      });
    }
  }

  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  int _loadGeneration = 0;
  bool _mutationBusy = false;
  bool _openingReader = false;
  final int _limit = 50;
  StreamSubscription? _dbSubscription;
  Timer? _hoverTimer;
  Timer? _refreshTimer;

  final ValueNotifier<int?> _hoverIndexNotifier = ValueNotifier(null);
  final ValueNotifier<bool> _isMergeModeNotifier = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _frames = PerfFrames('bookshelf');
    if (PerfLog.enabled) _firstLoad.start();
    loadData(refresh: true);
    _scrollController.addListener(_onScroll);
    _dbSubscription = _database.onDatabaseChanged.listen((_) {
      _refreshTimer?.cancel();
      _refreshTimer = Timer(const Duration(milliseconds: 40), () {
        if (mounted) loadData(refresh: true);
      });
    });
  }

  @override
  void dispose() {
    _frames.dispose();
    _hoverTimer?.cancel();
    _refreshTimer?.cancel();
    _dbSubscription?.cancel();
    _scrollController.dispose();
    _selModeNotifier.dispose();
    _selIdsNotifier.dispose();
    _dragClock.stop();
    _dragTiltNotifier.dispose();
    _hoverIndexNotifier.dispose();
    _isMergeModeNotifier.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 500 &&
        !_isLoading &&
        _hasMore) {
      loadData();
    }
  }

  Future<void> loadData({bool refresh = false}) async {
    if (!mounted || (_isLoading && !refresh)) return;
    if (refresh) {
      _refreshTimer?.cancel();
      _recentGeneration++;
    }
    final recentGeneration = _recentGeneration;
    final limit = refresh && _offset > _limit ? _offset : _limit;
    final watch = Stopwatch()..start();
    final generation = ++_loadGeneration;
    final offset = refresh ? 0 : _offset;
    setState(() => _isLoading = true);
    try {
      final result = await _database.fetchItems(limit: limit, offset: offset);
      PerfLog.event('bookshelf_query', {
        'elapsed_ms': watch.elapsedMilliseconds,
        'offset': offset,
        'count': result.length
      });
      if (!mounted || generation != _loadGeneration) return;
      if (!_firstLoadLogged) {
        _firstLoadLogged = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            PerfLog.event('bookshelf_first_frame',
                {'elapsed_ms': _firstLoad.elapsedMilliseconds});
          }
        });
      }
      setState(() {
        final byId = {
          for (final item in refresh ? <LibraryItem>[] : _items) item.id: item
        };
        for (final item in result) {
          byId[item.id] = item;
        }
        _items = byId.values.toList();
        _offset = offset + result.length;
        _hasMore = result.length == limit;
        _isLoading = false;
      });
      if (refresh) unawaited(_loadRecent(recentGeneration));
      if (_filter != 0 && _hasMore) loadData();
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _isLoading = false);
      context.showSnackBar('載入失敗：$error');
    }
  }

  void showAdd() {
    showDialog(
        context: context,
        builder: (_) => Dialog(
            shape: AppStyles.dialogShape,
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(AppStrings.get('add_content'), style: AppStyles.title),
                  const SizedBox(height: 20),
                  ListTile(
                      leading: const Icon(Icons.library_add_check),
                      title: Text(AppStrings.get('batch_import')),
                      onTap: () {
                        context.pop();
                        LibraryActions.batchImport(context);
                      }),
                  ListTile(
                      leading: const Icon(Icons.create_new_folder),
                      title: Text(AppStrings.get('create')),
                      onTap: () {
                        context.pop();
                        LibraryActions.createEmptyBook(context);
                      }),
                ]))));
  }

  void _createFolder() async {
    if (_selIdsNotifier.value.isEmpty) return;
    try {
      await LibraryActions.createFolder(
          context, _selIdsNotifier.value.toList(), _endSel);
    } catch (error) {
      if (mounted) context.showSnackBar('建立資料夾失敗：$error');
    }
  }

  void _deleteSel() async {
    final ids = _selIdsNotifier.value.toList();
    if (!await DialogUtils.showConfirm(context,
            title: AppStrings.get('confirm_delete')) ||
        !mounted) return;
    try {
      await _database.deleteItems(ids);
      if (mounted) _endSel();
    } catch (error) {
      if (mounted) context.showSnackBar('刪除失敗，資料未變更：$error');
    }
  }

  void _renameSel() async {
    if (_selIdsNotifier.value.length != 1) return;
    final id = _selIdsNotifier.value.first;
    final item = _items.firstWhere((e) => e.id == id);
    final newName = await DialogUtils.showInput(context,
        title: AppStrings.get('rename'), initial: item.title);
    if (newName.isValid) {
      await _database.updateTitle(id, newName!);
      if (mounted) _endSel();
    }
  }

  void _moveSel() {
    final ids = _selIdsNotifier.value.toList();
    if (_items.any((item) => ids.contains(item.id) && item is MangaFolder)) {
      context.showSnackBar('資料夾不能移入其他資料夾');
      return;
    }
    final folders = _items
        .whereType<MangaFolder>()
        .where((folder) => !ids.contains(folder.id))
        .toList();
    if (folders.isEmpty || ids.isEmpty) return;
    showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(AppStrings.get('move_to')),
              content: SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: folders.length,
                    itemBuilder: (_, i) => ListTile(
                        title: Text(folders[i].title),
                        onTap: () async {
                          if (_mutationBusy) return;
                          _mutationBusy = true;
                          try {
                            await _database.moveItems(ids, folders[i].id);
                            if (dialogContext.mounted)
                              Navigator.pop(dialogContext);
                            if (mounted) _endSel();
                          } catch (error) {
                            if (mounted) context.showSnackBar('移動失敗：$error');
                          } finally {
                            _mutationBusy = false;
                          }
                        }),
                  )),
            ));
  }

  void _endSel() {
    _selModeNotifier.value = false;
    _selIdsNotifier.value = {};
  }

  Future<void> _onReorder(String draggedId, String targetId) async {
    if (_mutationBusy || _selModeNotifier.value) return;
    final oldIndex = _items.indexWhere((item) => item.id == draggedId);
    final newIndex = _items.indexWhere((item) => item.id == targetId);
    if (oldIndex < 0 || newIndex < 0 || oldIndex == newIndex) return;
    _mutationBusy = true;
    final reordered = [..._items];
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    setState(() => _items = reordered);
    try {
      await _database.updateSortOrder(reordered.map((item) => item.id).toList(),
          notify: false);
    } catch (error) {
      if (mounted) {
        context.showSnackBar('排序失敗：$error');
        await loadData(refresh: true);
      }
    } finally {
      _mutationBusy = false;
    }
  }

  Future<void> _mergeItems(String draggedId, String targetId) async {
    if (_mutationBusy) return;
    final dragged = _items.where((item) => item.id == draggedId).firstOrNull;
    final target = _items.where((item) => item.id == targetId).firstOrNull;
    if (dragged is! MangaBook || target == null || draggedId == targetId)
      return;
    _mutationBusy = true;
    try {
      if (target is MangaFolder) {
        await _database.moveItems([draggedId], targetId);
      } else {
        final name = await SmoothInputDialog.show(context,
            title: '建立新資料夾', initialText: '新資料夾');
        if (!mounted || name == null || name.trim().isEmpty) return;
        await _database.createFolder(
            MangaFolder(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                title: name.trim()),
            itemIds: [draggedId, targetId]);
      }
      // Notifications own refresh. Never mutate a replacement list by old index.
      if (mounted) context.showSnackBar('合併完成');
    } catch (error) {
      if (mounted) context.showSnackBar('合併失敗，請重新選取：$error');
    } finally {
      _mutationBusy = false;
    }
  }

  void _tap(LibraryItem item, bool sel, [CoverOrigin? source]) {
    _resetDrag();
    if (_selModeNotifier.value) {
      final current = Set<String>.from(_selIdsNotifier.value);
      if (sel)
        current.remove(item.id);
      else
        current.add(item.id);
      _selIdsNotifier.value = current;
    } else if (item is MangaBook) {
      Navigator.push(
          context,
          DetailRoute(
              source: source,
              context: context,
              page: CategoryDetailScreen(
                  category: item,
                  coverFit: context.read<SettingsProvider>().cropBookCovers
                      ? BoxFit.cover
                      : BoxFit.contain,
                  onUpdate: () => loadData(refresh: true))));
    } else if (item is MangaFolder) {
      Navigator.push(
          context,
          DetailRoute(
              source: source,
              context: context,
              page: FolderDetailScreen(
                  folder: item, onUpdate: () => loadData(refresh: true))));
    }
  }

  void _handleLongPress(LibraryItem item) {
    if (!_selModeNotifier.value) {
      _selModeNotifier.value = true;
      _selIdsNotifier.value = {item.id};
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final visibleItems = _visibleItems;
    final recent = _recentBook;
    final columns = context.select<SettingsProvider, int>(
      (settings) => settings.bookshelfColumns,
    );
    final cropCovers = context.select<SettingsProvider, bool>(
      (settings) => settings.cropBookCovers,
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: ValueListenableBuilder<Set<String>>(
            valueListenable: _selIdsNotifier,
            builder: (context, selIds, _) {
              return ValueListenableBuilder<bool>(
                  valueListenable: _selModeNotifier,
                  builder: (context, selMode, _) {
                    return AnimatedSwitcher(
                        duration: Duration.zero,
                        child: selMode
                            ? Text(
                                "${selIds.length} ${AppStrings.get('selected')}",
                                key: const ValueKey('sel'),
                                style: const TextStyle(fontSize: 18))
                            : const Text("GunBook",
                                key: ValueKey('title'),
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 30)));
                  });
            }),
        actions: [
          ValueListenableBuilder<bool>(
              valueListenable: _selModeNotifier,
              builder: (context, selMode, _) {
                if (!selMode) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: () => showSearch(
                              context: context,
                              delegate:
                                  SearchDel(() => loadData(refresh: true)))),
                      const SizedBox(width: 16),
                      IconButton(
                          icon: const Icon(Icons.checklist),
                          onPressed: () => _selModeNotifier.value = true)
                    ],
                  );
                }
                return ValueListenableBuilder<Set<String>>(
                    valueListenable: _selIdsNotifier,
                    builder: (context, selIds, _) {
                      final allSelected = visibleItems.isNotEmpty &&
                          visibleItems
                              .every((item) => selIds.contains(item.id));
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              icon: Icon(allSelected
                                  ? Icons.deselect
                                  : Icons.select_all),
                              onPressed: () => _selIdsNotifier.value =
                                  allSelected
                                      ? {}
                                      : visibleItems.map((e) => e.id).toSet()),
                          if (selIds.length == 1)
                            IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: _renameSel),
                          IconButton(
                              icon: const Icon(Icons.drive_file_move),
                              onPressed: _moveSel),
                          IconButton(
                              icon: const Icon(Icons.create_new_folder),
                              onPressed: _createFolder),
                          IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: _deleteSel),
                          IconButton(
                              icon: const Icon(Icons.close), onPressed: _endSel)
                        ],
                      );
                    });
              })
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: showAdd,
        icon: const Icon(Icons.add),
        label: const Text("新增漫畫"),
      ),
      body: RefreshIndicator(
          onRefresh: () => loadData(refresh: true),
          child: CustomScrollView(
            controller: _scrollController,
            physics: MotionScope.of(context).scrollPhysics,
            slivers: [
              SliverToBoxAdapter(
                  child: BookshelfHeader(
                recent: recent,
                selectedFilter: _filter,
                onContinue:
                    recent == null ? null : () => _continueReading(recent),
                onFilter: (value) {
                  _endSel();
                  setState(() => _filter = value);
                  if (value != 0 && _hasMore && !_isLoading) loadData();
                },
              )),
              if (visibleItems.isEmpty && !_isLoading)
                SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                        child: Text(
                            _items.isEmpty ? '書架還沒有漫畫，點右下角新增吧' : '沒有符合條件的漫畫')))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        childAspectRatio: 0.52,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 24),
                    itemCount: visibleItems.length + (_isLoading ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == visibleItems.length)
                        return const Center(child: CircularProgressIndicator());

                      final item = visibleItems[i];

                      return ValueListenableBuilder<bool>(
                          valueListenable: _selModeNotifier,
                          builder: (context, selMode, _) {
                            return ValueListenableBuilder<Set<String>>(
                                valueListenable: _selIdsNotifier,
                                builder: (context, selIds, _) {
                                  final sel = selIds.contains(item.id);

                                  Widget buildItem(
                                          {DragVisualMode mode =
                                              DragVisualMode.none}) =>
                                      item is MangaFolder
                                          ? FolderCard(
                                              folder: item,
                                              isSelected: sel,
                                              dragVisualMode: mode,
                                              onTap: () => _tap(item, sel),
                                              onOpen: (origin) =>
                                                  _tap(item, sel, origin),
                                              onLongPress: () =>
                                                  _handleLongPress(item))
                                          : BookCard(
                                              book: item as MangaBook,
                                              cropCover: cropCovers,
                                              isSelected: sel,
                                              dragVisualMode: mode,
                                              onTap: () => _tap(item, sel),
                                              onOpen: (origin) =>
                                                  _tap(item, sel, origin),
                                              onLongPress: () =>
                                                  _handleLongPress(item));

                                  if (selMode || _filter != 0)
                                    return buildItem();

                                  return Listener(onPointerCancel: (_) {
                                    _dragCancelled = true;
                                    _resetDrag();
                                  }, child: LayoutBuilder(
                                      builder: (context, constraints) {
                                    return LongPressDraggable<String>(
                                        data: item.id,
                                        delay:
                                            const Duration(milliseconds: 300),
                                        onDragStarted: () {
                                          _resetDrag();
                                          _dragTravel = 0;
                                          _dragCancelled = false;
                                          _dragClock
                                            ..reset()
                                            ..start();
                                        },
                                        onDragUpdate: _updateDrag,
                                        onDragEnd: (details) {
                                          final select = !details.wasAccepted &&
                                              !_dragCancelled &&
                                              _dragTravel < 12 &&
                                              _dragClock.isRunning &&
                                              ModalRoute.of(context)
                                                      ?.isCurrent ==
                                                  true;
                                          _resetDrag();
                                          // The 300ms draggable wins the child's long-press
                                          // arena. A stationary release still enters multi-select.
                                          if (select) _handleLongPress(item);
                                        },
                                        onDraggableCanceled: (_, __) =>
                                            _resetDrag(),
                                        feedback: Material(
                                            color: Colors.transparent,
                                            elevation: 0,
                                            child: HeroMode(
                                                enabled: false,
                                                child: PhysicsDragFeedback(
                                                  tiltNotifier:
                                                      _dragTiltNotifier,
                                                  child: SizedBox(
                                                      width:
                                                          constraints.maxWidth,
                                                      height:
                                                          constraints.maxHeight,
                                                      child: buildItem()),
                                                ))),
                                        childWhenDragging: Opacity(
                                            opacity: 0.3, child: buildItem()),
                                        child: DragTarget<String>(onWillAccept:
                                            (d) {
                                          if (d != null && d != item.id) {
                                            _hoverTimer?.cancel();
                                            _hoverIndexNotifier.value = i;
                                            _isMergeModeNotifier.value = false;

                                            if (_items.any((candidate) =>
                                                candidate.id == d &&
                                                candidate is MangaBook)) {
                                              _hoverTimer = Timer(
                                                  const Duration(
                                                      milliseconds: 500), () {
                                                if (mounted &&
                                                    _hoverIndexNotifier.value ==
                                                        i) {
                                                  _isMergeModeNotifier.value =
                                                      true;
                                                }
                                              });
                                            }
                                            return true;
                                          }
                                          return false;
                                        }, onLeave: (d) {
                                          if (_hoverIndexNotifier.value == i) {
                                            _hoverTimer?.cancel();
                                            _hoverIndexNotifier.value = null;
                                            _isMergeModeNotifier.value = false;
                                          }
                                        }, onAccept: (dragIndex) {
                                          _hoverTimer?.cancel();
                                          final isMerge = _isMergeModeNotifier
                                                  .value &&
                                              _hoverIndexNotifier.value == i;
                                          _hoverIndexNotifier.value = null;
                                          _isMergeModeNotifier.value = false;

                                          if (_dragCancelled) return;
                                          if (isMerge) {
                                            _mergeItems(dragIndex, item.id);
                                          } else {
                                            _onReorder(dragIndex, item.id);
                                          }
                                        }, builder:
                                            (ctx, candidateData, rejectedData) {
                                          final isHovering =
                                              candidateData.isNotEmpty;
                                          return ValueListenableBuilder<bool>(
                                            // Only the active target subscribes to merge changes.
                                            valueListenable: isHovering
                                                ? _isMergeModeNotifier
                                                : const AlwaysStoppedAnimation(
                                                    false),
                                            builder: (context, isMerge,
                                                    child) =>
                                                buildItem(
                                                    mode: !isHovering
                                                        ? DragVisualMode.none
                                                        : isMerge
                                                            ? DragVisualMode
                                                                .merge
                                                            : DragVisualMode
                                                                .reorder),
                                          );
                                        }));
                                  }));
                                });
                          });
                    },
                  ),
                ),
            ],
          )),
    );
  }
}

class PhysicsDragFeedback extends StatelessWidget {
  final Widget child;
  final ValueNotifier<double> tiltNotifier;

  const PhysicsDragFeedback(
      {super.key, required this.child, required this.tiltNotifier});

  @override
  Widget build(BuildContext context) {
    // The drag overlay follows the pointer directly; no decorative lift/tilt.
    return child;
  }
}
