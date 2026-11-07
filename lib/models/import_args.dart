// lib/models/import_args.dart
class ImportArgs {
  final String sourcePath;
  final String appBooksPath;

  ImportArgs(this.sourcePath, this.appBooksPath);
}

// 🌟 新增：取消標記，用來在長時任務中傳遞中斷信號
class CancelToken {
  bool isCancelled = false;

  void throwIfCancelled() {
    if (isCancelled) throw const ImportCancelled();
  }

  void cancel() {
    isCancelled = true;
  }
}

class ImportCancelled implements Exception {
  const ImportCancelled();
  @override
  String toString() => '已取消匯入';
}
