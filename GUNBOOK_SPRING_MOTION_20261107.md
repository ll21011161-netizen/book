# 槍簿輕量 Q 彈動畫實作與驗證（2026-11-07）

## 1. 修改摘要

以本次開始時的工作區原始碼作為基準，保留既有未提交修改；沒有修改資料庫結構、圖片壓縮、閱讀器或使用者書庫資料。修改前原始碼存於 `performance_results/2026-11-07-spring/before/`，本次差異存於同目錄的 `changes.patch`。

| 檔案 | 實際修改 |
|---|---|
| `lib/core/constants.dart` | 新增專用按壓、釋放、彈窗、拖曳參數，保留原有一般轉場曲線。 |
| `lib/widgets/spring_press.dart` | 新增輕量按壓元件；pointer listener 立即回饋，不新增手勢辨識器；狀態只重建動畫外層，保留 child。處理放開、取消、長按、TickerMode 與同步導航的 Hero 尺寸復位。 |
| `lib/widgets/book_card.dart` | 改為無狀態卡片並使用 SpringPress；維持封面、進度、選取與 Hero。原有單一 RepaintBoundary 移至縮放內部，讓圖片／文字內容可獨立重用。 |
| `lib/widgets/folder_card.dart` | 使用相同按壓行為，維持四張縮圖及原有 Grid 尺寸。 |
| `lib/widgets/scale_button.dart` | 重用 SpringPress，移除重複按壓狀態。 |
| `lib/widgets/smooth_input_dialog.dart` | 0.95 倍縮放與淡入，取消額外位移；開／關使用不同時間與縮放曲線。使用可重用 Tween／CurveTween；移除延遲計時器，改在路由完成後取得焦點，並移除 status listener。 |
| `lib/screens/bookshelf/bookshelf_screen.dart` | 依實際經過時間估算水平速度，做時間相關濾波與角度量化，只通知拖曳回饋。加入浮起動畫；預覽依 Grid 實際約束。只有懸停目標訂閱合併變更；移除大範圍模糊陰影，改用縮放與靜態邊框。保留 500ms 合併判定及原本資料寫入流程。 |
| `lib/screens/details/folder_detail_screen.dart` | 拖曳預覽符合 Grid 尺寸並關閉預覽 Hero；補齊原地長按放開的多選與 pointer cancel 判斷。 |
| `test/spring_motion_test.dart`、`test/spring_drag_test.dart` | 新增 11 項動畫、手勢、生命週期與減少動畫回歸測試。 |
| `tool/spring_device_perf.dart` | 隔離 Android Profile 測試程式，使用合成圖片及記憶體資料庫。只應以獨立 applicationId 執行。 |

已檢查但未修改：`anim_route.dart`、`perf_log.dart`、`category_detail_screen.dart`、`page_thumbnail.dart`；與開始時快照逐位元組相同。PageThumbnail 的 retain/release、磁碟快取、延後產生縮圖及 GIF/WebP 保留策略均未更動。

原本 300ms 的 LongPressDraggable 會先於卡片的預設長按辨識器贏得手勢。本次保留拖曳時機，並讓原地長按後放開進入多選；移動累計達 12 logical pixels 後視為拖曳，取消事件不會誤進入多選。一般卡片與非拖曳模式仍使用原本長按回呼。

## 2. 動畫參數

| 互動 | 時間 | 比例／角度 | 曲線與回彈 |
|---|---|---|---|
| 書本／資料夾／ScaleButton 按下 | 90ms | 1 → 0.95 | easeOutCubic，pointer down 立即啟動。 |
| 放開／取消 | 210ms | 回到 1 | Cubic(0.2, 0.85, 0.35, 1.15)，完整 0.95→1 回復時峰值約 1.002。 |
| 彈窗開啟 | 250ms | 0.95 → 1 | 相同輕微過衝曲線；透明度獨立使用 easeInOut。 |
| 彈窗關閉 | 150ms | 1 → 0.95 | easeOutCubic，透明度 easeInOut，無反向彈跳。 |
| 拖曳浮起 | 170ms | 1 → 1.045 | easeOutCubic，位置仍由 Flutter Draggable 直接跟隨手指。 |
| 拖曳旋轉 | 100ms 視覺追蹤 | 最多 ±0.05 rad | 速度先以 55ms 時間常數濾波，再以 easeOutCubic 平滑旋轉；不平滑實際位置。 |
| 目標懸停／合併 | 190ms | 0.97／1.025 | 輕微過衝曲線與靜態邊框；合併觸發仍為 500ms。 |
| 目標復位 | 210ms | 回到 1 | 輕微過衝曲線；feedback overlay 由 Draggable 原生移除。 |

減少動畫時按壓、浮起與旋轉保持 1／0，時間為零；彈窗無進出轉場。目標保留瞬時靜態選中提示。同步導航會先復位來源縮放，避免 Hero 使用按壓中的尺寸。沒有新增第三方套件或每張卡片的手動 AnimationController。

## 3. 效能結果與限制

程式碼層級改善：按壓狀態不再重建整張卡片；child 保留使封面與文字不隨動畫 tick 重建。縮放內部沿用單一 RepaintBoundary，沒有新增卡片邊界層。拖曳通知只影響 feedback，角度量化排除細微雜訊；閒置目標不訂閱合併狀態。移除合併目標 blurRadius 20／spreadRadius 4 的動態陰影。預覽與原圖使用相同縮圖參數，維持 Flutter 圖片快取共用。

Pixel 6／Android 17、Flutter 3.38.3、Dart 3.10.1、Impeller Vulkan、Profile、GUNBOOK_PERF=true。以下是相同合成資料、相同手勢的單次場景視窗比較，數字為每個已繪製 frame 的平均毫秒：

| 場景 | Build 前 → 後 | Raster 前 → 後 | 超過 16.667ms 的 frame 前 → 後 |
|---|---:|---:|---:|
| 書本按壓 20 次 | 1.37 → 1.12 | 3.45 → 3.74 | 0/371 → 0/335 |
| 資料夾按壓 20 次 | 1.57 → 1.12 | 3.80 → 4.02 | 0/372 → 0/338 |
| 彈窗 10 次 | 1.67 → 1.61 | 2.67 → 2.73 | 1/771 → 1/726 |
| 拖曳排序 10 次 | 2.34 → 2.21 | 7.20 → 6.76 | 15/447 → 10/431 |
| 拖曳合併至資料夾 | 2.45 → 2.04 | 7.80 → 7.17 | 3/71 → 1/72 |
| 120 筆合成書架上下捲動 | 6.26 → 5.64 | 5.54 → 5.09 | 12/189 → 6/210 |

超時 frame 是 Build 或 Raster 任一超過門檻；兩者不是相加。這些視窗透過既有 PerfFrames 分別開啟／結束，未使用整個書架生命週期累積數字替代。彈窗視窗包含鍵盤，拖曳視窗包含排序、縮圖建立與目標回饋，不能將差異全歸因於單一動畫。

本次按壓的平均 Raster 略高，不能宣稱全面改善或固定百分比加速。動畫時間與 frame 數本來就不同；單次順序執行也受系統排程、暖機與溫度影響。90Hz 的預算約 11.1ms，60Hz 約 16.7ms，120Hz 約 8.3ms；既有紀錄提供 8.333／16.667ms 計數，8.333ms 超標不能直接稱為本機 90Hz 掉幀。

按壓視窗內圖片快取用量穩定；捲動完成時前／後 image_cache_bytes 均為 308400。正常模式捲動結尾 RSS 約 274.8／271.5 MiB，減少動畫模式約 268.6／269.7 MiB。這些是觀察值，並非 heap leak 證明。測試重用同一合成圖片，不能代表大量獨特高解析度封面的記憶體壓力。

完整指標：`performance_results/2026-11-07-spring/comparison.csv`、`profile-before.json`、`profile-after.json` 與原始 log。修改前正常按壓的兩筆指標在 Android log buffer 輪替前已由工具輸出擷取，另存 `profile-before-initial.json`；其餘基準原始紀錄在 `profile-before.log`。

## 4. 驗證結果

- 修改前：15 項既有相關測試通過。
- 修改後：`flutter test --no-pub --dart-define=GUNBOOK_PERF=true`，全 111 項通過，紀錄於 `tests.log`。
- 新增測試涵蓋：書本／資料夾各 20 次按壓、取消、長按、縮圖 Element 保留、彈窗 10 次確認／取消／外部點擊／返回／進場中關閉、焦點時機、拖曳排序 10 次、資料夾合併、取消不誤選、原地多選、資料夾預覽尺寸與 Hero、拖曳中移除畫面、旋轉上限、child 不重建，以及減少動畫。
- 既有 Hero 中斷返回、資料庫排序與合併競態、閱讀器、搜尋、設定、圖片與快取回歸測試一併通過。
- 修改的 11 個 Dart 檔案通過 dart format 檢查。
- `flutter analyze --no-pub`：0 error、0 warning、51 個 info，因此指令仍以非零狀態結束。剩餘為既有樣式／deprecated API 提示，以及本次拖曳通知處的一個括號樣式提示；沒有為了清除提示而擴大重構。
- Android Profile 前／後：正常及 MediaQuery 減少動畫各完成全套場景，排序計數各 10 次、合併各 1 次，無 spring_error／spring_failure。
- Android 真實系統減少動畫：另以 transition_animation_scale=0 驗證 Flutter 收到 system_reduced=true，裝置回報 60Hz。系統設定測試後恢復原值；結果見 `profile-system-verified.log`、`system-setting.txt`。

隔離 App 使用 `com.example.flutter_application_1manga.spring20261107`，沒有替換正式 App。測試副本已移至系統暫存目錄，避免完整靜態分析重複掃描舊版程式碼。正式專案 Android 設定沒有更動。

## 5. 剩餘問題

120Hz 實機、一般動畫下固定 60Hz 的完整比較、人工觸感驗收、獨特大量封面壓力與長時間 heap／DevTools trace 尚未完成。本機一般 Profile 使用 90Hz，實際系統減少動畫測試回報 60Hz。

拖曳及捲動仍有超時 frame，不能保證零掉幀。應先用 DevTools 分析不同封面資料下的 Raster、縮圖初始化及 Grid 工作，再決定是否需要更多優化；目前不宜為此改動圖片壓縮、資料庫或閱讀器。沒有證據需要新增物理彈簧控制器或額外動畫套件。
