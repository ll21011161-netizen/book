// lib/core/utils.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'strings.dart';
import '../models/library_item.dart';
import '../models/import_args.dart';
import '../data/database_helper.dart';
import '../data/import_service.dart';

class Debouncer {
  final int milliseconds;
  Timer? _timer;

  Debouncer({required this.milliseconds});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }

  void dispose() {
    _timer?.cancel();
  }
}

extension StringExtensions on String? {
  bool get isValid => this != null && this!.trim().isNotEmpty;
}

extension BuildContextExtensions on BuildContext {
  void showSnackBar(String message) {
    ScaffoldMessenger.of(this).clearSnackBars();
    ScaffoldMessenger.of(this).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<T?> push<T>(Widget page) =>
      Navigator.push<T>(this, MaterialPageRoute(builder: (_) => page));
  void pop<T>([T? result]) => Navigator.pop(this, result);
}

class AppSettings {
  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<int> getInt(String k, int d) async =>
      (await _prefs).getInt(k) ?? d;
  static Future<double> getDouble(String k, double d) async =>
      (await _prefs).getDouble(k) ?? d;

  static Future<void> setInt(String k, int v) async =>
      (await _prefs).setInt(k, v);
  static Future<void> setDouble(String k, double v) async =>
      (await _prefs).setDouble(k, v);
}

class DialogUtils {
  static void showLoading(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Expanded(child: Text(message, overflow: TextOverflow.visible)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<String?> showInput(BuildContext context,
      {required String title, String? initial, String? hint}) {
    String val = initial ?? "";
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          autofocus: true,
          initialValue: initial,
          decoration: InputDecoration(hintText: hint),
          onChanged: (v) => val = v,
          onFieldSubmitted: (_) => ctx.pop(val),
        ),
        actions: [
          TextButton(
              onPressed: () => ctx.pop(),
              child: Text(AppStrings.get('cancel'))),
          FilledButton(
              onPressed: () => ctx.pop(val),
              child: Text(AppStrings.get('save'))),
        ],
      ),
    );
  }

  static Future<bool> showConfirm(BuildContext context,
      {required String title}) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            actions: [
              TextButton(
                  onPressed: () => ctx.pop(false),
                  child: Text(AppStrings.get('cancel'))),
              FilledButton(
                  onPressed: () => ctx.pop(true),
                  child: Text(AppStrings.get('delete'))),
            ],
          ),
        ) ??
        false;
  }
}

class LibraryActions {
  static bool _importUIBusy = false;

  static Future<void> batchImport(BuildContext context) async {
    if (_importUIBusy) {
      context.showSnackBar('已有匯入作業進行中');
      return;
    }
    _importUIBusy = true;
    ValueNotifier<String>? progressText;
    ValueNotifier<double>? progressValue;
    DialogRoute<void>? dialog;
    Future<void>? dialogClosed;
    NavigatorState? navigator;
    try {
      final source = Platform.isAndroid
          ? await ImportService.pickDirectory()
          : await FilePicker.platform.getDirectoryPath();
      if (source == null) return;
      if (!context.mounted) {
        if (Platform.isAndroid) {
          await ImportService.channel
              .invokeMethod<void>('releaseDirectory', {'uri': source});
        }
        return;
      }
      final text = ValueNotifier<String>('準備匯入…');
      final value = ValueNotifier<double>(0);
      progressText = text;
      progressValue = value;
      final cancel = CancelToken();
      navigator = Navigator.of(context, rootNavigator: true);
      dialog = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('匯入漫畫'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              ValueListenableBuilder<String>(
                  valueListenable: text,
                  builder: (context, message, child) => Text(message)),
              const SizedBox(height: 16),
              ValueListenableBuilder<double>(
                  valueListenable: value,
                  builder: (context, amount, child) => LinearProgressIndicator(
                      value: amount > 0 ? amount : null)),
            ]),
            actions: [
              TextButton(
                  onPressed: () {
                    cancel.cancel();
                    text.value = '正在取消，等待複製停止並清理…';
                  },
                  child: const Text('取消'))
            ],
          ),
        ),
      );
      dialogClosed = navigator.push(dialog);
      final root = await DatabaseHelper.instance.booksRoot;
      final books = await ImportService.importBooks(
          ImportArgs(source, root.path), text, cancel,
          progressValue: value);
      if (context.mounted) {
        context.showSnackBar(
            '${AppStrings.get('import_success')}（${books.length} 本）');
      }
    } on ImportCancelled {
      if (context.mounted) context.showSnackBar('已取消匯入，未提交任何書籍');
    } catch (error) {
      if (context.mounted) context.showSnackBar('匯入失敗：$error');
    } finally {
      // Remove this exact route, never an unrelated top route or the screen.
      if (dialog != null && dialog.isActive && navigator != null) {
        navigator.removeRoute(dialog);
      }
      if (dialogClosed != null) await dialogClosed;
      // Route animations/builders must be detached before notifier disposal.
      if (dialog != null) await dialog.completed;
      progressText?.dispose();
      progressValue?.dispose();
      _importUIBusy = false;
    }
  }

  static Future<void> createEmptyBook(BuildContext context) async {
    final name =
        await DialogUtils.showInput(context, title: AppStrings.get('new_book'));
    if (name.isValid) {
      await DatabaseHelper.instance.saveBook(MangaBook(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: name!,
          filePaths: [],
          totalPageCount: 0));
    }
  }

  static Future<void> createFolder(BuildContext context,
      List<String> selectedIds, VoidCallback onComplete) async {
    final name = await DialogUtils.showInput(context,
        title: AppStrings.get('new_folder'));
    if (name.isValid) {
      final f = MangaFolder(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: name!,
          itemCount: selectedIds.length);

      await DatabaseHelper.instance.createFolder(f, itemIds: selectedIds);
      if (context.mounted) onComplete();
    }
  }
}
