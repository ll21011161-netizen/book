// lib/core/config.dart
class AppConfig {
  // ============================================
  // 閱讀器與縮放設定 (Reader & Zoom Settings)
  // ============================================
  static const double zoomMin = 1.0;
  static const double zoomMax = 4.0;
  static const int zoomDivisions = 30;

  // ============================================
  // 效能與快取設定 (Performance & Caching)
  // ============================================
  static const int pageSize = 50;
  static const int diskThumbnailWidth = 200;
  static const int detailThumbnailMinWidth = 120;
  static const int detailThumbnailMaxWidth = 150;
  static const int detailCoverWidth = 600;
  static const int thumbnailCacheVersion = 2;
  static const int thumbnailCacheWidth = 150;
  static const int microThumbnailCacheWidth = 80;
  static const int memoryEvictDistance = 3;
}
