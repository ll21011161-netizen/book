# 槍簿效能檢查紀錄（2026-11-06 晚間至 11-07）

本輪依工作區最新實際程式碼檢查並修改；根目錄是有效 Flutter 專案，內層 `flutter_application_1manga` 沒有 `lib`，不是另一份應用程式來源。使用 Flutter 3.38.3 / Dart 3.10.1、Windows、USB Pixel 6。沒有清除既有應用資料、變更資料庫結構、覆寫既有未提交修改或進行 Git 重設／提交。

有效工作約 32 分鐘，完成可安全驗證的主要修改後收尾；沒有以等待補滿時間。隔離測試套件已停止，測試產物保留供重現。

原始輸出、修改前程式碼與機器可讀統計位於 [performance_results/2026-11-06](performance_results/2026-11-06)，統計見 [summary.json](performance_results/2026-11-06/summary.json)。資料夾日期是開始工作時的日期。

## 已確認瓶頸與修改

| 檔案 | 證據與修改 |
| --- | --- |
| `lib/widgets/book_card.dart`、`lib/widgets/folder_card.dart` | 原本直接用 `AppImage` 讀取封面原圖。改為共用現有 `PageThumbnail` / `ThumbnailCache`。命中時讀磁碟縮圖；未命中先顯示原圖，原圖首幀回報後才用現有單工作者排程補快取，並保持當前圖片不切換。 |
| `lib/widgets/page_thumbnail.dart` | 增加可指定的 fit、cacheWidth、圓角及封面冷載入策略。保留詳情頁原有預設行為；補快取比可見詳情縮圖優先序低，已離開／換來源的工作不再啟動。保留書架父層原有背景。 |
| `lib/data/thumbnail_cache.dart` | 新增合併重複請求的「只查現有快取」入口。共用一次成功的目錄定位，暫時失敗可重試；有效縮圖檢查回傳已取得的 FileStat，省去命中路徑再次 stat。修正近期縮圖會繞過配額的漏洞。 |
| `lib/data/database_helper.dart` | `fetchItems` 和搜尋原本每個自訂封面資料夾各多一次 SELECT。以有界的 UNION ALL 批次執行既有 SELECT，通常 50 個資料夾從 51 次變成 2 次；維持原有 IN 查詢語意、順序、重複路徑、自動補圖、資料夾計數及分頁。不修改 schema。 |

靜態封面維持書籍 150、資料夾 80 的解碼寬度與原有 BoxFit／外層裁切、Hero tag、互動和 Material 配色。磁碟縮圖仍是原有 300 寬無損 PNG。GIF／WebP 封面保守沿用原圖，保留可能存在的動畫，因此靜態 WebP 目前也不走書架磁碟縮圖。

首次補快取會多讀一次原圖來產生後續可重用的縮圖；這項工作安排在該封面首幀之後。沒有把「等待首次縮圖生成」放到書架首張圖片的必要路徑。沒有調低閱讀器解析度，也沒有調整縮放、雙擊、拖曳、閱讀方向或翻頁動畫。

快取清理只處理既有快取目錄內符合 SHA256 名稱的 PNG，保留使用中的 lease 和正在寫入的檔案。256 MiB 是維護時的目標配額，仍屬最佳努力：使用中檔案、清理間隔及 I/O 失敗可能造成暫時超額。新縮圖不再因一天保留期而無條件繞過配額。

## 實際量測

以下都是元件／資料查詢量測，**不是應用 FPS 或首幀可見時間**。中位數不代表其他格式、裝置或真實書庫的保證改善。

| 情境 | 修改前／原圖策略 | 修改後／快取策略 | 判讀 |
| --- | ---: | ---: | --- |
| 5,000 本、50 自訂封面資料夾，SELECT 次數 | 51 | 2 | 桌面 SQLite 真實 SQL 回歸測試可重現 |
| Pixel 6 同程序交替執行上述 `fetchItems`，10 輪中位數 | 186.849 ms | 74.221 ms | 此資料集查詢耗時減少 60.28%；非繪製測試 |
| 同上範圍 | 108.572–1244.562 ms | 54.783–138.748 ms | 原始資料含明顯離群值，使用中位數，完整保留紀錄 |
| Windows 上述查詢，5 輪中位數 | 3.749 ms | 3.607 ms | 差異小且範圍重疊，不主張顯著加速 |
| Windows 搜尋 50 資料夾，5 輪中位數 | 2.614 ms | 2.712 ms | 次數減少，但沒有量測到時間改善 |
| Windows 12 張 2048×3072 合成 PNG，原圖／磁碟縮圖解析 | 95.254 ms | 9.562 ms | fresh cache instance 的磁碟命中；不是 Flutter decoded-image-cache 命中 |
| 同上，首次生成 PNG 後才顯示 | — | 372.862 ms | 確認會退步，未用此策略載入書架冷封面 |
| 同上，冷封面只查磁碟後讀原圖 | 95.254 ms | 118.954 ms | 新增查快取開銷；首次顯示加速未被證明，避免了等待完整生成 |

來源與方法：

- [bookshelf_before.log](performance_results/2026-11-06/bookshelf_before.log)、[bookshelf_after.log](performance_results/2026-11-06/bookshelf_after.log)：Windows OS SQLite、相同測試資料、各五輪；資料夾各有 100 本漫畫及四個自訂封面。
- [device_matched.log](performance_results/2026-11-06/device_matched.log)：同一 Profile APK 包含修改前的 `DatabaseHelper` 原始快照及修改後版本，在同一資料庫／程序內交替各執行十次。原始方法未被縮寫成模擬 SQL。查詢發生在鎖定畫面狀態，不能推論互動繪製速度，但前後工作負載和程序狀態相同。
- [device_matched_harness.dart.txt](performance_results/2026-11-06/device_matched_harness.dart.txt) 保留配對入口；修改前類別見 [database_helper.before.dart.txt](performance_results/2026-11-06/database_helper.before.dart.txt)。隔離副本中將後者命名為 `lib/data/database_helper_baseline.dart`，以 alias import 共存。
- [reader_cover_components_final.log](performance_results/2026-11-06/reader_cover_components_final.log)：Windows 圖片元件五輪交替；每輪使用新快取目錄，來源是純色合成 PNG，不是實際漫畫 JPEG，OS 檔案快取未清除。`deferred` 時間只含查詢與原圖解碼，後續生成另於量測結束後完成。
- 不採用 `device_before.log` / `device_after.log` 兩次啟動的非配對查詢時間來主張加速：啟動、鎖定／喚醒狀態不一致。以後續同程序配對紀錄為準。

Pixel 6 亦完成五輪非繪製的元件比較：12 張圖片原圖解析中位數 1729.395 ms、首次 PNG 生成並解析 5371.084 ms、磁碟命中解析 117.300 ms；冷封面查快取後讀原圖為 1702.535 ms。裝置仍鎖定且未收集前景繪製，這些僅供元件成本參考，不宣稱首張封面或第一排縮圖已快多少。

## 保留的現有機制與實驗

- `ThumbnailScheduler` 已能限制並行、動態評估優先序並丟棄已無需求的排隊工作；`ThumbnailCache` 有 pending 去重、原子寫入、來源 size/mtime 驗證、損壞回退、lease 及有界的有效性記憶。保留這些設計。
- Windows 24 張 2048×3072 合成 PNG，一工作者首次生成中位數 846.310 ms，兩工作者 552.889 ms（各三輪，順序交替）。沒有前景 Android 掉幀／峰值記憶體佐證，預設維持一工作者，仍可用既有 `GUNBOOK_THUMB_WORKERS` 做後續實驗。
- 閱讀器 `SerialImageWork` 涵蓋 codec 建立及首幀解析；後續動畫幀也排在同一佇列。`ReaderFileImage` 沒有設定縮小目標，原圖細節保留。既有 `LatestTask` 只保留一個可替換預載目標，並在拖曳、縮放、背景及已有圖片待載時抑制預載。這些不是缺少實作的功能。
- Pixel 6 用相同底層 codec 對八張完整 2048×3072 圖片做五輪壓力實驗：單工作者總耗時中位數 2546.615 ms、兩工作者 1180.743 ms；每輪排隊中位數再取中位數分別是 1262.152／577.210 ms。RSS 批次結束樣本中位數約 297.2／352.9 MiB。此實驗立即 dispose 各幀，**不是**完整 `ReaderFileImage` 畫面、正常單張翻頁或記憶體峰值量測，因此沒有據此增加閱讀器並行或調整解析度。
- `PagePathCache` 已合併 in-flight 查詢、有大小限制、複製回傳值及 mutation revision 防舊請求回填。閱讀進度已 debounce、序列寫入、失敗重試及退出 flush。保留現有設計。
- 書架已有分頁、載入代次防競態、通知 debounce、KeepAlive、設定選擇性訂閱；搜尋已有 200 ms debounce。沒有僅憑 setState、Opacity 或 RepaintBoundary 做重構。
- `ImportService` 的本機掃描在 compute isolate，複製使用非同步 I/O、節流進度、journal 和大小檢查，DB 以整筆 transaction 及有界 batch 寫入。Android `SafImportBridge.kt` 對 `content://` 用獨立 worker、原生 stream、共用 64 KiB buffer、取消檢查、同步落盤及持久 ownership marker。兩條流程不同，均保留。
- 實際匯入支援目錄內 JPG/JPEG/PNG/WebP/BMP/GIF/HEIC/JFIF；是否能解碼仍取決於既有平台能力。沒有 ZIP／CBZ 入口，沒有新增或假設壓縮檔支援。
- 本機匯入基準 80 個檔案、5 MiB、三輪總時間 118／84／86 ms，進度通知均三次；沒有本輪匯入程式修改，因此不宣稱匯入加速。SAF 效能沒有實際 provider 測試資料。

## 驗證與限制

| 檢查 | 結果 |
| --- | --- |
| 修改前 `flutter test --no-pub` | 60 項通過 |
| 最終 `flutter test --no-pub` | 69 項通過 |
| 最終啟用 `GUNBOOK_PERF=true` 完整測試 | 69 項通過 |
| 最終 `flutter analyze --no-pub` | 結束碼 1，0 error、4 既存 warning、51 既存 info；原本 57 項，最後 55 項，沒有新增問題 |
| 正式 `lib/main.dart` Android Profile APK | 建置成功，未安裝覆蓋使用者應用 |
| 隔離 benchmark Android Profile APK | 建置／安裝成功，套件 `com.example.flutter_application_1manga.perf20261106` |
| `git diff --check` | 通過 |

新增／擴充測試檔案：`test/database_cover_test.dart`、`test/thumbnail_cache_test.dart`、`test/app_image_test.dart`、`test/reader_image_test.dart`。涵蓋 161 資料夾跨批次／分頁、搜尋、損壞設定、封面順序與重複路徑、來源變更、hit-only 不生成、目錄失敗重試、lease／配額、冷封面延後生成／離開取消、裁切與動畫保留，以及完整 2048×3072 閱讀器解析。

配額回歸測試在修正前刻意失敗（期待 0 個可清理近期檔案卻剩 3 個），修正後通過。建立圖片的 widget 測試曾受 fake async 等待影響，改為在 runAsync 預先建立圖片及正確推進排程後已通過；沒有留下失敗的最終測試。

Pixel 6 鎖定畫面阻止畫面繪製。已通知使用者需要解鎖；未繞過驗證或清除鎖定。因此 **沒有可用的** `bookshelf_first_frame`、`detail_first_thumbnail`、`detail_first_row`、`reader_visible`、實際閱讀器 `reader_decode`、前景 `frames`、冷啟動畫面可見時間、正常翻頁掉幀或記憶體峰值結果。缺失事件不是 0 ms。書架捲動、設定切換、Hero、雙擊與拖曳只有既有／新增自動測試及程式檢查，沒有本輪實機視覺驗收。

## 重現與下一輪

桌面基準可從根目錄執行：

```powershell
flutter test --no-pub tool/bookshelf_perf_test.dart
flutter test --no-pub tool/cover_perf_test.dart
flutter test --no-pub tool/thumbnail_perf_test.dart
flutter test --no-pub --dart-define=GUNBOOK_PERF=true tool/import_perf_test.dart
```

`tool/device_perf.dart` 只允許在上述獨立套件識別碼下執行，啟動即檢查 app cache 路徑；不能直接拿正式套件識別碼來跑。測試副本在 `.dart_tool/perf_device`，其 Gradle applicationId 已另設，原始專案的 applicationId 未修改。新一輪編譯使用不同的 `--dart-define=GUNBOOK_BENCH_REVISION=<唯一值>`，並確認 APK 包含本輪事件，以排除舊入口的增量建置產物。

優先建議：

1. 解鎖並保持同一 Pixel 6 前景，用真實 JPEG／PNG／靜態及動畫 WebP 書庫，量測冷載入、磁碟命中、首張封面、詳情第一排與 Hero。特別確認冷封面補快取對其他待載封面的競爭成本。
2. 同流程收集實際 `reader_decode`／`reader_visible`／`frames` 與峰值記憶體，再評估前景優先佇列、過期工作跳過或有界兩路解析；維持原圖放大細節及手勢。
3. 以實際 Android SAF 本機／雲端 provider 的相同目錄做匯入分段量測（scan、copy、sync、database），驗證取消與失敗復原後再決定是否優化；目前沒有安全理由放寬落盤與交易保護。
