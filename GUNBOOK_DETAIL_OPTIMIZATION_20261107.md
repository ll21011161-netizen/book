# 槍簿詳情轉場與縮圖優化驗證

日期：2026-11-07。基準為本次開始時的工作區，保留先前修改及輕量按壓動畫。原始碼快照、差異、測試與 Profile 紀錄位於 `performance_results/2026-11-07-detail/`。

## 修改檔案

| 檔案 | 改善項目 |
|---|---|
| `lib/core/anim_route.dart` | 新增 DetailRoute，專用淡入淡出、立即導航、減少動畫與首幀紀錄；透過公開 route gesture API 處理 Android 預測返回。其他 AnimRoute 保留原設定。 |
| `lib/core/constants.dart` | 詳情進入 380ms、返回 320ms、easeInOutCubic，保留原有按壓 90/210ms。 |
| `lib/core/config.dart` | 磁碟縮圖 200px、詳情解碼 120–150px、後續封面 600px、縮圖鍵版本 2。 |
| `lib/screens/bookshelf/bookshelf_screen.dart` | 漫畫／資料夾改用 DetailRoute；不在 push 前等待圖片，傳遞封面裁切設定。 |
| `lib/screens/details/category_detail_screen.dart` | 移除檔名列表、重複路徑副本與舊封面檔案探測。首排可先顯示受限解析度原圖；其餘未命中工作等待轉場完成。縮小預載範圍至 200 logical pixels、移除伸展模糊與重複 RepaintBoundary。被其他畫面覆蓋時停止排入生成工作。 |
| `lib/screens/details/folder_detail_screen.dart` | 資料夾 Hero 兩端使用相同四格封面；移除進場 800px 單張封面解碼。資料夾內漫畫使用專用詳情路由。 |
| `lib/widgets/cover_hero.dart` | 由已繪製圖片回報 ImageProvider，飛行時凍結使用書架端 provider、裁切與四格構圖；沒有全域 provider 登錄表或飛行時磁碟查詢。 |
| `lib/widgets/detail_cover.dart` | 保持書架尺寸封面預覽；轉場及首排完成後才要求 600px 圖片。高解析圖片就緒後不再繪製底層預覽；失敗時保留預覽。GIF/WebP 不啟動第二組高解析動畫解碼。 |
| `lib/widgets/book_card.dart`、`folder_card.dart` | 接入 CoverHero，維持 SpringPress、選取、長按、拖曳與原有尺寸。 |
| `lib/widgets/page_thumbnail.dart` | 分離快取命中、首排原圖預覽、受控生成；加入動態生成閘門與優先權。預覽顯示後不因生成完成而跳圖。 |
| `lib/widgets/app_image.dart` | 回報實際 ImageProvider；支援高解析疊圖透明錯誤佔位，避免蓋住既有預覽。FileImage／ResizeImage 的取樣方式維持一致。 |
| `lib/data/thumbnail_cache.dart` | 200px 原比例、不放大小圖；版本與尺寸納入鍵。保留 PNG、原子寫入、損壞檢查、來源 metadata 失效、去重與 LRU。新增命中／未命中及生成階段紀錄。 |
| 測試與工具 | 新增 `detail_transition_test.dart`，擴充詳情、Hero 與縮圖快取測試；`tool/detail_device_perf.dart` 提供隔離實機場景。 |

已檢查、未修改：ThumbnailScheduler、PagePathCache、PerfLog／PerfFrames。沿用生成並行數 1、可見性優先權、請求去重，以及資料庫變更時的路徑快取失效。沒有更改資料庫結構、原始圖片、實際檔名或閱讀器。

## 最終行為

| 項目 | 最終設定與限制 |
|---|---|
| 一般進入／返回 | 380／320ms，easeInOutCubic 淡入淡出，無整頁縮放；導航不等待縮圖。 |
| Hero | 與路由共用時間軸，保留 Flutter 原生 Hero 的平滑幾何曲線；不強制將其改成 linear。進出均選書架端已顯示 provider，避免高低解析圖片在飛行中切換。 |
| 預測性返回 | 手勢期間透明度直接跟隨系統進度；取消恢復、提交由框架 route lifecycle 完成。提交時映射現有透明度，避免 controller 重啟造成閃白。沒有額外 AnimationController。 |
| 減少動畫 | 新路由進出時間為零、Hero 停用；原按壓減少動畫邏輯保留。 |
| 首次圖片載入 | 首排最多四張可使用 120–150px 原圖預覽；其他格子可讀快取，未命中則待轉場完成後交給既有單工排程。原圖預覽不會解碼為完整漫畫尺寸。 |
| 封面升級 | 首排及轉場完成後，靜態封面才要求 600px；升級失敗不遮住低解析預覽。 |
| 縮圖 | 磁碟 300→200px PNG，保持比例及透明度。記憶體寬度依格子實際像素限制在 120–150px。 |
| 快取 | 鍵包含 v2、200px、來源路徑／大小／修改時間。保留原 LRU 目錄，使舊版與新版檔案共同遵守 256MiB 配額；舊鍵不能命中新規格。原圖不會被覆寫或作為快取清理目標。 |
| 圖片標題 | 「第 1 張、第 2 張……」，直接使用 index + 1。查詢、排序或刪除後依最新列表更新；書名、資料夾名與真實路徑保持原樣。 |
| 閱讀器 | 繼續使用 ReaderFileImage 原始解析度；未修改翻頁、縮放、解碼尺寸或原始檔。 |

保留 PNG 的原因：Flutter 原生輸出可維持透明度及既有驗證／原子寫入流程；改用 JPEG/WebP 需要另一條編碼路徑，沒有足夠量測證據支持新增編碼成本。本次沒有新增依賴，也沒有宣稱比較過 JPEG/WebP 編碼速度。

## 實機結果

Pixel 6、Android 17、Flutter 3.38.3／Dart 3.10.1、Impeller Vulkan、Profile、GUNBOOK_PERF=true。104 張不同的合成 2048×3072 PNG，獨立 applicationId `.detail20261107`，使用記憶體資料庫。正式 App 與使用者書庫未被替換或讀寫。

| 載入指標（ms） | 修改前 | 最終修改後 |
|---|---:|---:|
| 首次詳情建立→第一幀 | 22 | 16 |
| 首次詳情建立→第一張縮圖 | 132 | 121 |
| 首次詳情建立→首排四張 | 342 | 209 |
| 第二次進入首排（清除圖片記憶體快取、保留磁碟） | 177 | 143 |
| 一般重返首排中位數，run 3–9 | 81 | 77 |
| 最後一次記憶體快取清除後首排 | 120 | 131 |
| 首次 pointer down→第一幀 | 100 | 90 |

pointer down 指標包含測試刻意保留的 60ms 按住時間；這不是 Navigator.push 的等待時間。既有首幀／首排指標從詳情 State 初始化起算；新加入 detail_route_first_frame 從路由建立起算，原始 log 可分別檢查。

| 場景視窗 | Build 平均 ms 前→後 | Raster 平均 ms 前→後 | 超過 16.667ms frame／全部 frame 前→後 |
|---|---:|---:|---:|
| 11 次進入（含一次 70ms 快速返回） | 3.817→3.478 | 6.412→7.383 | 20/244→30/367 |
| 11 次返回 | 2.320→3.266 | 6.112→7.500 | 2/152→10/273 |
| 詳情快速上下捲動 | 2.997→3.257 | 6.824→8.003 | 4/224→5/221 |

這是單次順序對照，並未證明 Raster 改善；返回及捲動的觀察值反而較高。進入／返回時間加長，所需動畫 frame 數也不同，不能只比較超時 frame 絕對數或宣稱固定百分比改善。進入視窗約 550ms、返回約 650ms，包含資料／圖片初始化與動畫完成附近的工作，並非純 Hero GPU 成本。Build 與 Raster 分別計算，沒有相加作為幀時間。

裝置回報 90Hz，幀預算約 11.1ms；既有 PerfFrames 的 8.333／16.667ms 計數分別可作為 120／60Hz 的參考，不能當作本機精確掉幀計數。未取得 DevTools trace，不能將剩餘尖峰確定歸因於某個 widget。

| 其他觀察 | 修改前 | 修改後／說明 |
|---|---:|---|
| 最後一次返回 image_cache_bytes | 9,240,000 | 6,480,000 |
| 最後一次返回 RSS | 306,896,896 | 312,795,136；並未證明總記憶體降低或無洩漏。 |
| 生成完成時間中位數 | 72.77ms，70 次 | 67.18ms，64 次；工作集合因排程不同，不是嚴格的同圖生成微基準。 |
| 生成階段中位數 | 舊版沒有拆分紀錄 | 讀取／解碼 39.03ms、PNG 編碼 22.00ms、來源驗證與寫入 3.31ms，PNG 約 5926 bytes。 |
| hit-only lookup | 舊版沒有 miss 紀錄 | 78 hit／32 miss，約 70.9%。 |
| get／生成請求 | 舊版沒有 miss 紀錄 | 460 hit／375 miss，約 55.1%；miss 包含之後被取消或離開視野的排程，不代表 375 張實際生成。 |

命中率按操作統計，不能當作獨特頁面命中率，也不能由舊版缺少 miss 紀錄推算修改前命中率。各階段中位數不應直接相加當作某一張圖片的完整時間。

第一次修改後的 Profile 也保存在 `profile-after-initial.log`。量測後已移除封面雙層繪製，以及一般淡入淡出時不需要的轉場包裝；最終值使用 `profile-after.log`。最終冷啟動使用相同合成內容的新路徑，避免誤用初版生成的 v2 快取。這些修正沒有達成全面降低 Raster，仍需後續定位。

## 測試結果

| 檢查 | 結果 |
|---|---|
| 修改前相關測試 | 16 項通過。 |
| 最終完整測試 | 118 項通過，含 GUNBOOK_PERF=true。 |
| 新增／擴充覆蓋 | 380/320ms、減少動畫零時長、預測返回取消與提交透明度連續、10 次返回保留非零捲動位置、快取閘門／首排預覽、背景頁停止排程、標題與路徑順序、v1 拒用、200px／比例／透明度／小圖不放大／原圖不變、Hero 中斷返回。 |
| 格式 | 修改的 Dart 檔案格式檢查通過。 |
| flutter analyze | 0 error、0 warning、49 個既有 info；指令仍因 info 以非零狀態結束。 |
| 實機 Profile | 冷／磁碟命中／記憶體暖快取／人工清除記憶體快取、11 次進出、快速返回與快速捲動完成；無 detail_bench_error／failure。 |
| 資料安全 | 獨立測試 App、合成圖片、記憶體資料庫；未刪除漫畫原圖。測試完成後停止隔離 App。 |

完整數據在 `summary.json`、`profile-before.json`、`profile-after.json` 與原始 log；快照及 changes.patch 供檢查本次差異。

## 尚未解決

| 項目 | 狀態／下一步 |
|---|---|
| 返回與捲動 Raster／尖峰 | 尚未全面改善。應取得 DevTools frame trace，區分整頁淡出合成、Hero 裁切、圖片解碼與 GPU 工作，再決定下一步。不能宣稱已穩定達到 120Hz。 |
| 60／120Hz 實機 | 本輪 Profile 回報 90Hz，未完成固定 60Hz 或 120Hz 對照。 |
| 真實低記憶體／長時間 heap | 僅人工清除 Flutter 圖片快取，未製造 Android LMK／OS 記憶體壓力，也未完成長時間 heap 追蹤。 |
| 原生返回觸感 | 已自動測試 Flutter back-gesture 通道；未完成人工 Android 邊緣手勢觸感驗收。 |
| 真實漫畫資料 | 已測 104 張不同高解析合成圖片；不同 JPEG、透明 PNG、動畫封面與超大型書庫仍值得實機擴充量測。 |

隔離測試專案已移至系統暫存目錄，避免主專案分析掃到測試副本；正式 Android 建置設定未更動。
