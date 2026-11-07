enum ItemType { book, folder }

abstract class LibraryItem { 
  final String id; 
  String title; 
  final ItemType type; 
  
  LibraryItem(this.id, this.title, this.type); 
}

class MangaBook extends LibraryItem { 
  String? coverPath; 
  List<String> filePaths; 
  int lastReadPage; 
  int readCount;
  int totalPageCount; 

  MangaBook({
    required String id, 
    required String title, 
    this.coverPath, 
    required this.filePaths,
    this.lastReadPage = 0,
    this.readCount = 0,
    int? totalPageCount, 
  }) : totalPageCount = totalPageCount ?? filePaths.length,
       super(id, title, ItemType.book); 
}

class MangaFolder extends LibraryItem { 
  int itemCount; 
  final List<String> thumbnails; 
  List<String> coverBookIds;

  MangaFolder({
    required String id, 
    required String title, 
    this.itemCount = 0,
    this.thumbnails = const [],
    this.coverBookIds = const []
  }) : super(id, title, ItemType.folder);
}