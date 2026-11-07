// lib/core/strings.dart
class AppStrings {
  static final Map<String, String> _data = {
    'home': '首頁', 'more': '更多', 'library': '書庫', 'import': '匯入',
    'new_folder': '新增資料夾', 'settings': '設定', 'display': '顯示', 'reader': '閱讀器',
    'zoom_delay': '縮放延遲 (毫秒)', 'zoom_level': '圖片縮放倍率',
    'scanning': '掃描中...', 'no_images': '沒有圖片', 'import_success': '匯入成功', 'empty': '空空如也',
    'rename': '重新命名', 'delete': '刪除', 'cancel': '取消', 'save': '儲存',
    'create': '建立', 'move_to': '移動到...', 'set_cover': '設為封面', 'reading': '閱讀中',
    'add_content': '新增內容', 'new_book': '新增空漫畫', 'batch_import': '批次匯入',
    'confirm_delete': '確定要刪除嗎？', 'selected': '已選取', 'edit': '編輯',
    'copying': '複製檔案中...', 'select_all': '全選', 'deselect_all': '取消全選',
    'rtl_mode': '右到左閱讀 (RTL)', 'rtl_desc': '適合日系漫畫的閱讀方向',
    'loading': '載入中...', 'folder_move_out': '移出資料夾', 'folder_empty': '資料夾是空的'
  };
  
  static String get(String key) => _data[key] ?? key;
}