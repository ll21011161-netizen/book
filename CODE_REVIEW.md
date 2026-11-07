# GunBook（槍簿）完整程式碼審查

> 本文件保留修正前的審查快照。前10項問題已於後續任務實作修正；修改內容、測試與新建構結果請見 [FIXES.md](FIXES.md)。以下原始行號與「尚未修復」描述屬審查當時狀態。

審查日期：2026-11-06（Asia/Taipei）。專案：`C:\Users\ll210\Desktop\manga`。

本次只檢查，未修復程式、升級套件、刪除檔案、開啟使用者資料庫或執行 Migration。唯一新增的專案檔案是本報告。測試副本與分析紀錄存放於 `%TEMP%\gunbook-review-a32bcf2249cb4284a87aea86f8eff514`，未清除。行號以本次讀取的原始檔為準。

## 1. 結論與證據界線

- 已閱讀 `lib/` 全部 **26 個 Dart 檔案、4,177 行**，Android 自訂 Kotlin、Gradle、Manifest、XML 資源、兩份 pubspec 與 lock、靜態分析設定及現有測試目錄。`test/` 為空，未找到 integration tests。
- 透過本機 Dart 3.10.1 Analysis Server，在暫存副本完成 `lib/` 分析：**0 error、10 warning、51 info**。這不是執行測試或保證執行期正確。
- Flutter CLI 的 doctor、analyze、test、pub outdated 均受 SDK 鎖定檔寫入權限阻擋；完整測試及最新可解析套件清單**未取得**。
- 已讀取現有 Debug、Release APK，逐一檢查全部原生程式庫的 ELF PT_LOAD 與 APK ZIP 位置，並執行 Android `zipalign` 檢查：**兩份 APK 均符合本次檢查的 16 KB 對齊條件**。沒有實際啟動 16 KB 系統，也沒有驗證 AAB 或手機上的已安裝 APK。
- 優先風險是資料夾關聯、檔案與 DB 的跨資源一致性、匯入失敗復原、閱讀進度，以及無併發限制的原圖預載入。不能僅憑原始碼斷定卡頓來自主執行緒解碼或特定手機 GPU。
- **P0：本次沒有足夠證據認定 P0。** P1 中仍有可能讓已匯入內容遺失、消失或部分不可讀的故障路徑，必須優先處理。

問題總計 **32 項：P0 0項、P1 12項、P2 15項、P3 5項**；高可信度疑點及待實機量測者均在各項標明，不等同32項皆已在手機重現。

狀態定義：**已確認**表示程式或產物直接證實缺陷；**高可信度疑點**表示有具體失敗路徑，但尚未在 Flutter／Android 執行重現；**尚待實機驗證**表示效能、OEM 或執行期影響仍需量測。每個問題均另列自動化及裝置驗證需求。

## 2. 專案架構總覽與模組關係

```text
main.dart → SettingsProvider → MaterialApp / MainScreen
                              ├─ BookshelfScreen → SearchDel
                              │                 → FolderDetailScreen
                              │                 → CategoryDetailScreen → MangaReaderScreen
                              └─ SettingsScreen

畫面 → LibraryActions / DialogUtils（core/utils.dart）
       ├─ FilePicker → heavyImportTask → 匯入 isolate → 原始圖片副本
       └─ DatabaseHelper → SQLite items / pages → 廣播變更 → BookshelfScreen 刷新

縮圖 → AppImage → ResizeImage / Image.file(cacheWidth)
閱讀 → Image.file 原尺寸 + InteractiveViewer + FileImage 預載入
```

| 區域 | 用途與評估 |
|---|---|
| `lib/main.dart` | 初始化 200 MiB ImageCache、Provider、Google Fonts、主畫面與底部導覽。 |
| `lib/core/` | 設定、主題、字串、動畫常數、路由，以及混合 UI／匯入／資料操作的 utils。 |
| `lib/data/` | SQLite v9、目錄掃描、isolate 匯入。資料與 UI 以全域 singleton／廣播耦合。 |
| `lib/models/` | 可變 MangaBook／MangaFolder、匯入參數與取消旗標；畫面直接修改共享物件。 |
| `lib/screens/` | 書架、搜尋、資料夾、書籍頁面清單、閱讀器與設定。各自維護 loading／分頁／選取狀態。 |
| `lib/widgets/` | 圖片、書籍／資料夾卡片、輸入視窗、毛玻璃與按壓動畫。 |
| `android/` | Flutter embedding v2，只有 MainActivity 有自訂平台行為；沒有自訂 C/C++ 編譯程式碼。 |
| `assets/` | 僅 `icon/app_icon.png`（51,316 bytes）；宣告路徑存在。沒有字型或漫畫測試資料。 |
| `test/` | 空目錄；不能聲稱有自動回歸保護或覆蓋率。 |
| `ios/`、`macos/`、`linux/`、`windows/`、`web/` | 主要為 Flutter 範本／平台 scaffold。本次以 Android 為審查目標，未驗證其他平台建構；`dart:io` 圖片與 sqflite 使用方式也不代表 Web／Windows 已受支援。 |
| `flutter_application_1manga/` | 另一份殘留專案設定、Android、assets 與產物，沒有 `lib/`；不是本次主程式入口。 |

Provider 僅管理設定，沒有 LibraryRepository／ImportCoordinator。閱讀器使用 ValueNotifier 將頁碼、工具列、縮放狀態局部更新，是合理方向；PageView 和 GridView 採 builder，沒有一次建立所有漫畫圖片。大多數畫面的 Controller、Notifier、Subscription 有 dispose。問題主要在非同步工作完成後的狀態、持久化與跨模組一致性，並非所有 Widget 都缺乏釋放。

資料庫有 `(parent_id, sort_order)`、`(book_id, page_order)`、`type` 索引，啟用 WAL、foreign_keys，單本保存及分批書籍保存有 transaction／batch，SQL 值大致採參數綁定。沒有確認 SQL injection。`pages.book_id` 有 cascade，但 `items.parent_id` 沒有外鍵或階層限制。

## 3. 最值得優先處理的 10 個問題

以下以資料完整性、主要功能和效能影響排序；都尚未修改。

| 順序 | ID／優先級 | 問題 | 證據狀態 |
|---|---|---|---|
| 1 | R01／P1 | 資料夾可移入自身或另一資料夾，書籍可能從正常導覽消失 | 已確認；記憶體 SQLite 驗證 |
| 2 | R02／P1 | 刪除先動檔案再寫 DB，失敗／中斷無復原 | 已確認流程缺陷 |
| 3 | R03／P1 | 複製失敗被吞掉，缺頁漫畫仍回報匯入成功 | 已確認 |
| 4 | R04／P1 | 匯入取消、DB 失敗和程序死亡會留下未登錄圖片 | 已確認清理缺口 |
| 5 | R05／P1 | 原圖解碼加上無併發上限預載入，存在記憶體尖峰風險 | 高可信度；需量測 |
| 6 | R06／P1 | 閱讀進度只在 dispose 儲存，背景遭終止會遺失 | 已確認 |
| 7 | R07／P1 | 刪頁後不修正進度，繼續閱讀可進入不存在頁面 | 已確認未校正；畫面需驗證 |
| 8 | R08／P1 | 多個 SQLite 更新沒有 await，通知／完成早於實際寫入 | 已確認 |
| 9 | R09／P1 | 合併操作同時觸發刷新，又用舊索引修改清單 | 高可信度競態 |
| 10 | R10／P1 | SAF 選目錄後轉實體路徑掃描，與 Android 儲存授權不一致 | 已確認設計；失敗範圍待實機 |

## 4. 完整問題清單（P0～P3）

### R01 — P1：資料夾階層不受限制，允許自我移動與不可見巢狀資料夾

- **位置／證據**：`lib/screens/bookshelf/bookshelf_screen.dart:140–146` 以所有已載入資料夾當目的地，未排除選取中的資料夾；`lib/data/database_helper.dart:303–309` 直接更新 `parent_id`；`:34` 的 parent 沒有外鍵。`fetchFolderBooks`（`:166–181`）僅取 book，`FolderDetailScreen` 只顯示書籍。
- **原因／影響**：選資料夾 F 再移到 F，根目錄查詢不再顯示 F；移 F 到 G，G 內也不顯示 F。內容可能仍在 DB／磁碟，但正常導覽不可達。自我循環與一般巢狀資料夾應分別阻擋或完整支援。
- **狀態／驗證**：已確認。用原始 `items` schema 在 Python 記憶體 SQLite 執行自我移動，SQL 成功且根項目為空；沒有開啟 App DB。
- **建議**：資料層驗證目的地存在、為 folder、非自身／後代；若僅支援一層，拒絕移動 folder；createFolder＋move 放同一 transaction。
- **自動化**：可以，以記憶體 DB 驗證自移／循環／不存在父項／正常移動；**實機**：Pixel 6、S24 Ultra 做操作回歸即可，並非硬體限定問題。

### R02 — P1：刪除檔案與資料庫不是可復原的一組操作

- **位置／證據**：`lib/screens/details/category_detail_screen.dart:142–164` 先刪檔，再 `removeAt` 與 saveBook；刪檔例外只 debugPrint，仍移除 DB 頁面。`lib/data/database_helper.dart:312–332` 先刪 book 目錄，再刪 item；刪 folder 後才逐一刪 children；檔案例外完全吞掉。
- **原因／影響**：刪檔成功、DB 失敗，DB 留下缺失圖片；刪檔失敗、DB 成功，檔案永久殘留；刪資料夾中途終止，尚存 children 變成孤兒。記憶體 SQLite 已確認刪 parent 不會限制／級聯 children。大量刪除不是一個 transaction，會多次廣播並刷新書架。
- **狀態**：已確認故障路徑；未實際刪除任何漫畫。若大批內容在故障中不可恢復，事件影響可能升高，但本次不將未發生事件判為 P0。
- **建議**：採刪除工作紀錄／tombstone、隔離目錄、DB transaction 與可重試清理；不能只增加 SQL transaction 就宣稱檔案也原子化。失敗保留可復原狀態並提示。
- **自動化**：可注入刪檔失敗、DB commit 失敗及逐步中斷；**實機**：兩機驗證大量刪除、背景中斷與重新啟動後一致性。

### R03 — P1：單頁複製失敗仍產生「成功」漫畫

- **位置／證據**：`lib/data/import_service.dart:108–128` copy 的 catch 只輸出記錄，仍保存 `newPaths`；`lib/core/utils.dart:208–225` 只以回傳書籍數顯示成功。掃描錯誤在 `import_service.dart:63–71` 也被略過。
- **原因／影響**：空間不足、權限、來源檔損毀／消失時，可能漏頁卻顯示成功，使用者不知匯入不完整。掃描空目錄提示 `:74–78` 甚至將「沒掃描到」直接歸因權限，證據不足。
- **狀態**：已確認錯誤處理缺陷，未製造手機磁碟滿。
- **建議**：回傳 scanned/copied/failed 結果、來源與錯誤分類；每本完整提交或清楚標示部分成功；可用空間預檢只是輔助，仍需處理 copy 時的 ENOSPC。保留原始檔，不以轉碼壓縮換取成功。
- **自動化**：可用注入式檔案系統模擬第 N 頁失敗；**實機**：兩機驗證低空間、USB／供應者斷線、部分權限。

### R04 — P1：匯入取消及失敗的清理只涵蓋部分時段

- **位置／證據**：`lib/data/import_service.dart:155–169` 只有 isolate 執行中的取消會清理 `createdDirs`；`:184–197` done／error 關閉 timer／port，error 不清理；`lib/core/utils.dart:213–236` 每 20 本提交，後續取消／失敗只顯示提示，沒有清理未提交目錄。
- **原因／影響**：isolate 完成後再取消 DB 階段，已提交前幾批、剩餘圖片未登錄；DB 寫入失敗或程序死亡亦同。目錄先 create 再送 createdDir（`:102–104`），kill 與訊息處理間還有追蹤缺口。每次匯入採新 UUID，同來源重試會再複製一份。
- **狀態**：已確認缺少復原流程；取消競態的精確重現時機尚待測試。
- **建議**：以 import session／staging manifest 記錄所有目標，區分已提交與未提交，重啟可復原；取消在掃描、複製、DB 階段有一致定義。清理採非同步，避免 `deleteSync(recursive:true)` 卡 UI。重複匯入可先提示或允許明確另存。
- **自動化**：可以，覆蓋各階段取消、跨批 DB 失敗、重啟恢復；**實機**：兩機驗證大量檔案、kill process、低空間與取消延遲。

### R05 — P1：原圖解碼與未受限預載入可能造成尖峰記憶體及反覆解碼

- **位置／證據**：`lib/screens/reader/manga_reader_screen.dart:518–542` 原尺寸 `Image.file`；`:83–90` 每次呼叫立即 `precacheImage(FileImage(...))`，沒有排程、取消或 await；`:287–289` 滑桿連續 jump。`lib/main.dart:16` 設為 200 MiB。
- **原因／影響**：一張 6000×9000 的 4-byte 像素緩衝約 **206 MiB**，尚未計壓縮資料、解碼暫存、GPU、其他 live image。超過 cache 上限的圖未必保留，來回閱讀可能反覆解碼；快速跳頁會讓不同頁面的 pending 工作重疊。ImageCache 的 keepAlive 上限不是 App RAM 上限，live／pending 仍需觀察。[ImageCache 文件](https://api.flutter.dev/flutter/painting/ImageCache-class.html)
- **狀態**：原圖與無併發控制已確認；是否造成這兩支手機 OOM、CPU／raster 超時屬高可信度疑點，未量測。沒有證據顯示此處有同步 Dart 圖片解碼；匯入 isolate 也沒有替閱讀解碼限流。
- **建議**：先量尺寸及 Timeline，建立單一預載入排程器、至多有限張 pending、跳頁淘汰過時排程；合理保留目前頁與相鄰頁。保留原檔及放大品質；超大圖片評估原始解析度 tile／region 解碼與分層顯示，明確比較接縫／清晰度。不要直接將閱讀器一律設 150px／螢幕寬 cacheWidth，也不要任意清除仍被使用的 live image。
- **自動化**：可驗證排程、併發及 cache key；記憶體／掉幀須效能測試；**實機**：Pixel 6、S24 Ultra 均必要，含不同顯示解析度、120Hz 與長圖。

### R06 — P1：進度只在 dispose 儲存，無背景存檔

- **位置／證據**：`lib/screens/reader/manga_reader_screen.dart:55–62` dispose 才 updateProgress；`:73–81` 翻頁不存 DB；全 `lib/` 沒有 AppLifecycleListener／WidgetsBindingObserver。
- **原因／影響**：背景被系統回收、強制結束或崩潰，不保證 dispose，整段閱讀進度可能遺失。dispose 不能等待寫入，且 updateProgress 本身也沒有等待 SQL（R08）。
- **狀態**：已確認保存策略缺口；未操作使用者 App。
- **建議**：翻頁 debounce 持久化、inactive／paused 儲存、退出路由等待關鍵 flush；依 bookId 串行避免較舊寫入覆蓋較新值。
- **自動化**：可 fake clock／repository 驗證 debounce、flush、順序；**實機**：兩機驗證 Home、鎖屏、程序回收後恢復。

### R07 — P1：刪頁後 lastReadPage 可超出實際範圍

- **位置／證據**：`lib/screens/details/category_detail_screen.dart:155–164` 改頁數及封面卻不調整 lastReadPage；`:228`、`:310` 直接繼續閱讀該 index。`lib/screens/reader/manga_reader_screen.dart:40–42` 直接給 PageController，沒有 clamp 或空頁防護。
- **原因／影響**：讀到第 100 頁後刪成 10 頁，仍從 index 99 開啟；頁碼可能 100/10、初始畫面無頁或被框架行為校正，不能保證正確。空書封面也能進入 0 頁閱讀器。刪除當前頁之前的頁面還會改變進度指向內容。
- **狀態**：未校正已確認；實際空白／跳頁表現尚待 Widget／實機驗證，不斷言必定閃退。
- **建議**：刪頁時依穩定頁面識別重新定位，DB 同 transaction 更新進度；入口驗證 `0 <= index < length`，空書顯示明確空態。
- **自動化**：可驗證刪末頁、刪前頁、全部刪除及過期 DB 值；**實機**：兩機做閱讀／刪頁回歸。

### R08 — P1：SQLite 更新 Future 被丟棄

- **位置／證據**：`lib/data/database_helper.dart:292–294`、`:342–354` 的 updateProgress／updateTitle／updateCover／updateFolderCovers 都是 `(await database).update(...)`，沒有 await／return；後三者隨即 `_notify()`。
- **原因／影響**：呼叫端 `await updateTitle` 也不代表 SQL 已完成；錯誤脫離呼叫端 catch；讀取／提示可能早於持久化。sqflite 佇列可能掩蓋部分讀寫競態，但不能取代正確的完成／錯誤契約。
- **狀態**：已確認。
- **建議**：等待 SQL 成功、檢查更新列數再通知；關鍵錯誤往上傳遞。對有意 fire-and-forget 的工作使用明確錯誤處理；啟用 discarded_futures／unawaited_futures 等規則前逐處評估。
- **自動化**：可用延遲／失敗 DB double 驗證 Future 與通知順序；**實機**：兩機快速改名／改封面後重啟，主要可由自動化覆蓋。

### R09 — P1：合併時刷新與舊索引本地刪除互相競爭

- **位置／證據**：`lib/screens/bookshelf/bookshelf_screen.dart:52–54` 每個 DB 通知都 refresh；`:174–177` move 後 removeAt(dragIndex)；`:203–211` create／move 各自通知，隨後以原 dragIndex／dropIndex 刪清單。
- **原因／影響**：等待 DB 操作／命名視窗時 `_items` 可能已替換；再按舊索引移除可造成顯示錯誤、RangeError 或錯誤的後續 sort_order。沒有 mutation token 或資料版本。實際交錯需控制 Future 重現。
- **狀態**：高可信度疑點，非已重現閃退。
- **建議**：以 ID 操作；將 create＋move 原子化，操作完成後統一刷新，避免同時套用舊索引樂觀更新；異步返回檢查 mounted／資料版本。
- **自動化**：可用可控 Future 插入刷新與 drag；**實機**：兩機快速合併、多次匯入通知時回歸。

### R10 — P1：目錄選取 URI 權限沒有轉為可持續的檔案存取流程

- **位置／證據**：`lib/core/utils.dart:117` 取 `getDirectoryPath()`，`lib/data/import_service.dart:27–47` 使用 dart:io Directory。鎖定 file_picker 10.3.10 的 Android `FileUtils.kt:151` 是 ACTION_OPEN_DOCUMENT_TREE，`:84`、`:563–635` 將 tree URI 換成 `/storage/...` 路徑。專案只有 Manifest 宣告 READ_MEDIA_IMAGES／READ_EXTERNAL_STORAGE，沒有 runtime request 或 ContentResolver 讀取實作。
- **原因／影響**：SAF 的 URI grant 不等於對任意實體路徑的存取權；Android scoped storage、雲端／虛擬供應者尤其不同。不能以「搬到 Download」保證成功；Android 11+ 的 tree picker 也限制選取部分根目錄。Manifest 宣告不代表 runtime permission 已授予。[Android SAF 文件](https://developer.android.com/training/data-storage/shared/documents-files)
- **狀態**：設計已確認，特定本地目錄在已授權／既有安裝可能成功；不能聲稱所有 Android 版本均無法匯入。
- **建議**：使用 SAF tree URI 列舉／串流複製及必要的持久授權，或明確採 MediaStore＋相應 runtime 權限；不要預設要求 MANAGE_EXTERNAL_STORAGE。處理 provider 與權限錯誤，匯入來源 URI 與內部副本分開建模。
- **自動化**：可 mock ContentResolver／供應者並做 Android instrumentation；**實機**：兩機必要，測全新安裝、拒絕／部分授權、Download 子目錄、Documents、雲端供應者及 OS 更新後。

### R11 — P1：新增空漫畫後無法加入圖片

- **位置／證據**：`lib/core/utils.dart:240–250` 建立 0 頁書；`lib/screens/details/category_detail_screen.dart:114` 的 `_add() async {}` 是空函式，`:219` 按鈕連到它。
- **原因／影響**：可見的新增圖片操作完全無效，空漫畫功能不能完成其用途。
- **狀態**：已確認。
- **建議**：之後另行實作逐頁／批次加入與失敗復原；完成前不要呈現可成功操作的 UI。
- **自動化**：可做 Widget＋匯入整合測試；**實機**：兩機驗證 picker 與新增後閱讀。

### R12 — P1：音量鍵全域被攔截，但 Dart 沒有接收事件

- **位置／證據**：`android/app/src/main/kotlin/com/example/flutter_application_1manga/MainActivity.kt:19–28` 對音量鍵 invokeMethod 後 return true；全 `lib/` 沒有 `com.gunbook.volume` 或 setMethodCallHandler。
- **原因／影響**：按鍵不翻頁，書架／設定也不能正常以實體鍵調音量。平台呼叫可能產生未處理方法回應，但沒有足夠證據認定因此閃退。
- **狀態**：已確認事件鏈中斷。
- **建議**：僅閱讀器啟用按鍵接管，建立 Dart handler，路由離開時解除；未接管時走 super。
- **自動化**：可測 channel handler／啟用狀態及 Kotlin instrumentation；**實機**：兩機必要，含長按、重複事件、背景音樂和離開閱讀器。

### R13 — P2：refresh 與載入下一批允許重疊，分頁結果可過期

- **位置／證據**：書架 `bookshelf_screen.dart:76–99`、資料夾 `folder_detail_screen.dart:62–89` 都允許 refresh 繞過 loading；已有內容時 refresh 不設 `_isLoading=true`，共用可變 `_offset`，沒有 generation／requestId。
- **原因／影響**：過期分頁結果加入新清單，offset 重複累加、漏項或重複。資料變動通知與手動下拉會放大機率。資料夾在 refresh 後未重新統計完整總數。
- **狀態**：高可信度疑點。
- **建議**：每個 request 固定 offset／generation，refresh 作廢舊請求；依 ID 去重，分開 refresh/loadingMore 狀態。
- **自動化**：可控制兩個回應相反順序；**實機**：兩機測 50／51／100／101 本及匯入同時捲動。

### R14 — P2：資料夾向後拖曳使用錯誤的目標索引語意

- **位置／證據**：`lib/screens/details/folder_detail_screen.dart:107–113` 在 oldIndex < newIndex 時 `newIndex--`，但 `:308–310` 傳來的是 DragTarget 的項目索引，並非 ReorderableListView 插槽索引。
- **原因／影響**：將 index 0 拖到 1，減成 0 後完全不移動；拖到最後只能落在前一位。書架 `_onReorder` 沒有此減法，兩者語意不一致。
- **狀態**：已確認索引運算。
- **建議**：定義落在目標前／後或替換位置的單一規則，以 ID／實際目標索引操作。
- **自動化**：可測相鄰、首尾、雙方向與分頁邊界；**實機**：兩機拖曳回歸。

### R15 — P2：部分異步錯誤不結束 loading，返回後仍操作已銷毀狀態

- **位置／證據**：`category_detail_screen.dart:109–111` 讀頁沒有 catch；`:137–172` 刪頁無 try/finally，DB 失敗時非可取消 loading dialog 不關；`:121–127` await 後未檢查 mounted 就 setState／Notifier。`folder_detail_screen.dart:73–88` 無 catch，`:95–104`、`:127–133` 同樣缺 mounted。書架 `:175`、`:206` 也有此風險。
- **原因／影響**：DB error 可讓畫面持續 loading；等待時返回路由會觸發 setState after dispose／已釋放 notifier／無效 context。analyzer 在書架和刪頁已報 5 個 use_build_context_synchronously，但不會抓到全部 setState 問題。
- **狀態**：已確認缺少防護；閃退／紅畫面重現待控制時序。
- **建議**：明確 loading/error/retry 狀態、try/finally、await 後就近 mounted 檢查，讓 dialog 有自己的關閉權杖。batchImport 也應等待指定 dialog 關閉再 dispose notifier，而非以父 context 盲目 pop。
- **自動化**：可測 DB throw、返回中完成 Future、dialog route 取消；**實機**：兩機快速返回、切背景、失敗重試。

### R16 — P2：isolate 沒有 onError／onExit，異常退出可能讓匯入永久等待

- **位置／證據**：`lib/data/import_service.dart:144–153` spawn 無 onError／onExit；`:173–203` 只有收到自訂 done/error 才完成 Future。spawn 失敗也缺少 port 的 finally 清理。
- **原因／影響**：未被頂層 try 捕捉的 isolate error／意外退出沒有終止訊息，timer 與對話框可能一直等。OS 若直接終止整個 App，這套監控本身不能恢復，仍需 R04 的持久紀錄。
- **狀態**：高可信度疑點。
- **建議**：onError／onExit、單次完成 guard、終止訊息契約、finally 關 port／timer；取消不要在 UI isolate 同步遞迴刪檔。
- **自動化**：可造 worker 非預期退出／spawn error／重複終止事件；**實機**：兩機測取消與背景中斷。

### R17 — P2：RTL 預載入方向與邏輯下一頁相反

- **位置／證據**：`manga_reader_screen.dart:85` RTL 時預載 index-1；`:101–104` 下一頁則 `_pc.nextPage`，`:145` reverse 只改視覺方向。初始 index 0 在 RTL 不預載 index 1；initState 也沒有初次 warmup。
- **原因／影響**：日本漫畫模式主要前進方向沒有預熱，反而預熱前頁。 `_isInteracting` 是單一 bool，不是 pointer 計數；雙指第一指放開就可能提早預載入。
- **狀態**：方向錯誤已確認；卡頓差異尚待實機驗證。
- **建議**：以邏輯閱讀進度及最近移動方向決定預載入；用手勢／pointer 計數與限流排程，初次開啟也在適當時機預熱。
- **自動化**：可測 RTL index0→1 預載目標、多指順序；**實機**：兩機比較 RTL／LTR 冷快取前進。

### R18 — P2：翻頁、淡入與毛玻璃可能疊加 raster 成本

- **位置／證據**：`manga_reader_screen.dart:148–165` 每幀 scale＋Opacity；`:535–539` 解碼後再 AnimatedOpacity；`lib/widgets/glass_box.dart:12` BackdropFilter；`lib/main.dart:194–207` 底部 blur／shadow。
- **原因／影響**：多層合成、大畫面透明度與 blur 可能增加 GPU／raster 負荷；不是必定每幀 saveLayer，也不能從程式碼斷言 RepaintBoundary 可消除解碼或紋理上傳。閱讀器 AnimatedBuilder 已把頁面放 child，並未每幀重建 Image 子樹。
- **狀態**：尚待實機驗證的效能疑點。
- **建議**：在相同資料下逐項 A/B 關閉特效、看 raster duration／offscreen layer，再保留有效設計；不要先大規模刪動畫。
- **自動化**：可做固定動作的 profile benchmark；**實機**：兩機必要，60／120Hz 分開量測。

### R19 — P2：動畫圖片及格式辨識缺少資源策略

- **位置／證據**：`import_service.dart:56` 接受 GIF／HEIC／JFIF 等；閱讀器 `:518` 交由 Image.file 自動辨識；沒有靜態漫畫／動圖模式或解碼前格式／尺寸檢驗。
- **原因／影響**：動畫 GIF／WebP 可能持續解碼／重繪，多幀記憶體超出單張估算；HEIC 支援取決平台 codec，副檔名存在不代表一定能讀。損壞檔仍可匯入，直到閱讀才顯示 broken image。
- **狀態**：缺少策略已確認；各 codec 影響待驗證。
- **建議**：讀 metadata 後提示不支援／異常尺寸；靜態漫畫可提供首幀顯示選項並保留原始檔，不擅自降低畫質。
- **自動化**：可用損毀、超長、動畫及格式 fixture；**實機**：兩機必要，尤其 HEIC／動畫。

### R20 — P2：只要 .thumbs 目錄存在便假設全部縮圖存在

- **位置／證據**：`category_detail_screen.dart:75–86` 對整本替換路徑，沒有逐頁 exists；`:91–95` 封面反而有逐檔檢查。目前匯入流程沒有建立 `.thumbs`。
- **原因／影響**：舊版／部分產生的縮圖目錄會讓仍有原圖的頁面顯示損壞；新匯入沒有磁碟縮圖，所以瀏覽預覽仍需讀取每張原始壓縮檔。150px 解碼可以減少輸出尺寸，不等於來源 I/O 已變小。
- **狀態**：已確認邏輯；是否有使用者舊縮圖未知。
- **建議**：縮圖索引／逐檔 fallback，背景生成且可中斷；縮圖與原圖分開，不修改閱讀原檔。
- **自動化**：可測 0／部分／完整縮圖及毀損縮圖；**實機**：兩機比較書籍頁面清單冷載入。

### R21 — P2：設定載入與寫入沒有穩定的錯誤／時序控制

- **位置／證據**：`lib/core/settings_provider.dart:21–26` 未 catch 載入錯誤；`:29–44` 每次 slider 更新就寫 prefs、notify，且忽略回傳 Future；讀值沒有 clamp。`settings_screen.dart:98–101` 連續 onChanged；`main.dart:33–62` 每次設定變動重建主題與字型。
- **原因／影響**：初始化失敗時 reader 因 isLoaded=false 一直黑屏；載入期間操作可能被舊設定覆蓋；大量無等待寫入及全域 rebuild 浪費資源；異常 zoom 值可超出 Slider 範圍。Provider 非同步完成後也沒有 disposed 防護。
- **狀態**：已確認缺少控制，實際儲存失敗／載入競態待測。
- **建議**：初始化明確成功／降級狀態、值驗證；持久化 debounce／onChangeEnd 串行並處理失敗；Selector／分拆主題與閱讀設定訂閱。
- **自動化**：可用 mocked prefs／clock／dispose 時序；**實機**：兩機拖曳設定、立刻重啟與深色冷啟動。

### R22 — P2：離線本地閱讀器依賴未打包的 Google Fonts

- **位置／證據**：`lib/main.dart:37–54`、`lib/core/theme.dart:61–70` 使用 Noto Sans TC；`pubspec.yaml:46–47` 只有 icon。Release merged Manifest 沒有 INTERNET；Debug／Profile Manifest 才宣告 INTERNET。
- **原因／影響**：無內建字型且冷快取時會嘗試 runtime fetching；Release 無網路權限／離線時字型下載失敗，可能 fallback、非預期字重與錯誤記錄。這不是已確認的 App 必定閃退。套件支援資源字型優先及關閉 runtime fetch。[Google Fonts 套件文件](https://pub.dev/packages/google_fonts)
- **狀態**：已確認資源與權限差異，具體視覺待 release 冷啟動。
- **建議**：為離線用途打包授權允許的字型、設定 fetch 策略並驗證所有字重；不必為本地 App 任意增加網路權限。
- **自動化**：可測字型 asset 載入／無網路；**實機**：兩機全新 Release 安裝、飛航模式，不清除現有使用者資料來測。

### R23 — P2：Release 使用 debug signing

- **位置／證據**：`android/app/build.gradle.kts:35–39` release 的 signingConfig 指向 debug。
- **原因／影響**：目前開發安裝可用，但正式發佈身分／金鑰穩定性及跨環境更新不可依賴 debug key；改簽若與既有安裝不同可能無法直接覆蓋更新，不應要求使用者先刪 App。
- **狀態**：已確認設定；未認定憑證外洩或遠端攻擊。
- **建議**：正式發佈前制定 release key／備份／更新路徑；記錄已安裝簽章並先保護漫畫資料。applicationId 仍是範本名稱，另行評估正式命名，不在修效能時順便改。
- **自動化**：可檢查產物 signing certificate；**實機**：兩機驗證保留資料的升級安裝。

### R24 — P2：資料夾封面顯示與儲存結果可能不同步

- **位置／證據**：`folder_detail_screen.dart:167–178` 存 covers 後只改 coverBookIds，沒更新 final thumbnails，也未呼叫 onUpdate；背景 `:183–184` 用原 thumbnails。`database_helper.dart:130–139`、`:402–411` 以 IN 查封面，沒有還原使用者選取順序／限定 parent。
- **原因／影響**：儲存後原畫面與書架仍顯示舊封面；書籍移出資料夾後，舊 coverBookIds 仍可引用它。刪除／移動不清理封面引用，且 DB 無關聯約束。
- **狀態**：已確認更新缺口。
- **建議**：以 ordered ID relation／映射還原順序，規定封面是否可跨資料夾；成功後重新取得資料並通知父畫面，刪除／移動時更新引用。
- **自動化**：可測順序、刪除、移出與 save 後畫面更新；**實機**：兩機操作回歸。

### R25 — P2：沒有自動化測試保護高風險操作

- **位置／證據**：`test/` 空；`pubspec.yaml:25–31` 有 flutter_test，沒有現存測試可執行。專案無測試隔離與故障注入介面。
- **原因／影響**：資料刪除、匯入取消、Migration、頁碼及競態都沒有回歸防線；0 analyzer error 無法證明這些正確。
- **狀態**：已確認；沒有量測 coverage，不能報「覆蓋率通過」。
- **建議**：先建立第 8 節的失敗路徑測試，僅對 fixture／暫存 DB；效能用 profile integration benchmark。測試前不要對真實 DB migration。
- **自動化**：本項即需補測；**實機**：Pixel 6 與 S24 Ultra 的裝置整合測試不可省略。

### R26 — P3：未使用的直接相依性增加解析／平台成本

- **位置／證據**：`pubspec.yaml:14`、`:20–23` 的 path_provider、flutter_staggered_animations、fluid_bottom_nav_bar、image 在 `lib/` 無 package import。path_provider 可能被其他套件間接使用，不能直接宣稱移除後完全消失。fluid 帶入舊 flutter_svg 1.1.6（lock `:185–192`）。
- **原因／影響**：維護者誤認 image 已用來背景解碼；多餘直接限制擴大解析面，原生 plugin／JNI 的實際去留要看 transitive graph，不能只靠 Dart tree shaking 推定。
- **狀態**：直接未引用已確認。
- **建議**：後續逐一核對依賴圖再移除無用宣告；本次不執行 pub get／upgrade。
- **自動化**：可做 import／dependency audit 及三模式建構；**實機**：移除後兩機 smoke test 即可。

### R27 — P3：死程式與重複查詢／輸入流程增加誤判

- **位置／證據**：`screens/reader/smooth_zoom.dart:5` 的 SmoothScopeZoom 沒有外部引用；`file_scanner.dart:23` scanImages 未呼叫（compareNatural 有使用）；`core/utils.dart:18` Debouncer 未使用；`config.dart:16` memoryEvictDistance 未使用。database_helper 的 getBookFull／fetchTopBooks 無呼叫。fetchItems 與 searchItems 重複 folder cover 組裝，DialogUtils.showInput 與 SmoothInputDialog 重複輸入行為。
- **原因／影響**：`_manageMemory` 名稱暗示會回收，實際僅預載入；註解如「保證絕對滑順」沒有量測證據。維護者可能修改未生效的舊縮放元件。
- **狀態**：已確認本專案內引用結果。
- **建議**：確認產品用途後整理未用 API，集中重複邏輯；優先更新具誤導性的命名與註解，不先大重構。
- **自動化**：可檢查引用與重構後回歸；**實機**：非必要，行為改動時兩機 smoke test。

### R28 — P3：lint 已累積，現有規則未涵蓋關鍵 Future 契約

- **位置／證據**：`analysis_options.yaml:10` 只有 flutter_lints；直接分析結果有 10 warning／51 info，包括 7 unused_import、1 無效 non-null assertion、1 未使用 key 參數、1 dead_null_aware_expression；另有 29 deprecated_member_use、9 大括號、5 async context 等。
- **原因／影響**：警告噪音掩蓋真風險；Future 被丟棄不一定由預設規則抓到。`smooth_input_dialog.dart:84` 的 `AppStrings.get(...) ?? ...` 右側永遠不執行。
- **狀態**：已確認 analyzer 診斷。withOpacity／Matrix4 舊 API 的 deprecated 本身不是當前閃退原因。
- **建議**：先修 correctness lints，再整理樣式；逐步加入 Future 規則與 CI gate，不自動套用全專案格式／fix。
- **自動化**：可重跑 analyzer；**實機**：純 lint 整理不需，API 行為變更再測。

### R29 — P3：宣告最低 SDK 與實際鎖定需求不一致，工具鏈缺乏專案釘選

- **位置／證據**：`pubspec.yaml:7` 宣告 Dart >=3.2；`pubspec.lock:688–690` 實際要求 Dart >=3.10、Flutter >=3.38。Android 使用 `flutter.*SdkVersion`、`flutter.ndkVersion`；沒有 FVM／等效版本釘選。
- **原因／影響**：依 README／pubspec 以較舊 SDK 開啟不代表能解析／建構。升級 Flutter 會隱含改變 Android SDK／NDK。launcher icon 的 min_sdk_android 21（yaml `:39`）不是執行時 minSdk；本機實際是24。
- **狀態**：已確認設定差異，不表示目前 SDK 不相容。
- **建議**：文件列出測試過的 Flutter／Dart／Java 版本，對齊實際最低限制；工具鏈釘選與升級獨立評估。
- **自動化**：可在乾淨 CI／指定 SDK 建構；**實機**：工具鏈變更後兩機驗證。

### R30 — P3：巢狀舊專案與版本控制邊界不清楚

- **位置／證據**：`flutter_application_1manga/pubspec.yaml`／Android／assets 存在但無 lib；根 README 是 Flutter 起始範本。根與巢狀目錄沒有找到 AGENTS.md。`git status` 顯示搜尋到使用者家目錄層級的 repository，未證實本專案有獨立可比較的 commit；因此後續改用檔案 SHA-256 驗證。
- **原因／影響**：容易在錯誤目錄執行、引用舊 APK、以不相關 Git 差異判斷改動；缺少可重現建構／資料備份說明。
- **狀態**：已確認結構；沒有刪除舊專案，也不認定其中產物就是手機警告來源。
- **建議**：之後確認唯一工作區入口及版本控制根，記錄既有副本用途；保留備份後再由使用者決定整理。
- **自動化**：可驗證 CI 工作目錄及必要入口；**實機**：非必要，產物辨識見第6節。

### R31 — P2：搜尋每次 build 建立新查詢且缺少 debounce

- **位置／證據**：`search_delegate.dart:41–44` 在 FutureBuilder 的 future 直接呼叫 searchItems；`database_helper.dart:381–387` `%keyword%` LIKE、limit100；自訂 folder 封面逐資料夾另查一次。
- **原因／影響**：鍵入／其他 rebuild 重複查詢與 loading 閃爍；前置萬用字元通常無法利用一般標題 B-tree 索引。大量資料時加重 DB 負荷，但目前沒有資料量／查詢時間證據。FutureBuilder 本身有過期 Future 管理，不能據此斷言舊搜尋結果必定覆蓋新結果。
- **狀態**：重複查詢設計已確認；效能影響待量測。
- **建議**：以 query 維護穩定 Future、debounce；大量書籍再評估 FTS／預先正規化，明示100筆上限與載入更多。
- **自動化**：可驗證查詢次數／debounce／結果上限；**實機**：兩機測大型書庫快速打字。

### R32 — P2：縮圖解碼尺寸固定，未依 DPR／顯示大小調整

- **位置／證據**：`core/config.dart:14–15` 固定150／80像素；`app_image.dart:26–40` 直接作 cacheWidth；書架4欄、Hero 詳細封面800px。
- **原因／影響**：高 DPR／高解析度螢幕縮圖可能模糊；寬800px封面與80px資料夾拼圖會各有 cache key。150px僅限制寬，極長圖的縮圖高度／記憶體仍可很大。這只涉及瀏覽縮圖，閱讀器目前仍用原圖。
- **狀態**：尺寸策略已確認；視覺／資源影響待實機。
- **建議**：按 layout physical pixels 分級解碼，長圖產生符合縮圖用途的裁切預覽；保留閱讀原圖。不要為改善縮圖而改寫原始漫畫。
- **自動化**：可測 DPR、aspect ratio、cache key；**實機**：S24 Ultra 不同解析度與 Pixel 6 比較可讀性。

## 5. 漫畫卡頓的潛在原因與畫質原則

目前沒有 Timeline／FPS／PSS 實測，以下是有程式碼依據的排序，並非已證實的瓶頸排名：

1. **原尺寸圖片的解碼、紋理上傳與記憶體壓力（R05）**：高解析度頁可能比整個 keepAlive cache 大；來回翻頁可能重新載入。不要用磁碟 JPEG 的1–5MB大小估算解碼後記憶體。
2. **滑桿／連續跳頁的多張 pending 工作（R05）**：`_manageMemory` 沒有真正回收記憶體；pointerUp、onPageChanged 均可能請求，重複同 key 通常可合併，但不同頁仍可能累積。
3. **RTL 預載錯方向及初頁沒有預熱（R17）**：造成冷頁更容易顯示解碼等待。
4. **alpha、scale、淡入、blur 的合成成本（R18）**：需看 raster track；不把所有慢幀歸因 Dart rebuild。
5. **預覽讀取原壓縮圖片與動畫圖（R19、R20、R32）**：縮小解碼不代表無 I/O；動圖還有持續工作。
6. **資料通知／設定 rebuild 和 UI isolate 同步刪除（R04、R09、R13、R21）**：影響匯入／瀏覽／設定；閱讀器沒有每次頁碼變更整頁 setState，這點應保留。

建議採「保留原圖、控制工作量、按需提高顯示解析度」；若引入分層圖，放大時必須有可確認的原始細節替換，不讓低解析度預覽成為最終畫面。對超大長圖，完整解析度 tiles 往往比一次持有整張高解析度 bitmap 更可控，但需要另行原生／套件評估及品質測試，尚未選定實作。

## 6. Android 設定與 16 KB 相容性分析

### 6.1 本機可證實的工具鏈

| 項目 | 本次證據 |
|---|---|
| Flutter | 本機 cache version JSON：3.38.3 stable，framework 19074d12f7eaf6a8180cd4036a430c1d76de904e |
| Engine | 13e658725ddaa270601426d1485636157e38c34c；既有 sdkDependencies 亦指向此版本 |
| Dart | 直接 `dart.exe --version`：3.10.1 |
| AGP／Kotlin plugin | `android/settings.gradle.kts:21–22`：8.11.1／2.2.20 |
| Gradle | wrapper 8.14；直接現有 distribution `--version --offline` 成功，內建 Kotlin2.0.21不等於 App 的 Kotlin plugin2.2.20 |
| Java | Temurin OpenJDK17.0.17，source／target／jvmTarget17 |
| compileSdk／targetSdk／minSdk | 本機 FlutterExtension.kt:23／26／34：36／36／24；既有 Release merged Manifest 證實 min24、target36 |
| NDK | FlutterExtension.kt:42：28.2.13676358；本機已安裝相同版本 |
| Android build-tools | 本機35.0.0、36.1.0；本次 zipalign 使用36.1.0 |

AGP8.11 官方最低 Gradle8.13、JDK17、最高支援 API36，與本專案本機設定沒有明顯靜態衝突；沒有完成 fresh build，所以不能判定所有 plugin 建構均已通過。[AGP8.11 官方相容表](https://developer.android.com/build/releases/agp-8-11-0-release-notes)

Android 官方將「ELF segment 對齊」、「APK／AAB 包裝對齊」、「原生執行期不假設固定頁大小」分開檢查。AGP8.5.1+／NDK r28+ 可改善預設，但不會重新編譯第三方預建 `.so`；只改 ndkVersion 不能修正已下載的 Flutter engine／AndroidX 二進位。[16 KB 官方指引](https://developer.android.com/guide/practices/page-sizes)

### 6.2 既有 APK 的實際結果

| 產物 | 檔案大小／本機修改時間（台北） | SHA-256 |
|---|---|---|
| `build/app/outputs/flutter-apk/app-debug.apk` | 85,950,339 bytes；2026-11-06 00:05:32 | `cb55f169f9a8f919944127d08c0578984419c720103930090b602de99c5ccd13` |
| `build/app/outputs/flutter-apk/app-release.apk` | 52,112,867 bytes；2026-11-06 00:03:01 | `23c3ac45a13b134257697e0764037f13eff8a51e9f4289f4e4d2faa02814ecfa` |

Python 直接在 ZIP 讀取 ELF header／program headers，檢查每一 PT_LOAD 的 p_align 與 offset-vaddr 在16384下的餘數；另讀 ZIP local file header 計算實際資料位置。Debug8個 `.so`、Release12個 `.so` 全部通過本次條件；均未壓縮且資料起點為16384倍數。Android `zipalign.exe -c -P 16 4 <apk>` 對兩份檔案 exit0。沒有修改或重新封裝 APK。

| 函式庫 | Debug | Release | 本次 ELF 對齊 |
|---|---|---|---|
| `libdatastore_shared_counter.so` | arm64-v8a／armeabi-v7a／x86_64 | 同左 | 全部 PT_LOAD `0x4000`（16KiB） |
| `libVkLayer_khronos_validation.so` | 僅 arm64-v8a | 不存在 | `0x10000`（64KiB），同樣符合16KiB邊界 |
| `libflutter.so` | 僅 arm64-v8a | arm64-v8a／armeabi-v7a／x86_64 | `0x10000` |
| `libapp.so` | 無 AOT libapp | 三 ABI | arm32為`0x4000`，其餘`0x10000` |
| `libdartjni.so` | 三 ABI | 三 ABI | `0x4000` |

注意：32-bit ABI 的對齊也已列出，但 Android 的16 KB支援重點是64-bit，不能用32-bit結果代替arm64驗證。本次未檢查 RELRO 的完整安全性或 native allocator 的所有假設；「alignment pass」不是完整 runtime 相容證明。

### 6.3 三個指定函式庫的來源與可能處理方式

**libdatastore_shared_counter.so**

- 鏈：`shared_preferences`2.5.5 → `shared_preferences_android`2.4.23 → AndroidX DataStore／preferences1.1.7 → datastore-core-android1.1.7 AAR JNI。
- 本機 plugin 的 `android/build.gradle.kts` 明確宣告1.1.7；現有 Release `sdkDependencies.txt:722–890` 也是1.1.7。
- 從本機1.1.7 AAR取出的 arm64 `.so` 與兩份 APK 的 arm64檔案 SHA-256一致，前16碼皆 `d3e48717c9aa147e`；arm32／x86_64亦一致。來源可直接確認。
- plugin2.4.20曾升DataStore1.2.0，2.4.21因16 KB regression退回1.1.7；目前2.4.23已包含回退。本機舊1.2.0 AAR的arm64 ELF檢查其實也符合16 KB，說明不能把歷史regression一概等同「所有1.2.0 ELF皆未對齊」。[shared_preferences_android changelog](https://pub.dev/packages/shared_preferences_android/changelog)
- 因此本專案目前沒有需要盲目 downgrade／force DataStore的證據。若手機仍告警，先比對實際安裝 APK、解析版本與 ABI；未來升級需對 Flutter最低版本、release JNI／R8及16 KB runtime一起測。即使App使用legacy SharedPreferences API，Gradle依賴仍可能把DataStore `.so`包入。

**libVkLayer_khronos_validation.so**

- 來自Flutter engine的Vulkan validation layer。已在本機 io.flutter arm64_v8a_debug、engine版本13e658...的原生JAR確認含 `lib/arm64-v8a/libVkLayer_khronos_validation.so`（未剝符號約233MB）；APK的已剝符號檔約15.25MB。Flutter engine建構腳本明確把validation native library加入engine artifact。[Engine BUILD.gn](https://chromium.googlesource.com/external/github.com/flutter/flutter/+/43b94a8ee0b81137ee209944d97d15827e78cd03/engine/src/flutter/shell/platform/android/BUILD.gn)
- 既有Release沒有此檔，Debug有且已對齊。不要為了消除Debug警告就任意exclude／刪除 `.so`；先判定是哪份engine／artifact有問題。若舊SDK產物未對齊，更新經測試的Flutter engine版本再重建驗證，而非期待App NDK重編譯它。
- 本次不以網路另一commit的程式碼當作本機完全相同的設定；來源主要由本機JAR與Gradle依賴佐證。

**libflutter.so**

- 來自Flutter engine預建原生JAR／Maven artifact，本機Debug JAR同時包含約358MB未剝符號版本；Release對應獨立artifact。不是image Dart套件或App自訂NDK程式產生。
- Debug與Release的大小／編譯模式本來就不同；本次APK皆64KiB PT_LOAD對齊。若其他產物失敗，確認framework／engine版本和下載快取來源，選經驗證支援16 KB的Flutter版本重建；不手動patch二進位或僅改App linker flags。

**額外發現 libdartjni.so**：本機path_provider_android2.3.1使用dartPluginClass且依賴jni／jni_flutter；lock含jni1.1.2、jni_flutter1.0.4+1。這條JNI鏈亦必須納入16 KB檢查；目前APK的該檔已通過。它不能因「App沒寫C++」而被忽略。

### 6.4 Debug／Profile／Release 與警告判讀

- Debug不是效能基準；包含JIT／開發服務與可能的validation layer。Profile適合Timeline；Release代表最終AOT／R8／簽章行為。沒有Profile APK，不能推測Profile的native檔案清單。
- 兩份既有APK時間接近，但沒有本次fresh build／source commit對應，不能保證與目前程式逐位元一致，也不能代表S24 Ultra上已安裝版本。
- 沒有AAB，無法執行 `bundletool dump config` 或檢查Play生成split APK；APK通過不自動代表AAB包裝通過。
- 下一次告警應記錄：包名、versionCode、APK SHA-256、ABI、OS build、`adb shell getconf PAGE_SIZE`、告警文字及未對齊的實際library。PAGE_SIZE=4096的Pixel6／S24 Ultra實測不能宣稱已驗證16 KB；需另外以16384環境執行，不能只看手機型號。
- 本次未執行adb devices／啟動adb server／連線手機，避免改動現有裝置作業狀態。

### 6.5 其他Android相容性

`manga_reader_screen.dart:44` 嘗試immersiveSticky，離開時`:57–58`切edgeToEdge並固定明亮模式system style；深色模式返回可能圖示對比錯誤。target36的全螢幕／edge-to-edge效果依平台支援而定，不能假設此呼叫一定隱藏系統列；Flutter API文件指出target36+的模式限制。需在兩機實際OS版本、手勢與三鍵導覽、鍵盤返回／背景恢復測試；不為此直接降target或加入已失效的opt-out。[SystemChrome文件](https://api.flutter.dev/flutter/services/SystemChrome/setEnabledSystemUIMode.html)

## 7. 測試結果、執行方式與限制

### 7.1 執行紀錄

先複製lib／test／assets／android／pubspec／lock／analysis_options／metadata／既有package_config至暫存目錄。啟用 `FLUTTER_SUPPRESS_ANALYTICS=true`、`CI=true`，沒有執行pub get／upgrade／clean。

| 檢查 | 結果與限制 |
|---|---|
| `flutter --no-version-check doctor -v` | 標準bat啟動沒有輸出，已中止；檢查發現bat會嘗試寫SDK cache lock並在失敗時迴圈。改以現有Dart執行flutter_tools.snapshot，exit1：無法開啟 `C:\src\flutter\bin\cache\lockfile`。未取得完整doctor結果，不能聲稱Android licenses／裝置連線正常。 |
| `flutter analyze --no-pub` | 透過同版本現有snapshot執行，exit1，同SDK lock權限；CLI未完成。 |
| `flutter test --no-pub` | 同樣exit1，未進入測試；且test目錄沒有測試檔，不能視為通過。 |
| `flutter pub outdated` | 同樣exit1，未查詢可解析版本；不提供推測的Current／Upgradable／Resolvable／Latest表。 |
| `dart --suppress-analytics analyze --format=machine lib` | exit1，啟動analysis_server子程序時CreateFile failed5／拒絕存取。 |
| 直接Analysis Server | **完成**。以本機dartaotruntime執行analysis_server_aot snapshot，設定analysis roots為副本lib，使用專案規則與原package config；等待isAnalyzing由true變false，收集diagnostics：0 error／10 warning／51 info。沒有執行程式邏輯。 |
| `dart.exe --version`、`dartaotruntime.exe --version` | 成功，Dart3.10.1。 |
| `java -version` | 成功，Temurin17.0.17。 |
| 現有Gradle distribution `--version --offline --gradle-user-home <temp>` | 成功，Gradle8.14／JDK17；只查版本，未配置或建構App。 |
| 既有APK ELF／ZIP＋zipalign | 完成，Debug8／Release12個so均通過本次alignment；兩次zipalign exit0。 |
| 記憶體SQLite probe | 完成，僅`:memory:`，證實自我移動可接受、刪parent留下child；不是sqflite Android端測試或Migration測試。 |
| fresh Android build／Gradle dependency resolution | **未執行**；完整build會寫SDK／Gradle／plugin cache及產物，且本環境已有SDK權限限制。只讀現有manifest、依賴產物與SDK設定，不把舊APK當作本次建構通過。 |
| Pixel6／S24 Ultra／16 KB模擬器 | 未執行，無FPS、PSS、CPU／GPU trace或實機功能通過結論。 |

未繞過SDK lock或修改SDK權限。工具問題是本審查沙箱的限制，不能據此認定使用者在VS Code的正常開發環境也壞掉。

### 7.2 靜態診斷明細

| 類型 | 數量 | 代表位置 |
|---|---:|---|
| unused_import（warning） | 7 | search_delegate:6；category_detail:7、11；folder_detail:5；book_card:5；folder_card:5；smooth_input_dialog:4 |
| unnecessary_non_null_assertion（warning） | 1 | folder_detail:129 |
| unused_element_parameter（warning） | 1 | manga_reader_screen:370 |
| dead_null_aware_expression（warning） | 1 | smooth_input_dialog:84 |
| deprecated_member_use（info） | 29 | withOpacity、Matrix4 translate／scale、DragTarget舊callback、Switch.activeColor |
| curly_braces_in_flow_control_structures（info） | 9 | database_helper、bookshelf_screen |
| use_build_context_synchronously（info） | 5 | bookshelf:145、179、213；category_detail:140、172 |
| use_super_parameters（info） | 5 | app_image、book_card、folder_card、category_detail |
| no_leading_underscores_for_local_identifiers（info） | 2 | manga_reader_screen:117、118 |
| unnecessary_import（info） | 1 | core/utils:4 |

### 7.3 檢查完成不代表已證實的事項

沒有證實：真實OOM／記憶體洩漏、GC頻率、UI/raster哪一端掉幀、16 KB執行期相容、Samsung專屬問題、實際來源圖片尺寸／格式分布、真實書庫資料量、歷史資料庫是否存在孤兒／不合法值、手機已安裝版本、測試覆蓋率或全套件最新可用版本。未讀取或外傳使用者漫畫內容。

## 8. SQLite、Migration 與資料完整性專項

目前schema v9。`onCreate`直接建最新表；v2–v8逐欄補上與索引，v9建立pages_new、複製、drop／rename；sqflite的onCreate／onUpgrade本身有transaction語意，不應僅因程式沒有額外transaction就判為非原子Migration。這次沒有開DB或執行升級。

仍需驗證：

1. v1–v8每個版本的真實schema fixture升級到9；尤其外鍵啟用時，舊pages若有孤兒book_id，`:75` INSERT可能失敗；這是條件式風險，未證實現有使用者資料有孤兒。
2. `items.parent_id`沒有FK、CHECK(type)、NOT NULL／pages唯一(book_id,page_order)等約束；需要先訂資料模型、審核舊資料，再決定migration，而非直接加約束。
3. `saveBook`在transaction外先count，`saveBooksBatch`／moveItems在外先讀MAX；併發操作可產生相同sort_order或競爭。查詢僅sort_order排序缺穩定ID次序；先用可控並行測試確認產品影響。
4. 重命名目前只改DB title，不改實體UUID目錄，方向合理；真正缺陷是R08的未await。移動也只改邏輯parent，不需搬圖片。
5. 路徑是絕對私有目錄字串；跨安裝／備份恢復後路徑可能改變，尚無路徑遷移／備份策略。應以root＋relative path或可驗證重定位策略設計，不能現在掃描真實DB並自動改路徑。
6. `_db ??= await _initDB()`沒有memoize in-flight Future；sqflite預設singleInstance可能避免多個實體連線，但不能據此把應用層初始化／關閉生命週期視為完整。全域DB／廣播在整個App常駐屬可理解設計，不直接判為洩漏。

建議先對暫存fixture補測：新增／取頁／更新／刪除cascade、父關聯、順序、進度、讀次數、批量保存rollback、重命名失敗、封面引用、外鍵違反、各歷史版本migration、程序中斷後復原。檔案系統＋DB的故障測試應與純SQL transaction測試分開。

匯入掃描補充：目前先把所有圖片路徑存入folderImagesMap，再逐本順序copy，最後一次回傳全部頁面路徑。沒有一次讀完整本圖片bytes，這是優點；但路徑／batch資料量仍隨整個來源成長，20本一批不是固定頁數或固定記憶體上限。recursive=true、followLinks=false可避免跟隨symlink遞迴；只略過檔名以點開頭，沒有排除`.thumbs`等隱藏目錄內容，來源有預覽資料夾時需納入重複匯入驗證。書籍資料夾順序使用目錄列舉／Map插入順序，未做穩定自然排序；頁面有compareNatural，但大小寫／前導零相等時沒有次要排序，需用實際命名fixture確立規則，不能宣稱所有輸入都會得到唯一穩定頁序。這些是後續匯入測試與規格確認項，不是本次已觀察到使用者漫畫亂序的證據。

## 9. 建議修復順序

1. **建立資料保護基線**：確認主專案／裝置APK身分、使用者資料備份與fixture；先加入高風險回歸測試，不對真實DB跑migration。
2. **R01、R02、R08**：限制父關聯、修正Future完成契約、設計可復原刪除。先阻止新孤兒與不可見內容。
3. **R03、R04、R10、R16**：匯入結果必須真實、取消有一致語意、SAF存取與持久工作紀錄完整；包含低空間測試。
4. **R06、R07**：可靠進度保存、刪頁後重新定位與空書保護。
5. **R09、R13–R15**：移除清單索引競態、統一刷新、錯誤與loading生命週期。
6. **R11、R12**：完成明確失效的新增圖片與音量鍵功能。
7. **先量測再修R05、R17–R20、R32**：建立可比較的Profile基線，優先限流／方向／原圖按需策略，再決定tile解碼，不減損最終放大畫質。
8. **Android發佈驗證**：以固定工具鏈生成新的Profile／Release／AAB，重新測全部so／ZIP及真16 KB runtime；目前沒有證據需要先降DataStore或換NDK。
9. **R21–R24、R31**：設定訂閱／字型／封面／搜尋／簽章。
10. **R26–R30**：清理無用相依、死程式、lint與文件，在功能正確後逐步改善架構。

以上是修復建議，不是本次已執行事項。每一階段應形成可單獨審查的小改動，禁止順手大規模重構、變更App身分或清除漫畫資料。

## 10. 後續效能與裝置測試計畫

### 10.1 固定環境與資料

- 記錄兩機OS／build、裝置RAM、App版本／簽章／SHA、PAGE_SIZE、螢幕解析度／刷新率、是否省電／過熱、Flutter／engine版本。Pixel6不可代替S24 Ultra；兩者4 KB結果也不可代替16 KB系統。
- 新建獨立測試安裝／測試資料，不清除現有書庫。測試圖片採合法fixture：一般2000×3000、高解析4000×6000、6000×9000、極長圖、跨頁、損毀、GIF／動畫WebP、HEIC；每組至少數百頁、書架含50／51／1000本。
- 分開冷cache與暖cache。只有隔離測試安裝可重置cache，不清使用者資料。放大品質以原圖細字／線條／網點在相同縮放和相同實體像素下比對。

### 10.2 動作矩陣

| 動作 | 必記數據／驗證 |
|---|---|
| 冷啟動／書架快速滑動／搜尋 | 首屏時間、DB查詢數／p95時間、UI/raster frame time、font failure |
| 開書、連翻100頁、快速反向 | 首張顯示時間、解碼／紋理事件、掉幀比例、cache命中、pending／live數 |
| RTL與LTR相同序列 | 下一頁預載入命中率、等待空白時間 |
| 滑桿從頭到尾快速來回10次 | pending峰值、解碼併發、取消過期工作、峰值PSS／RSS／GPU相關記憶體 |
| 連續雙擊／雙指縮放拖曳 | raster p95／p99、手勢衝突、恢復翻頁、原始細節品質 |
| 進入背景30秒／鎖屏／程序終止後重啟 | 進度保存、系統列／縮放狀態、無已銷毀notifier操作 |
| 大量匯入、低空間、階段取消 | 每階段耗時、UI是否被deleteSync阻塞、來源／目標頁數、孤兒目錄數 |
| 新Release／16 KB環境安裝啟動 | 所有ABI的ELF／ZIP／AAB、JNI載入、prefs讀寫、SQLite及圖片讀取 |

### 10.3 工具與成功條件

使用Flutter Profile＋DevTools Performance／Memory、FrameTiming，必要時Perfetto及`adb shell dumpsys meminfo <package>`；只在使用者允許連線裝置後執行。UI與raster分開看，60Hz每幀16.67ms、120Hz8.33ms是預算；收集p50／p95／p99與最差幀，至少3次相同序列並記錄溫度。

最初先建立基線，不捏造預期提升百分比。建議驗收：連續閱讀與跳頁後記憶體回到穩定區間、無持續成長／OOM；每次存檔或匯入回報與DB／檔案一致；所有來源頁成功／失敗可追蹤；背景重啟進度符合最後一次成功flush；任何效能改善均不能以可見的放大細節流失交換。比較一次只變更一項策略，避免無法歸因。

## 11. 整體架構與可維護性評估

這是可以逐步改善的小型分層Flutter App。分頁builder、局部ValueNotifier、縮圖與閱讀原圖分開、SQLite索引／batch／WAL、匯入放isolate，已有合理基礎。沒有足夠證據支持立即換整套狀態管理框架或資料庫。

主要缺口是業務操作分散在Widget與core/utils、資料模型可變且由多個路由共享、全域DB通知太粗、缺少操作完成與失敗復原契約。建議先抽出少量可測的Repository／匯入與刪除協調介面，把「狀態轉換、錯誤、取消、持久化」集中管理；Widget保留呈現與互動，Provider先按實際更新範圍拆訂閱。這些都應以修復具體問題為界，避免大型重構。

本報告提交後，等待使用者決定下一步；尚未進行任何修復。
