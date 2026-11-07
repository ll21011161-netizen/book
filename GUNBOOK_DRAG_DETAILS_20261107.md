# GunBook 拖曳與詳情頁驗證

本次未更動資料庫結構、原圖、檔名、閱讀器解碼、磁碟縮圖尺寸或快取版本。

## 修改檔案

| 檔案 | 修改內容 |
| --- | --- |
| `lib/widgets/drag_cover.dart`（新增） | 明確定義 none／reorder／merge；封面專用縮放，以及 Positioned.fill、IgnorePointer 裝飾。排序：藍色 2dp、swap_vert、0.97 倍、200ms。合併：主題色 3dp、create_new_folder、最多 1.025 倍、240ms 輕微回彈。依封面長邊限制擴張約每側 2dp，避免侵入相鄰卡片；減少動畫時使用零時長。 |
| `lib/widgets/book_card.dart` | 拖曳效果只包住 Expanded 封面 Stack；移除舊 hover 遮罩。文字、卡片尺寸、點擊範圍、按壓、選取、圖片快取及來源 Hero 保留。 |
| `lib/widgets/folder_card.dart` | 同樣只處理資料夾封面，保留封面組合、圓角、文字及點擊範圍。 |
| `lib/screens/bookshelf/bookshelf_screen.dart` | 移除整張卡片外的縮放及框線，傳入明確視覺模式。保留 500ms 與原本資料操作；pointer 取消時清理 Timer／Notifier，放下時核對當前目標、拒絕取消中的拖曳。只有有效目標訂閱合併變化，pointer update 不重建整個書架；浮起及旋轉回饋維持。 |
| `lib/screens/details/category_detail_screen.dart` | 移除 320dp 大封面、FlexibleSpaceBar、漸層、Hero 目的地、DetailCover 及封面狀態。改 pinned 標準高度標題列、單行省略，保留操作處理器。首排在首幀後經原排程開始生成，其餘等淡入完成；路由遮蔽或返回時停止新生成需求。取消首排原圖預覽。保持四欄、比例 0.78；純數字置於縮圖外的 24dp 標題區，無障礙描述仍完整。 |
| `lib/screens/details/folder_detail_screen.dart` | 移除 200dp 大封面及 Hero 目的地，改 pinned 標準標題列。保留設定封面、多選、重新命名、移出及資料夾內排序。 |
| `lib/widgets/page_thumbnail.dart` | 更新生成閘門註解，執行邏輯不變。 |
| `test/detail_loading_test.dart` | 驗證首排提早生成、其他項目延後、無原圖預覽、無大封面、數字順序及標題在圖片外；保留路由遮蔽、載入失敗及大型網格測試。 |
| `test/spring_drag_test.dart` | 驗證封面範圍、模式與圖示、跨目標清理、取消不排序，以及資料夾拖曳超過 500ms 仍只排序；涵蓋減少動畫設定。 |
| `test/spring_motion_test.dart` | 明確選取最外層按壓 AnimatedScale，持續驗證重複按壓、取消、尺寸及圖片 Element 保留。 |

`DetailRoute` 已有淡入／淡出，維持 380ms／320ms、無整頁縮放及既有 Android 預測返回生命週期，無需改動。詳情頁不建立隱藏 Hero；卡片及其他畫面仍保留 Hero。沒有配對目的地時，框架不啟動該 flight，導覽與中斷返回測試通過。

既有快取及排程保留：磁碟 200px、詳情顯示解碼 120–150px、預設單工、同路徑需求合併、dequeue 時依當下 viewport 計算優先權、卸載需求取消，以及懶建立網格與 200dp cacheExtent。未重寫圖片系統。

## 測試

- Dart format 已完成。
- 完整 `flutter test --no-pub`：119 項全部通過，見 `performance_results/2026-11-07-drag-details/tests.log`。其後僅補強資料夾來源拖曳測試，相關 5 項再次全數通過，見 `drag-final.log`。
- `flutter analyze --no-pub`：0 error、0 warning，44 項 info；包含既有大括號、舊 DragTarget callback、withOpacity、super parameter 提示。非零結束碼來自 info，不能稱為零提示。
- Android arm64 profile 建置成功；Pixel 6、Android 17 API 37、Impeller Vulkan 執行。
- 測試涵蓋 Android 預測返回取消／提交、380/320ms、重複返回保持首頁捲動位置、Hero 中斷、1000 頁懶建立、快取、資料安全與閱讀器。

## 效能對照

使用既有 `tool/detail_device_perf.dart`、PerfLog、PerfFrames，獨立套件 `com.example.flutter_application_1manga.detail20261107`，104 張 2048×3072 合成 PNG、記憶體資料庫，未使用正式 App 或使用者漫畫。

每版 11 次進出；run 2 為 70ms 快速返回，run 1、10 清空記憶體圖片快取，run 1 包含八次快速上下捲動。各版不同 fixture 路徑，首輪為該組磁碟縮圖冷快取，首頁封面可先暖入一張。

對照詳情頁由既有 `2026-11-07-detail/before` 快照與 `changes.patch` 還原，保存於本次結果的 `category-baseline.dart.txt`；只在隔離副本替換該檔，其他元件與新版相同，用來隔離詳情頁變化，並非完整歷史 APK 對照。先跑新版再跑還原版，未控制溫度及背景負載；冷快取每版只有一個樣本，不宣稱普遍改善比例。

| 指標 | 大封面還原版 | 新版 |
| --- | ---: | ---: |
| 冷開啟 Route 首幀 | 26.289ms | 17.167ms |
| 冷開啟 Widget 首幀 | 20ms | 8ms |
| 冷開啟第一張縮圖 | 150ms | 65ms |
| 冷開啟首排四張完成 | 238ms | 232ms |
| 再次開啟第一張，中位數 | 78ms | 67ms |
| 再次開啟首排完成，中位數 | 78ms | 71ms |
| 進場每次平均 UI 幀時間的中位數 | 3.46ms | 2.61ms |
| 進場每次平均 Raster 幀時間的中位數 | 7.07ms | 5.68ms |
| 進場最大 UI／Raster | 89.66／64.56ms | 44.48／31.07ms |
| 進場超過 16.67ms 幀／總幀 | 27／359 | 21／369 |
| 進場結束 RSS 樣本中位數 | 320.47MiB | 281.94MiB |
| 進場結束 image cache 樣本中位數 | 8.75MiB | 6.18MiB |
| 磁碟命中耗時，中位數 | 22.36ms | 23.72ms |
| 縮圖生成耗時，中位數 | 63.29ms | 67.65ms |

首幀是 post-frame callback elapsed time，Route 與 Widget 起算點不同。再次開啟中位數排除 run 0、2，共九次；幀樣本排除 run 2，共十次。RSS 是程序樣本，受 fixture 準備及 GPU 等影響，不是峰值或單頁淨增加記憶體。快取中位數涵蓋整次腳本，工作集合不同（還原版 570 次命中／70 次生成，新版 587／66），不能據此宣稱生成更快。

兩版各 11 次完成返回，首頁捲動位置均為 0.0，未記錄 bench error／failure。新版版面見 `detail-screen.png`。原始輸出、逐次事件及彙總在本次結果的 `profile.log/json`、`baseline.log/json`、`summary.json`。

縮圖生成本身未變快。主要措施是移除 600px 封面與背景工作、避免首排原圖預覽的額外解碼，以及提早使用有限並行排程。首排冷開啟完成時間接近，仍需其他裝置及漫畫驗證。

## 未完成的驗證與既有問題

- 未操作 Flutter DevTools UI、匯出完整 timeline 或量測 peak memory；數據來自 profile 模式 PerfFrames／PerfLog。
- 未量測整個首屏所有可見縮圖全部完成；首排四張不代表整個首屏。
- 漫畫詳情與滑動已用合成腳本實機測試；資料夾詳情、拖曳視覺及減少動畫主要以 Widget／手勢測試驗證，尚未完成所有真實手指與 Android 系統手勢的人工驗收。
- 真實漫畫、各種格式／長寬比、慢速儲存及長時間記憶體壓力仍待實機驗證；不保證所有情況更快或完全無掉幀。
- 原始漫畫詳情的 `_add() async {}` 已是空實作。本次保留按鈕及處理器，未擴充既有未實作的新增圖片流程。
