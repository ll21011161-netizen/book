# 槍簿 UI、動畫與操作體驗優化報告

日期：2026-11-07。以本輪開始時工作區最新版本為基準，保留先前穩定性修復與其他未提交修改。

## A. UI 與動畫問題

| 優先級 | 位置 | 確認結果與影響 |
| --- | --- | --- |
| P0 | `manga_reader_screen.dart` 翻頁 | 每個可見頁面以 PageController 通知驅動額外 AnimatedBuilder、縮放及整頁透明度。圖片子樹原本已放在 child，並非每幀重建圖片。已移除裝飾效果，保留 PageView 自然滑動。實機沒有證明 raster 加速，詳見量測。 |
| P0 | 閱讀控制列／`glass_box.dart` | 同時執行 AnimatedPositioned、AnimatedOpacity、即時模糊；位置動畫逐幀影響 Stack layout，半透明不會自動阻止觸控。固定 -100/-140 位移也無法涵蓋所有文字／安全區高度。已改為依實際尺寸滑出、立即停止隱藏區域觸控，取消即時模糊。配對實機量測確認 raster 成本下降。 |
| P1 | `main.dart` 導覽列 | 每次超過 2 logical pixels 的方向變動便切換，慣性／細微反向可能造成反覆收合；滑出後 Scaffold 仍保留導覽列高度。已加入方向累積門檻、忽略非手指慣性變動，改為穩定覆蓋視窗並處理巢狀 SafeArea。 |
| P1 | `main.dart` 頁面導航 | 使用 400ms；目前選取索引本來就代表目標，不應在反向動畫途中再用暫時頁碼覆寫。改為 260ms，保留重複目標去重，支援動畫中改變方向與減少動畫時直接跳轉。 |
| P1 | `PhysicsDragFeedback` | 每筆拖曳 delta 都重新設定 150ms Tween 目標，並疊加 3D 變換與整張透明度。原本 child 已保留，不稱為重複解碼問題。改為跟隨目前輸入的小角度 2D 傾斜，取消額外 opacity 與 Tween。未量測大量書籍實機拖曳 FPS。 |
| P1 | `settings_screen.dart` | 倍率滑桿每次 onChanged 都對整個設定頁 setState。已先用回歸測試在原始碼重現，再將草稿狀態限制於倍率區塊；仍只在放開時寫入。 |
| P1 | 閱讀器離開／深色模式 | dispose 一律 `AppTheme.setSystemStyle(false)`，使深色模式返回時系統導覽圖示對比錯誤。已建立失敗測試，改為快取目前 Theme brightness 後正確還原。 |
| P2 | `anim_route.dart`、`reader_zoom.dart` | 每次建立曲線包裝使用 CurvedAnimation，沒有對那些包裝物件做獨立 dispose。改用不額外訂閱父動畫狀態的 CurveTween；未主張有已量測的記憶體洩漏改善。 |
| P2 | 動態效果偏好 | 自訂卡片、路由、導航、控制列、縮放、拖曳與 Shimmer 原本未完整處理減少動態效果。已在本輪修改範圍加入支援。 |

沒有因看到 Opacity、Clip、Shadow 或 RepaintBoundary 就全面刪除。整頁 alpha 是否需要中間圖層取決於 Flutter／renderer 最佳化，不能一律視為 saveLayer；Pixel 6 翻頁量測也沒有顯示明顯 raster 瓶頸。

## B. 實際修改

| 檔案 | 修改 |
| --- | --- |
| `lib/screens/reader/manga_reader_screen.dart` | 移除滑動期間的逐頁縮放／透明度，以及圖片首幀後的額外淡入等待。維持 ReaderFileImage 原圖解碼、相同 cache key、既有串行解碼及 LatestTask 預載。控制列固定定位，按鈕／滑桿以 ValueListenableBuilder.child 保留；加入測試 DB 注入接縫、正確還原深色系統圖示。 |
| `lib/widgets/reader_controls_transition.dart` | 新增小型共用控制列位移元件：AnimatedSlide、IgnorePointer、ExcludeSemantics、隱藏子樹 TickerMode。依子樹高度滑出，不使用固定像素門檻。 |
| `lib/widgets/glass_box.dart` | blur=0 時使用直接半透明 DecoratedBox，不建立 BackdropFilter／ClipRect；預設 blur 功能保留。閱讀器指定黑色 0.8 alpha，配色與原先一致。 |
| `lib/main.dart` | 導航 260ms；快速反向以新目標中斷；同目標不重複啟動。導覽列隱藏時不接收觸控／語意焦點；往下累積 24px 收合，往上 12px 顯示，到頂也會顯示。extendBody 維持視窗尺寸，再去除其人工增加的 bottom padding，保留真實系統安全區。保留原有兩頁、NavigationBar 與各頁末端留白。 |
| `lib/core/constants.dart` | 分開 press 100ms、release 150ms、controls 200ms、zoom 200ms、navigation 260ms；原有 route 250/150ms 與其他常數保留。新增依系統偏好回傳零時長的 helper。 |
| `lib/core/anim_route.dart` | 以 CurveTween 建立曲線，減少動畫時不套用自訂轉場。沒有新增 Hero shuttle 或昂貴快照。 |
| `lib/screens/reader/reader_zoom.dart` | 保留 InteractiveViewer、Matrix4Tween、點擊中心、1–4 倍範圍與可設定雙擊倍率。曲線改 easeOutCubic，系統減少動畫時直接套用目標矩陣。 |
| `lib/screens/bookshelf/bookshelf_screen.dart` | 拖曳回饋改為小角度 2D 跟隨，不再用每筆輸入重設 Tween、3D 或 opacity；feedback 關閉 Hero 參與。排序、合併計時、資料夾建立及資料操作不變。選取標題／懸停動畫尊重減少動態效果。 |
| `lib/widgets/book_card.dart`、`folder_card.dart`、`scale_button.dart` | 按下 100ms、放開 150ms，維持原有縮放幅度；減少動畫時立即回饋。書架卡片在減少動畫時停用 Hero flight。既有 RepaintBoundary 保留，沒有盲目增加。 |
| `lib/screens/settings_screen.dart` | 新增私有倍率設定子元件，限制草稿重建範圍；原有設定區塊、文字、滑桿範圍與儲存時機維持。 |
| `lib/screens/details/category_detail_screen.dart`、`bookshelf/search_delegate.dart` | 系統要求減少動畫時停用 Shimmer ticker，保持佔位尺寸。 |
| `lib/core/perf_log.dart` | 在既有 PerfFrames 聚合結果增補 total_build_us／total_raster_us，供平均值計算；沒有建立第二套監測系統，關閉 GUNBOOK_PERF 時不啟用回呼。 |
| `test/navigation_motion_test.dart` | 細微滑動／慣性、不留導覽列空白、快速導航反向、減少動畫、視窗尺寸變更。 |
| `test/reader_motion_test.dart` | RTL／LTR 手勢翻頁、快速控制列反向、隱藏觸控、保留圖片 provider／頁面狀態／滑桿子樹、進度儲存及深淺色系統圖示恢復。 |
| `test/settings_motion_test.dart` | 驗證草稿更新不重建外層 ListView，且放開才持久化。 |
| `test/hero_motion_test.dart` | 書籍封面路由在轉場未完成時返回，並涵蓋減少動畫。這是空封面結構測試，不能冒充真實封面畫質／閃爍驗收。 |
| `test/reader_zoom_test.dart` | 增補減少動畫時立即使用設定倍率、縮回原尺寸；既有雙擊、雙指、邊界與中斷測試保留。 |

本輪共修改／新增 20 個程式與測試檔，精確清單與差異見 `performance_results/2026-11-07-ui/changed-files.json`、`changes.patch`。開始時的 lib／test 完整快照保留於該目錄的 `before`，使用 `.dart.txt` 避免分析器重複掃描。

檢查但保留：`theme.dart` 配色與 Material 3、`folder_detail_screen.dart` 既有互動、`page_thumbnail.dart` 的顯示原圖後補快取且不中途換圖策略。`smooth_zoom.dart` 沒有實際引用，目前閱讀器使用 ReaderZoom，未刪除預留實作。`flutter_staggered_animations` 與 `fluid_bottom_nav_bar` 沒有 production import；沒有為此次動畫工作變更依賴或 lockfile。

## C. 動畫效能：真實量測

裝置為 **Pixel 6，90Hz**，前景且解鎖；Flutter **3.38.3 / Dart 3.10.1**，Profile Mode，啟用現有 `GUNBOOK_PERF=true`。使用獨立套件 **`com.example.flutter_application_1manga.ui20261107`**，沒有覆寫正式應用或真實書庫。

同一個 Profile APK 同時包含修改前與修改後的實際閱讀器程式碼，交替順序執行；先各一輪暖身不列入，之後各四輪。四張相同 2048×3072 合成 PNG 預先以 ReaderFileImage 解碼，共 96 MiB decoded-image cache。每輪執行 12 次相同的 260ms 程式化滑頁，再切換控制列 12 次、間隔 320ms。兩邊控制列採各自產品設定的 250／200ms 時長。

以下平均值以 PerfFrames 的總耗時除以總樣本數，尖峰為四輪最大值。

| 情境 | 指標 | 修改前 | 修改後 |
| --- | --- | ---: | ---: |
| 暖快取翻頁 | build 平均 | 1.334ms | 1.241ms |
| 暖快取翻頁 | raster 平均 | 3.091ms | 3.110ms |
| 暖快取翻頁 | build／raster 最大 | 8.103／9.334ms | 9.312／9.183ms |
| 暖快取翻頁 | 超過 8.333ms 的樣本 | 1 / 1196 | 2 / 1195 |
| 控制列切換 | build 平均 | 1.634ms | 2.143ms |
| 控制列切換 | raster 平均 | 5.659ms | 3.616ms |
| 控制列切換 | build／raster 最大 | 7.998／12.689ms | 5.205／9.823ms |
| 控制列切換 | 超過 8.333ms 的樣本 | 84 / 1152 | 1 / 960 |
| 兩種情境 | 超過 16.667ms 的樣本 | 0 | 0 |

**判讀：控制列 raster 成本確實下降；翻頁 raster 幾乎沒有改善，不宣稱 FPS 加速。** 控制列 build 平均上升，不能稱為 CPU／GPU 全面變快；其 build 尖峰則下降。兩邊動畫長度不同，樣本數也不同，已保留分母，不能只拿次數宣稱掉幀率改善百分比。

PerfFrames 的門檻是 build 或 raster 任一超過即計數。這不是 SurfaceFlinger 實際漏呈現影格數。90Hz 的預算約 11.1ms；8.3ms 數字只顯示餘裕，**未驗證 120fps，也未單獨切至 60Hz 重測**。沒有量測 GPU utilization、真正輸入至顯示延遲或峰值記憶體，亦未開啟 DevTools Performance trace 做事件逐幀歸因。

這個實驗刻意排除冷解碼成本，不代表 JPEG／4K／GIF、快取被清除、數百頁連續閱讀或低階裝置。合成圖案與真實漫畫不同。記憶體僅保留各階段結束時 RSS 原始樣本，不當成峰值或洩漏證明。

原始資料與重現材料：

- `performance_results/2026-11-07-ui/device-profile-final.log`
- `performance_results/2026-11-07-ui/summary-final.json`
- `performance_results/2026-11-07-ui/ui_device_perf.dart.txt`
- `manga_reader_measured_before.dart.txt`、`manga_reader_measured_after.dart.txt`
- `isolated-profile-build.log`

初次探索量測保留於 `device-profile.log`／`summary.json`，最終結論以 final 資料為準。最後另加入的深色圖示恢復不影響上述亮色主題的量測路徑；精確被量測來源已另存，沒有將未量測部分併入效能主張。隔離測試套件已停止；其 APK／原始碼保留在 Windows 暫存目錄供重現。

## D. 使用體驗改善與視覺差異

- 翻頁改為完整明亮頁面的連續滑動，不再同時縮小、變暗；新圖片有首幀就顯示，沒有額外 250ms 淡入。原圖解析度及 RTL 保留。
- 控制列維持黑色半透明表面與邊框，但**不再即時模糊背景，也不再淡入淡出**，改為 200ms 位移。快速切換可由當前位置反向，隱藏立即停止攔截觸控與語意焦點。
- 首頁／設定切換採 260ms；導覽列不因 2–3px 抖動反覆動作，輕微反向後累積 12px 即可重新叫出；視窗不因導覽列收合改變高度。
- 卡片按下反應更短；拖曳仍有小角度傾斜與原有放大，但取消 3D 搖擺、透明度與追趕輸入的延遲 Tween。
- 設定倍率文字與滑桿局部更新；深色模式返回時系統圖示對比恢復正確。
- 未更動封面比例、顏色、欄數、縮圖尺寸、導航結構、原有資料操作或圖片品質。

上述時長屬配置變更；除了表列 build／raster 數據，不把它們當成已量測的觸控延遲。

## E. 測試結果

| 檢查 | 結果 |
| --- | --- |
| 修改前完整測試 | 88 項通過 |
| 最終 `flutter test --no-pub` | **100 項通過** |
| 最終 `flutter test --no-pub --dart-define=GUNBOOK_PERF=true` | **100 項通過** |
| `flutter analyze --no-pub` | **0 error、2 既存 warning、50 既存 info，結束碼 1**；不是全綠。修改前為 54 項，最終 52 項，沒有新增診斷。 |
| 正式入口 Android Profile APK | **成功**；`build/app/outputs/flutter-apk/app-profile.apk`，未安裝覆寫正式應用。 |
| 隔離 Profile 配對量測 | **完成**，暖身後四輪／版本，原始 log 有 complete 且無 benchmark error。 |
| 設定整頁重建／深色系統圖示 | 原始實作的針對性測試均先失敗，修復後通過；見 `settings-before.log`、`system-style-before.log`。 |

既存 warning 仍位於 `smooth_input_dialog.dart`：未用 import、永遠不會執行的 null fallback。本輪沒有為清除診斷而修改無關功能。

Widget 測試涵蓋快速反向導航、控制列中斷、離開中動畫、RTL／LTR、雙擊與雙指縮放、選取／拖曳相關既有回歸、深色圖示、導航視窗尺寸變更；並繼續通過既有書庫、資料庫、匯入取消與圖片錯誤測試。沒有修改資料庫或匯入流程。

尚未執行：真實 Android 手指雙指縮放／快速連翻壓測、實機旋轉時的縮放邊界驗收、低記憶體強制回收、真實封面 Hero 視覺逐幀比對、大量書籍拖曳的實機配對 profile、120Hz 裝置測試。Widget 測試不能取代這些驗收。

## F. 下一輪最值得改善的三項

1. **冷載入與高解析度閱讀的實機互動量測**：使用隔離的真實 JPEG／4K 漫畫，驗證解碼尖峰、預載與快速滑頁競爭、低記憶體回收及旋轉後縮放邊界；量測真正輸入延遲與峰值記憶體。
2. **真實封面的 Hero 一致性**：比對書架原圖／磁碟縮圖、詳情頁裁切及資料夾拼圖到單封面的視覺銜接。現有 tag 配對與快速返回結構未出錯，但不在沒有畫面證據時加入複雜 shuttle。詳情縮圖目前也沒有與閱讀器路徑 Hero 配對，未擅自增加新轉場。
3. **大量書庫拖曳與多更新率驗證**：測試合併、排序、選取、深色切換及導航在低階 60Hz、目前 90Hz 與真正 120Hz 裝置的 frame trace，確認簡化拖曳回饋的實際收益與手感。

本輪已完成可驗證的主要閱讀控制列改善、互動穩定性與局部重建修正。沒有將簡化動畫本身、縮短時長或測試通過，誇大成全 App FPS 提升。
