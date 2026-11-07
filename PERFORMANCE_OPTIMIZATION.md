# GunBook 效能與穩定性改善紀錄

日期：2026-11-06（Asia/Taipei）

本次完成程式檢查、可確認問題的修正、隔離測試及桌面基準。**尚未完成 Pixel 6／S24 Ultra 的效能驗收，不能宣稱手機整體變快或已排除 OOM。** 沒有修改原始漫畫、清除 SQLite／SharedPreferences、變更資料庫版本或新增套件。

## 還原點與範圍

- 主專案是此目錄下的 `pubspec.yaml`、`lib/`、`android/`，不是內層 `flutter_application_1manga/` 範本。
- 專案使用獨立 `.baseline-git`；一般 `git` 會找到 `C:/Users/ll210` 的另一個儲存庫。所有提交均使用 `--git-dir=.baseline-git --work-tree=.`。
- 工作分支：`perf/2026-11-06-stability`。
- **修改前還原點：`e3b3461`**，已保存原本 8 個未提交檔案的修改；沒有覆蓋它們。
- 診斷：`ff98ece`；縮圖：`3472fe0`；詳情頁：`4fb77d6`；書架：`38abe5f`；基準及匯入測試：`3415d0f`；縮圖成本修正：`b5f2a4e`；生命週期：`35e0309`。
- 檢閱總差異：`git --git-dir=.baseline-git --work-tree=. diff e3b3461 HEAD -- lib test tool`。需要還原時，先保存後續修改，再選擇撤銷相關提交；不要直接 hard reset 使用中的工作區。

## 已確認的問題與修正

| 問題 | 修正與驗證 |
| --- | --- |
| `AppImage.frameBuilder` 每次成功 frame／重建都可能排入完成回呼 | 改為每個圖片來源／解碼尺寸只通知一次；同步命中、換圖重設、過期與 dispose 回呼都有測試 |
| `PageThumbnail` 先顯示原圖，之後切換磁碟縮圖 | 先解析縮圖結果；成功時只交給顯示層一個來源；失敗才使用有尺寸限制的原圖；避免原圖→縮圖閃換 |
| 詳情頁 `_checkPages` 查詢失敗未捕捉，會一直 Shimmer | 明確區分載入、錯誤、空書、成功；重試按鈕；generation 與 mounted 防止過期更新 |
| 重開書籍／從詳情頁開閱讀器可能重讀相同頁面清單 | 資料庫層有界 LRU、合併同時讀取；回傳清單副本；資料變更後失效，包括舊的進行中查詢 |
| 最近閱讀遇到多個已刪書籍時逐筆查詢 | 一次批次讀取最多 100 個 ID 的摘要，依歷史順序挑選；第一筆已在最新書架資料內則直接使用 |
| 書架刷新回到前 50 筆，可能截短已載入範圍 | 刷新保留目前已載入筆數；沿用 ScrollController、分頁互斥與過期回應保護 |
| 詳情頁封面設定在 await 後可能操作已 dispose 的 State，開閱讀器的 Future 未完整處理 | mounted／busy 保護、等待寫入並捕捉失敗；阻止重複開閱讀器與重複封面更新 |
| 刪頁確認期間可重複開啟操作 | 確認前即取得操作鎖，取消／失敗均釋放 |
| `DialogUtils.showInput` 建立未釋放的 Controller | 使用 `TextFormField.initialValue`，交給 Flutter 管理內部 Controller；保留輸入、提示、送出及按鈕行為 |

## 各階段檔案與策略

### 1. 分析與診斷

已閱讀指定 Dart 檔案、`reader_zoom.dart`、匯入日誌與恢復程式、搜尋、Provider、模型、既有測試、pubspec／lock、Android Activity、SAF bridge、Manifest 與 Gradle 設定。

修改：`lib/core/perf_log.dart`、`lib/data/import_service.dart`、`lib/data/reader_image.dart`、三個指定畫面及 `lib/screens/bookshelf/search_delegate.dart`。

沿用 `PerfLog`，只在 `--dart-define=GUNBOOK_PERF=true` 啟用；沒有第二套紀錄系統。記錄筆數、耗時、位元組與索引，不記書名、路徑或搜尋文字。

| 事件 | 意義與限制 |
| --- | --- |
| `import_scan_local`／`import_scan_saf` | 掃描耗時與數量；本機掃描沿用 compute，SAF 沿用原生背景工作 |
| `import_copy_local`／`import_copy_saf` | 複製耗時、位元組、頁數；本機額外記 MiB/s，SAF 可由 bytes／elapsed_ms 換算；SAF sync_ms 已包含在複製時間內 |
| `import_database`／`import_total` | 原子資料庫寫入／包含準備及最終恢復清理的完整匯入耗時與結果 |
| `detail_first_frame`／`detail_paths` | State 建立至首個 Flutter frame／取得清單耗時；後者可能命中清單快取 |
| `database_pages_query` | 真正執行 SQLite 頁面查詢時才出現，可區分快取與資料庫成本 |
| `detail_first_thumbnail`／`detail_first_row` | 索引 0–3 的首張／全部成功圖片 frame 的 post-frame 回呼；壞圖不算成功；不代表整個螢幕已完成 GPU 呈現 |
| `thumbnail_hit`／`thumbnail_generate`／`thumbnail_trim` | 快取查找、排隊與產生時間、清理後容量 |
| `bookshelf_query`／`bookshelf_first_frame` | 查詢及模型組裝時間／第一次資料發佈後 frame，並非所有封面解碼完成 |
| `search_result` | 包含 200 ms debounce 的結果時間，標記已過期的請求 |
| `reader_decode` | 排隊與原圖 I/O、codec、首 frame 取得時間；不等於純 codec 或 GPU 上傳耗時 |
| `reader_visible` | 初始載入或 page changed 到圖片 ready 回呼；未含完整滑動手勢，亦不是淡入動畫結束時間 |
| `frames` | Widget 掛載期間 build／raster 超過 8.33、16.67 ms 的 frame 數與最大值；保留中的書架與覆蓋路由的區間可能重疊，不能直接當作該畫面專屬掉幀率 |

RSS 與 ImageCache 數值是事件當下樣本，**不是記憶體尖峰**。實際掉幀、縮放流暢度及記憶體尖峰仍須用 DevTools／Android 工具選定相同操作區間分析。重複開啟標記只代表同一程序曾開過該書，不代表 OS 磁碟快取狀態；缺少事件不能視為 0 ms。

### 2. 縮圖（最高優先）

修改：`lib/data/thumbnail_cache.dart`、新增 `lib/data/thumbnail_scheduler.dart`、`lib/widgets/page_thumbnail.dart`、`lib/widgets/app_image.dart`。

- 預設維持 **一個 codec 工作**。排隊時重新評估 viewport：可見為 0、下一排為 1、其餘為 2；同級保留排入順序。SliverGrid 的懶建立及 cacheExtent 保留。
- 相同來源共用進行中的 Future；多個使用者的需求合併。離頁後尚未開始的工作略過；已進入原生解碼的工作不強制中止。
- 測試用 `--dart-define=GUNBOOK_THUMB_WORKERS=2` 可比較二工；只接受 1–2。尚未通過手機記憶體驗收，所以不啟用二工作為預設。
- 來源 path、size、mtime 決定快取鍵；原圖變更會產生不同鍵。失敗會移除 pending 狀態，允許重試。
- PNG 先寫 `.tmp` 再 rename；命中時檢查檔案大小、PNG 頭及 IEND。這不是完整 CRC 驗證；中段損壞由顯示 decoder 錯誤回呼處理，丟棄壞快取並退回原圖，之後可重建。
- 最多 256 筆已驗證檔案的 size／mtime 記錄，變更後重新驗證；避免每次重讀同一快取檔。
- 快取目標 256 MiB、30 天未使用可清理；使用時間以 mtime 記錄，每小時最多更新一次。最近一天及有 widget lease／進行中請求的結果受保護，因此是**軟上限**。
- 清理只在縮圖批次結束後觸發，最多每 10 分鐘掃描；只處理縮圖專用目錄中符合 SHA256 命名的 `.png`，不走訪漫畫原圖目錄。
- 風險：首次產生期間先顯示固定尺寸占位，首排需要等待產生佇列；可能比原本先顯示原圖更晚。必須比較 Pixel 6 的首張／首排時間，若退步，調整冷快取顯示策略，不能僅用整批吞吐量判定。
- 尚未自動回收程序被殺後遺留的 `.tmp`；不將它們視為成功快取，也不任意刪除可能仍被其他工作使用的暫存檔。

### 3. 詳情頁與 SQLite

修改：`lib/screens/details/category_detail_screen.dart`、`lib/data/database_helper.dart`、新增 `lib/data/page_path_cache.dart`。

頁面清單只選取 `path` 欄位。最多快取 20 本、合計 20000 路徑；超大單本仍可讀取，但不留在此快取。所有既有資料變更通知都保守地清除清單快取；閱讀進度不改路徑，故不清除。這避免複雜的局部通知協定，但封面／改名也會使快取失效，是已知的保守成本。

詳情頁監聽資料變更並重新取得清單，已有資料不再整頁變 Shimmer。首次讀取會立即發佈清單，不等待 legacy cover 檔案存在性檢查。網格仍每列四張、保留排列與選取介面。

### 4. 書架

修改：`lib/screens/bookshelf/bookshelf_screen.dart`、`lib/data/database_helper.dart`。

保留既有 40 ms 通知 debounce、分頁去重、資料代次檢查、Material 3、分類、搜尋、封面大小與捲動控制器。最近閱讀改在有效的書架查詢完成後載入，避免過期刷新繼續查摘要；錯誤會捕捉並保留既有面板。

尚未改成全新的局部資料通知架構。選取非「全部」分類仍沿用既有分頁掃完資料的方式；大量書籍時仍可能昂貴。保留已載入範圍的刷新也可能讀取較多資料，需看 `bookshelf_query` 實測。

### 5. 匯入

修改：匯入診斷、`tool/import_perf_test.dart` 與 `test/library_safety_test.dart`；Android SAF 邏輯不變。

SAF 已使用單一背景 executor、每資料夾投影查詢、共用 64 KiB buffer、100 ms 進度節流、檔案長度核對與 fd.sync。本機已使用掃描 isolate；SQLite 每 256 個 operation 分批但包含在同一 transaction。已有 session journal、取消確認與提交後恢復。

沒有實機證據支持並行複製、調大 buffer 或移除 sync，因此保留。新增失敗→取消→再匯入成功且既有書籍位元組及資料列不受影響的測試。大量小檔與少量大檔均已隔離測試，各三次。

### 6. 閱讀器

修改僅限第一階段的 `reader_image.dart` 與 `manga_reader_screen.dart` 診斷；`reader_zoom.dart` 不變。

已檢查實際 codec／首 frame 序列化、LatestTask 只保留最新預載目標、互動／背景時取消待執行預載、ImageStream listener／ImageInfo／codec 釋放，以及進度序列化、重試與生命週期 flush。保留原始解析度、雙擊、雙指、拖曳、PageView、RTL 與閱讀進度。

**未進行沒有實機證據的解析度／解碼系統重寫。** 200 MiB ImageCache 是快取預算，不是整個程序或 live image 的上限。極高解析度單頁及多個 live image 仍可能造成記憶體尖峰；RGBA 記憶體約 width × height × 4，還有 codec／GPU 等額外成本。

`reader_visible` 是首次 ready 回呼的診斷，已建立且再次成為目前頁的 widget 不保證重新發事件；來回翻頁的完整延遲應以 DevTools timeline／影片及統一操作量測，不能僅憑此事件算全部翻頁中位數。

### 7. 品質與未完成項目

修改：`lib/core/utils.dart` 與詳情頁操作保護，並新增對應測試。

- `_add()` 確認是空方法，按鈕仍存在；此次沒有擅自實作匯入到現有書籍的新功能。
- `smooth_zoom.dart` 未被目前 reader 引用；`image`、`flutter_staggered_animations`、`fluid_bottom_nav_bar` 在 lib 未找到使用。尚未刪除檔案或依賴，避免擴大套件／舊功能變動。
- 剩餘 analyzer 提示包含既有未用 import、非必要 null 判斷、deprecated API 與 braces 風格；沒有降低規則或加入忽略來掩蓋。
- Android release 仍使用既有 debug signing 設定；正式發行簽章配置不屬此次效能修改。

## 自動驗證

Flutter 3.38.3／Dart 3.10.1；Windows 主機。工具偵測到 Pixel 6、Android 17 API 37 已連線；沒有安裝或操作手機正式書庫。

| 階段 | flutter test |
| --- | --- |
| 修改前 | 43 通過 |
| 診斷 | 43 通過 |
| 縮圖 | 49 通過 |
| 詳情頁 | 53 通過 |
| 書架 | 56 通過 |
| 匯入重試 | 57 通過 |
| 最終一般／PerfLog 啟用 | 各 60 通過 |

每個有程式修改的階段均執行指定檔案 `dart format`、`flutter analyze --no-pub` 與 `flutter test --no-pub`。初始 analyzer 為 60 項；**最終仍非零：57 項（4 warnings、53 infos，0 errors）**。比對訊息及檔案後沒有新增診斷；本次新增提示已修復。詳細紀錄在 `performance_results/`，不得將此結果稱為 analyze 全綠。

Android debug 及啟用診斷的 profile APK 已編譯成功。編譯不代表已完成實機功能／效能驗證。

新增／擴充測試涵蓋：快取重用、來源失效、截斷檔重建、失敗重試、清理保護、排程優先與有限並行、同步圖片快取、換圖／離頁、壞圖、SQLite 失敗重試、1000 頁網格懶載入、既有資料保留、書架刷新與分頁，以及匯入恢復。既有雙擊、雙指、RTL、翻頁／預載排程、進度寫入失敗測試均保留。真實高速滑動、連續翻頁與程序中斷恢復仍需手機測試。

## 修改前後桌面基準

基線：`e3b3461`。所有資料為測試建立的暫存合成資料與獨立記憶體 SQLite，各組三次，採中位數。**不是 Pixel 6 結果，也不是 release/profile 裝置測試。** 匯入 fixture 是測複製的位元組檔，不是可解碼漫畫；SQLite 使用 Windows FFI adapter，沒有 Android sqflite channel 成本。OS 快取未強制清除。

| 項目 | 修改前中位數 | 修改後中位數 | 判讀 |
| --- | ---: | ---: | --- |
| 匯入 500 × 16 KiB | 578 ms | 573 ms | 接近，不能宣稱改善；通知均 8 次 |
| 匯入 4 × 16 MiB | 31 ms | 30 ms | 接近，不能宣稱改善；通知均 3 次 |
| 5000 頁清單首讀 | 3.305 ms | 2.970 ms | 不足以推論手機首開速度 |
| 同本 5000 頁再次取清單 | 3.493 ms | 0.076 ms | 隔離基準確有減少；兩次取清單的 SQL 從 2 次降為 1 次 |
| 24 張 2048×3072 PNG 縮圖產生，單工 | 964.363 ms | 973.981 ms | 接近，沒有證明整批產生變快 |
| 同批 24 張縮圖再查找，單工 | 5.278 ms | 6.646 ms | 檔案驗證有額外成本，已用有界驗證記錄降低；保留完整性取捨 |
| 新版二工縮圖產生 | 不適用 | 583.329 ms | 僅桌面合成測試較快，預設仍一工 |
| 詳情頁首張／首排、再次開啟、書架首屏 | 未量測 | 未量測 | 待 Pixel 6 |
| 手機翻頁、RAM 尖峰、GPU／UI 掉幀 | 未量測 | 未量測 | 待 Pixel 6／S24 Ultra |

各次原始數字與中位數見 `performance_results/summary.json` 及同目錄 logs。縮圖早期輪次曾出現較長的產生時間；其中重跑與 Android profile 編譯重疊，不能用來估計改善。所有輪次保留，最終比較在編譯結束後循序執行。依量測將清理移出產生熱路徑，並減少重複驗證 I/O；沒有以挑選最快單次結果宣稱加速。

縮圖 RSS 只採樣批次結束時，不同工作數在同程序交錯執行，有記憶體殘留及 GC 影響，**不能作為並行的尖峰記憶體比較**。二工仍不通過手機啟用條件。

## 重現測試

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub --dart-define=GUNBOOK_PERF=true
flutter test --no-pub --dart-define=BENCH_FILES=500 --dart-define=BENCH_BYTES=16384 tool/import_perf_test.dart
flutter test --no-pub --dart-define=BENCH_FILES=4 --dart-define=BENCH_BYTES=16777216 tool/import_perf_test.dart
flutter test --no-pub tool/page_paths_perf_test.dart
flutter test --no-pub tool/thumbnail_perf_test.dart
flutter build apk --profile --no-pub --dart-define=GUNBOOK_PERF=true
```

要測基線，將 `e3b3461` 用 `git archive` 匯出到另一個測試目錄，複製相同 assets、基準 tool 與測試圖片 helper，再離線 `flutter pub get --offline`。舊縮圖 API 沒有 worker／trim 參數，對應的完整基線 harness 保存在 `performance_results/thumbnail_baseline_harness.dart.txt`，放回基線 `tool/thumbnail_perf_test.dart` 即可。不要用 reset 覆蓋主工作區。

## Pixel 6 驗收步驟

使用隔離 Android 使用者或測試安裝及漫畫副本；不要清除正式 App 資料。兩版相同 applicationId 會更新同一 App，需事先安排隔離測試環境。分別使用還原點及新版，固定 Flutter、裝置溫度、充電／省電模式、亮度、螢幕更新率及 storage provider；避免同時下載或編譯。

1. 資料集分三組：大量小檔、少量大檔、RealESRGAN 高解析度。記錄檔案數、總 bytes、最大寬高、圖片格式及儲存來源。完整操作每版至少 3 次，交替版本，記錄中位數與範圍。
2. 用 `flutter run --profile --dart-define=GUNBOOK_PERF=true -d 1B151FDF6002BP`。此命令會安裝／啟動，請在隔離測試環境使用。`adb logcat -s GUNBOOK_PERF:I flutter:I '*:S'` 保存 Dart／SAF 紀錄。
3. 匯入三組資料。比對 scan、copy、MiB/s（bytes ÷ elapsed_ms × 1000 ÷ 1048576）、database、total。中途取消、再試、模擬供應者失去授權／讀取失敗；確認既有書籍、頁序及閱讀進度不變。
4. 各開一本短書與 1000+ 頁書，首開、返回再開、快速進出 20 次。使用一致的畫面捲動位置使第一排確實可見；記錄首張／首排、清單查詢事件及錯誤恢復。區分冷程序、既有磁碟縮圖與程序內暖快取；不要刪除原圖或清 App 資料來製造冷啟動。
5. 書架快速滑到超過 100 本的位置，刷新、分類、搜尋、返回；檢查捲動位置及列表不突然截短，通知突發不產生連續查詢，最近閱讀面板與進度正確。
6. 高解析度書籍連翻 100 頁，向前／向後、快速拖曳進度條、LTR／RTL、雙擊、雙指縮放至 4×、放大拖曳後退回 1×。確認文字畫質、翻頁手勢、錯圖提示及進度保存。
7. 閱讀中切換背景、鎖屏、旋轉與返回；匯入中切換背景／中止程序後重開。只在隔離資料測試程序終止，檢查 journal 恢復及無部分書籍提交。
8. 用 DevTools Performance／Memory 與 `adb shell dumpsys meminfo com.example.flutter_application_1manga` 在固定點取樣；另觀察過程尖峰及 Android logcat OOM。選定同一可見畫面的操作區間，120 Hz 與 60 Hz 的 frame budget 分別評估。
9. 相同資料再比較 `GUNBOOK_THUMB_WORKERS=1`／`2`。只在首排／整批耗時改善且尖峰記憶體、掉幀、取消與長讀穩定性均不惡化時考慮改預設；冷快取占位造成首排變慢時，先調整顯示策略。

## S24 Ultra 最終驗證與下一步

- 使用正式常用的螢幕解析度、120 Hz、RTL 設定與高解析度漫畫，重做上述操作；連續閱讀至少 30–60 分鐘，觀察溫度、記憶體成長與文字清晰度。
- 測內部儲存及實際使用的 SAF provider。不要將桌面複製結果套用到手機供應者。
- 優先補齊首張／首排、書架 frame、翻頁、記憶體尖峰的前後實機表格，再決定是否啟用二工。
- 若極大單頁仍 OOM，需先確認解碼尺寸與 live image，再評估動態解析度或分塊顯示；這涉及清晰度及架構，不能只把 ImageCache 上限調低當作解決。
- 通知目前仍保守刷新；分類會載入所有分頁。只有實測顯示它們是瓶頸時，再做可回滾的局部通知／SQL 分類查詢調整。
- `_add()` 未實作、暫存殘留清理與剩餘靜態提示仍待後續處理。本報告明確保留這些未完成項目，不代表全部階段已通過手機驗收。
