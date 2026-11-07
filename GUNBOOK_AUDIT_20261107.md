# 槍簿程式碼健檢與修復報告（2026-11-07）

## A. 問題總覽

| 等級 | 位置／原因 | 影響與處理 |
| --- | --- | --- |
| P0 | `bookshelf_screen.dart::_continueReading` 只設 `_openingReader=true`，沒有釋放 | 正常返回、空書籍、查詢／計數失敗後均不能再開啟。已用 `finally` 修復，空書籍提供訊息。 |
| P0 | `file_scanner.dart::compareNatural` 短路迭代後再次呼叫 `moveNext`，跳過尾端片段；整數解析也無法涵蓋任意長數字 | 比較器反對稱性失效、資料夾／頁面順序錯誤。已改為每輪分別取得兩邊狀態，數字依有效位數與字典序比較，零補位等值時提供穩定次序。 |
| P0 | `folder_detail_screen.dart` 查詢沒有代次、失敗處理；寫入沒有互斥／生命週期保護；排序先更新 UI 且不等待儲存 | 載入卡住、舊查詢蓋新資料、離開後 setState、排序錯亂、重複寫入。已修復並加入重試入口。 |
| P1 | `settings_provider.dart` 非同步載入完成後直接 notify | Provider 已 dispose 時仍通知。已重現並修復；一併保護載入期間的使用者編輯、明確選回預設值的持久化。一般立即修改深色模式的案例在修改前已通過，不能稱為已重現的既有錯誤。 |
| P1／待處理 | 設定 setter 忽略寫入 Future；`AppSettings` 未檢查 SharedPreferences 寫入 bool | 儲存失敗缺乏使用者通知及一致的回復／重試流程。此輪未改寫持久化架構，仍是已知風險。 |
| P2 | 資料夾 refresh 固定只讀 50 筆，且非空時未標記 loading | 已載入多頁後刷新會縮回第一頁，增加後續重新載入；也可能讓分頁與刷新重疊。已保留載入視窗並阻止重複分頁。 |
| P2／待處理 | `category_detail_screen.dart::_add()` 是空函式 | 詳情頁新增圖片按鈕沒有功能；屬既有未完成實作，本輪未擅自設計新匯入流程。 |

## B. 實際修改內容

本輪只變更下列 9 個程式／測試檔；其他 Git 差異是工作開始前已存在的修改。

| 檔案 | 修改方式、理由及風險 |
| --- | --- |
| `lib/screens/bookshelf/bookshelf_screen.dart` | 開啟鎖在所有出口釋放；空頁面顯示訊息。低風險，沒有修改閱讀器畫質或路由樣式。 |
| `lib/data/file_scanner.dart` | 修正迭代器與超長數字比較。低至中風險：新匯入排序會依正確自然順序；既有已儲存頁序不重新排列。大小寫相同仍可視為等值，零補位檔名有確定順序。 |
| `lib/screens/details/folder_detail_screen.dart` | 可注入測試 DB；查詢代次、去重、try/catch/finally、重試；寫入互斥、擷取選取 ID、mounted 檢查；儲存成功才發布排序；移出不再以已載入筆數冒充整個資料夾總數；刷新保留載入範圍。中風險：排序需等待 DB 成功才反映，避免失敗回滾造成混亂；寫入後會多一次確認查詢。 |
| `lib/core/settings_provider.dart` | 一次取得偏好設定後同步讀取各值；dispose 防護、載入例外處理、保護載入期間編輯。低風險；沒有改鍵名、預設值或依賴版本。寫入失敗回復仍待下一輪。 |
| `test/file_scanner_test.dart` | 基本順序、多段數字、前綴、超長數字、零補位、反對稱性及傳遞性。 |
| `test/recent_reading_test.dart` | 連點互斥、正常路由返回、空書籍、書籍不存在、計數失敗、dispose 後失敗。正常返回用 Navigator observer 移除測試路由，未啟動會觸及真實 DB 的閱讀器。 |
| `test/folder_safety_test.dart` | 載入失敗重試、舊查詢完成、dispose、排序失敗及寫入互斥、移出／改名／封面完成時已離開、100 本分頁刷新。 |
| `test/settings_lifecycle_test.dart` | dispose 後載入、載入期間編輯、預設值仍確實儲存。 |
| `test/reader_image_test.dart` | 在原有未提交測試上增補：缺檔、空檔、損壞檔均回報錯誤，之後正常圖片仍可解碼。原有完整解析度測試保留。 |

工作開始時根目錄 Git 解析至使用者家目錄；另找到專案內 `.baseline-git`，用唯讀 status 識別既有修改。已完整備份當時 `lib`／`test` 至 `performance_results/2026-11-07-audit/before`，Dart 備份使用 `.dart.txt` 避免被分析器重複掃描。沒有 reset、clean、提交、清空書庫或安裝覆蓋應用。

本輪差異見 `performance_results/2026-11-07-audit/changes.patch`，檔案清單見 `changed-files.json`。依賴、資料庫 schema、migration、Material 3 配色、卡片尺寸與閱讀畫質均未變更。

## C. 效能比較

| 項目 | 修改前 | 修改後 | 證據／限制 |
| --- | --- | --- | --- |
| 已載入 100 本的資料夾，編輯後刷新查詢上限 | 50 | 100 | 原始碼及新增分頁測試。保留視窗，避免刷新後被迫重新分頁；這不是耗時量測，刷新單次查詢反而可能較大。 |
| 設定初始化的順序 await／偏好取得入口 | 5 | 1 | 程式碼可直接確認。SharedPreferences 原本已有快取，不能說省掉 4 次原生 I/O，也不宣稱可見啟動時間改善。 |
| 啟動／書架可互動、首張封面／縮圖／閱讀圖片時間 | 未量測 | 未量測 | 未進行相同資料與前景條件的實機配對測試。 |
| 圖片解碼等待、連續翻頁、UI／raster 幀耗時、峰值記憶體、匯入耗時 | 未量測 | 未量測 | 單元測試 PerfLog 不是 Android 使用者操作基準，不能用來推論 FPS 或峰值。 |

沒有本輪實測加速百分比，也未引用前一輪效能報告冒充新結果。沒有足夠證據支持提高縮圖／閱讀器解碼併行或擴大預載，保留既有單工作者策略與原始閱讀解析度。

## D. 測試結果

環境：Flutter **3.38.3**、Dart **3.10.1**、DevTools **2.51.1**；AGP **8.11.1**、Kotlin **2.2.20**、Gradle **8.14**，Android Java 目標 **17**。套件依賴沿用 `pubspec.lock`，沒有升級。實際偵測到已授權 Pixel 6，但未安裝、啟動或覆寫其正式應用。

| 檢查 | 結果 |
| --- | --- |
| 修改前 `flutter test --no-pub` | **69 項通過**。 |
| 新增最初 16 項回歸套用於原始碼 | **13 項失敗、3 項通過**；確認原始問題。資料夾僅加 DB 注入接縫，仍執行原始操作邏輯。使用 finally 還原修復版。 |
| 最終 `flutter test --no-pub` | **88 項通過**。 |
| 最終 `flutter test --no-pub --dart-define=GUNBOOK_PERF=true` | **88 項通過**，沿用現有 PerfLog。 |
| 最終 `flutter analyze --no-pub` | **0 error、2 warning、52 info**，結束碼 **1**；不能標示為全綠。既存 warning 位於 `smooth_input_dialog.dart`：未用 import 與無效的 null fallback。本輪未新增分析診斷，移除修改檔內一個既存未用 import。 |
| `flutter build apk --profile --no-pub --dart-define=GUNBOOK_PERF=true` | **成功**；最終 APK 91,464,023 bytes，輸出 `build/app/outputs/flutter-apk/app-profile.apk`。未安裝。 |
| Android 前景 profile／DevTools／實際手勢長時間壓測 | **未執行**；未建立安全隔離且可操作的 Android 測試書庫與測試套件。 |

完整測試包含既有真實 OS SQLite 記憶體資料庫測試：v9 升級、transaction／批次取消 rollback、刪除 commit 失敗、閱讀進度與封面一致性、失敗清理重試、匯入複製失敗、取消、重新匯入、journal 復原、不刪外部來源。所有資料使用測試 DB／獨立暫存目錄，沒有讀取或清除真實書庫。

圖片測試包含既有快取損壞／消失回退、來源變更、元件卸載，以及 2048×3072 原始解析度維持；本輪新增 ReaderFileImage 壞檔後佇列繼續執行。這些不等於 4K／超大漫畫在 Android 上的長時間記憶體認證。

原始輸出位於 `performance_results/2026-11-07-audit`：`baseline-tests.log`、`regression-before.log`、`final-tests.log`、`final-tests-perf.log`、`final-analyze.log`、`profile-build-final.log`。早期探索失敗輸出亦保留；例如第一次資料夾測試缺少等待路由動畫，已修正測試後通過。早期分析掃到備份的 110 項不是專案實際診斷總數，最終以 54 項為準。

## E. 剩餘風險與審查範圍

已檢視指定的 SettingsProvider、LatestTask、匯入／journal、資料庫、閱讀進度、路徑快取、書架、資料夾／書籍詳情、閱讀器與圖片快取／排程／元件，並執行既有縮放／控制測試。沒有宣稱逐行證明整個專案不存在錯誤。

- SQLite 交易、journal ownership、刪除後持久清理、外部來源保護已有回歸覆蓋，未做 schema 改動。不同舊版升級鏈不代表本輪全部重新逐版測試。
- 依安裝中的 Flutter SDK 原始碼確認 ImmutableBuffer 交給 codec 建立 API 後由該 API 管理；沒有因看到 buffer 就補上可能重複的 dispose。ui.Image／Codec／ImageStream 仍沿用現有生命週期。未發現需本輪強行改動的資源所有權問題，但未量測實機長時間洩漏。
- LatestTask 的 run 若拋錯會向未等待的 pump 傳播；目前唯一閱讀器呼叫點已包 try/catch，不把泛型工具可能被誤用當成已確認的閱讀器閃退。未做多餘重構。
- MethodChannel 的 active sessions 非預期 null 目前會使匯入安全失敗，而非當成空集合後清理可能仍執行的工作。原生契約相符，未以寬鬆 fallback 犧牲資料安全。
- 尚待 Android 實機驗證：SAF provider 中斷、Activity／程序重建、真正磁碟不足、匯入時被系統終止、數百頁高解析度連翻與快速縮放、快取被系統回收、峰值記憶體。
- 設定寫入失敗回復、詳情頁新增圖片空實作仍未處理。Profile build 沿用 debug signing；發佈前需正式簽章，此輪不變更應用 ID 或簽章。

## F. 最終結論

1. **已確認的三項 P0 已修復**；本輪測試範圍內沒有尚未修復的 P0 證據。不能因此保證實機完全沒有重大錯誤。設定儲存失敗處理與新增圖片空實作仍是已知功能缺口。
2. 修復最近閱讀無法再次開啟、自然排序不一致／超長數字、資料夾失敗卡住／競態／離開後更新／排序儲存失敗，以及設定載入後通知已釋放 Provider。
3. 可確認減少的是設定載入的等待入口、重複分頁風險與資料夾刷新後的重新分頁需求；**本輪沒有實測證據宣稱啟動、圖片載入、FPS 或匯入變快**。
4. 測試與 Profile 編譯支持進入日常使用試用；尚不足以無條件認定已完成 Android 長時間穩定性驗收。建議先以測試書庫完成實機驗證。
5. 下一輪前三項：**設定持久化失敗通知／重試與一致性**、**隔離 Android 書庫的 SAF 中斷／程序終止／高解析度壓測及配對 PerfLog**、**補齊詳情頁新增圖片並驗證原有進度／封面／取消安全**。
