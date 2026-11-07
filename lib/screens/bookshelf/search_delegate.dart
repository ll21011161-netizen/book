import 'dart:async';
import '../../core/perf_log.dart';
// lib/screens/bookshelf/search_delegate.dart
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme.dart';
import '../../core/anim_route.dart'; // 🌟 記得匯入動畫路由！
import '../../models/library_item.dart';
import '../details/category_detail_screen.dart';
import '../details/folder_detail_screen.dart';
import '../../data/database_helper.dart';

class SearchDel extends SearchDelegate {
  final VoidCallback onUpd;

  SearchDel(this.onUpd, {Future<List<LibraryItem>> Function(String)? search})
      : _search = search ?? DatabaseHelper.instance.searchItems;

  final Future<List<LibraryItem>> Function(String) _search;
  Timer? _debounce;
  Completer<List<LibraryItem>>? _pending;
  String? _lastQuery;
  Future<List<LibraryItem>>? _lastFuture;

  Future<List<LibraryItem>> _searchAfterTyping(String raw) {
    final watch = Stopwatch()..start();
    final value = raw.trim();
    if (_lastQuery == value && _lastFuture != null) return _lastFuture!;
    _debounce?.cancel();
    if (_pending != null && !_pending!.isCompleted) _pending!.complete([]);
    _lastQuery = value;
    final result = Completer<List<LibraryItem>>();
    _pending = result;
    _lastFuture = result.future;
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      try {
        final items = value.isEmpty ? <LibraryItem>[] : await _search(value);
        PerfLog.event('search_result', {
          'elapsed_ms': watch.elapsedMilliseconds,
          'count': items.length,
          'stale': result.isCompleted
        });
        if (!result.isCompleted) result.complete(items);
      } catch (error, stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      }
    });
    return result.future;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_pending != null && !_pending!.isCompleted) _pending!.complete([]);
    super.dispose();
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _buildAsyncList(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().isEmpty) {
      _debounce?.cancel();
      if (_pending != null && !_pending!.isCompleted) _pending!.complete([]);
      _lastQuery = null;
      _lastFuture = null;
      return Center(
          // 🌟 字體顏色隨系統設定，不怕看不見！
          child: Text("請輸入關鍵字來尋找漫畫",
              style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color)));
    }
    return _buildAsyncList(context);
  }

  Widget _buildAsyncList(BuildContext ctx) {
    return FutureBuilder<List<LibraryItem>>(
        future: _searchAfterTyping(query),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView.builder(
              itemCount: 8,
              itemBuilder: (_, i) => Shimmer.fromColors(
                enabled: !MediaQuery.disableAnimationsOf(context),
                baseColor: Colors.grey[300]!,
                highlightColor: Colors.grey[100]!,
                child: ListTile(
                  leading: const Icon(Icons.book, color: Colors.white),
                  title: Container(
                    height: 16,
                    width: double.infinity,
                    color: Colors.white,
                    margin: const EdgeInsets.only(right: 50),
                  ),
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
                child: Text("搜尋發生錯誤：${snapshot.error} ",
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodyMedium?.color)));
          }

          final r = snapshot.data ?? [];
          if (r.isEmpty) {
            return Center(
                child: Text("找不到相關的漫畫，要不要換個關鍵字試試看",
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodyMedium?.color)));
          }

          return ListView.builder(
              itemCount: r.length,
              itemBuilder: (_, i) => ListTile(
                  leading: Icon(r[i] is MangaFolder ? Icons.folder : Icons.book,
                      color: AppTheme.accent),
                  title: Text(r[i].title),
                  onTap: () {
                    close(ctx, null);
                    if (r[i] is MangaBook) {
                      // 🌟 使用 fade 確保 HERO 動畫
                      Navigator.push(
                          ctx,
                          AnimRoute(
                              context: ctx,
                              page: CategoryDetailScreen(
                                  category: r[i] as MangaBook,
                                  onUpdate: onUpd)));
                    } else {
                      Navigator.push(
                          ctx,
                          AnimRoute(
                              context: ctx,
                              page: FolderDetailScreen(
                                  folder: r[i] as MangaFolder,
                                  onUpdate: onUpd)));
                    }
                  }));
        });
  }
}
