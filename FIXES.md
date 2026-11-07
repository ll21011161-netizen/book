# GunBook 前 10 項問題修正紀錄

日期：2026-11-06。`CODE_REVIEW.md` 保留原始審查快照；本檔記錄後續實作及驗證，原報告行號不再代表修改後的位置。

## 修改內容

| 問題 | 修正方式 | 主要位置 |
|---|---|---|
| 1. 資料夾自我／巢狀移動 | UI 阻擋選取資料夾移入；資料層在 transaction 內驗證目的地及所有項目。現有 UI 僅支援單層，拒絕 folder→folder。建立資料夾與移入書籍同一交易。 | `database_helper.dart`、`bookshelf_screen.dart` |
| 2. 刪除缺少復原 | SQLite v10 新增 `file_cleanup`。先以交易移除資料並記錄清理工作，commit 後才刪檔。失敗留下工作，啟動／後續刪除可重試；commit 失敗不刪檔。子樹刪除一次交易且有 visited set。清理拒絕外部路徑及 symlink，不刪 legacy 外部來源。 | `database_helper.dart`、`category_detail_screen.dart` |
| 3. 漏頁仍回報成功 | 掃描／任一頁 copy 錯誤均終止整次匯入，檢查空檔與複製長度，保留來源。全部複製成功才提交整批書籍，沒有部分書籍被當作成功。 | `import_service.dart`、`SafImportBridge.kt` |
| 4. 匯入取消／失敗殘留 | `.imports/<session>/<book UUID>` 在建立目標目錄前持久記錄所有權；取消等待 worker 關閉串流後清理。DB 批次在同一 transaction，取消／寫入失敗全部 rollback。啟動僅清理由 journal 記錄且 DB 沒有的書籍，不掃刪未知目錄。Android 保留跨 engine 的活躍 session，防止新 engine 清理仍在寫入的目錄。 | `import_journal.dart`、`import_service.dart`、`SafImportBridge.kt` |
| 5. 原圖／預載入併發 | 閱讀圖片改用 `ReaderFileImage`，codec 建立及第一幀實際解碼共用串行佇列，動畫後續幀亦經同一佇列。預載入同時至多一個工作，pending 目標可替換；畫面圖片尚未完成、縮放、背景、多指互動或拖曳滑桿時不啟動預載。RTL 依邏輯頁碼前進。滑桿放開才跳頁。 | `reader_image.dart`、`latest_task.dart`、`manga_reader_screen.dart` |
| 6. 只在 dispose 保存進度 | 翻頁後400ms debounce、inactive／paused flush、正常返回等待 flush。寫入串行、失敗保持 dirty，後續 flush 重試；dispose 留最後一次 best effort。 | `reading_progress.dart`、`manga_reader_screen.dart` |
| 7. 刪頁後進度越界 | 資料交易中依當前頁面路徑重新定位；當前頁被刪時選後續仍存在頁，否則最後頁；空書歸零。同步更新總頁數、封面、進度。閱讀入口及 SQL 進度更新皆限制合法範圍。 | `reading_progress.dart`、`database_helper.dart`、`category_detail_screen.dart` |
| 8. 未 await SQLite | 進度、名稱、封面、資料夾封面均等待 SQL；通知在成功寫入之後，錯誤回傳給呼叫端。資料庫初始化也共用正在進行的 Future。 | `database_helper.dart` |
| 9. 合併／刷新競態 | 拖曳資料改為穩定 ID；合併後由資料通知刷新，不再按舊索引 removeAt。合併操作鎖避免重複操作；過期查詢結果依 generation 丟棄。失效目標在交易內拒絕。 | `bookshelf_screen.dart`、`database_helper.dart` |
| 10. Android 路徑授權 | Android 使用自有 ACTION_OPEN_DOCUMENT_TREE 選取，URI 直接交給 ContentResolver／DocumentsContract，在背景 worker 列舉與串流複製；沒有 URI→`/storage/...` 轉換。取得可用的持久 read grant，結束後釋放；取消在掃描及64KiB複製迴圈檢查。 | `SafImportBridge.kt`、`MainActivity.kt`、`import_service.dart` |

圖片不轉碼、不壓縮、不指定閱讀 cacheWidth／targetWidth；原始 bytes 與完整解析度保留。一般檔名保留；SAF 供應者若提供不合法、過長或重複檔名，僅對內部副本產生安全名稱。來源不變更。

## 資料庫與復原邊界

- 本次沒有啟動或安裝 App，沒有對實際手機資料庫執行升級。新版本首次開啟既有 v9 DB 時會新增 `file_cleanup` 表；不重建 items／pages，不清空書庫。
- 已損壞的舊父關聯、沒有 journal 的歷史殘留目錄不自動猜測修復或刪除，避免誤傷現有資料。
- journal 尚未清乾淨時仍保留紀錄供下次重試，磁碟不一定立即釋放。已提交書籍不會因提交後抵達的取消訊號被清除。
- 背景 flush 是 best effort。OS 未給 lifecycle callback 就立刻 kill，仍可能失去最後尚未提交的進度；不能保證每一個瞬間都已落盤。
- 全尺寸單頁若超過裝置可負擔的記憶體，仍可能失敗；本次限制的是併發與多餘請求，沒有實作 tiles，也不以降低放大畫質換取記憶體。
- 原有音量鍵、空書新增圖片、離線字型與正式簽章等其他審查項目，不在本次10項範圍內。

## 自動化驗證

`flutter test --no-pub --reporter expanded`：**28 項全部通過**。測試使用臨時目錄及 OS SQLite 的 `:memory:` DB，不接觸 gunbook.db；test-only FFI adapter 沿用鎖定的 sqflite SQL builder，沒有新增相依套件。

涵蓋：

- v9→v10新增表並保留原書籍／頁面／進度。
- 自移／巢狀／不存在目的地、建立資料夾與移入原子性。
- 刪除 commit 失敗、子樹循環、頁面重定位、空書、外部來源保護。
- 清理失敗後重試、清理查詢失敗不誤報已提交操作回滾。
- SQLite Future 與通知順序、寫入例外傳遞。
- 中途複製失敗、複製取消、提交失敗、跨256操作批次取消 rollback。
- 成功匯入保留 bytes／自然頁序，journal 僅清理自己擁有的目錄，跳過活躍 session。
- mock SAF channel 保留不透明 URI、等待 native 終止回覆才結束取消。
- 實際圖片解碼保留321×654原始像素，圖片工作串行且錯誤不阻塞後續工作。
- pending 預載入替換與 dispose、進度 debounce／順序／失敗重試。
- Widget 測試重現過期 refresh 與合併途中清單替換。

`flutter analyze --no-pub`：**0 error、9 warning、63 info，exit1**。嚴格分析不是全綠；仍有既有 unused import、無效 non-null／null fallback、deprecated API，以及本次修改檔案中的大括號等 info。沒有隱藏或關閉 lint 規則。

`pubspec.yaml`、`pubspec.lock` 未改；沒有 pub get／upgrade／clean。Flutter 工具已獲准存取 SDK lock，以完成分析、測試與建構；不再沿用原審查時的沙箱受阻結論。

完整測試、分析、建構紀錄：`%TEMP%\gunbook-fix-validation\`。

## 最終 Android 產物

兩份皆以 Flutter3.38.3、`--no-pub --target-platform android-arm64` 新建構成功，沒有安裝到手機。其他 ABI 的 Flutter engine 未在本次建構；plugin AAR 仍包含其他 ABI 的 JNI 程式庫。

| 產物 | 大小 | SHA-256 |
|---|---:|---|
| `build/app/outputs/flutter-apk/app-debug.apk` | 108,740,387 bytes | `3006ecf163dd58a2f665adf8542757aeeae854826f3f655bcd19f631147fecd8` |
| `build/app/outputs/flutter-apk/app-release.apk` | 18,933,889 bytes | `837b56b7ac41e7d6b4e5bc9471b8da7db3c7601d38d761ba7e1bc2532b42c72c` |

新Debug、Release各8個`.so`全部通過逐一PT_LOAD對齊／offset-vaddr及未壓縮ZIP起點16KiB檢查；Android build-tools36.1.0 `zipalign -c -P 16 4`兩次皆exit0。DEX亦確認包含最後版本的`activeImportSessions`處理。詳細原生檔案清單為紀錄目錄中的`apk-alignment.json`。

Release沿用專案既有的debug signing設定，這次未更換applicationId、版本號或簽章設定；正式發佈簽章仍屬原審查中的另一項工作。

## 仍需實機驗證

Pixel 6 與 S24 Ultra：全新測試安裝及保留資料升級、Download子資料夾／Documents／雲端供應者、拒絕授權、低空間、中途取消、Activity／程序重啟、刪頁後繼續閱讀、背景後進度、RTL與雙指手勢。

效能使用 Profile 比較長圖／高解析頁、快速翻頁及滑桿；記錄UI/raster幀時間、PSS及解碼事件。16 KB須在 `getconf PAGE_SIZE=16384` 的系統實際啟動，不以APK對齊檢查或手機型號代替。
