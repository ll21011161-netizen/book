動畫系統修改與驗證紀錄（2026-11-07）

1. 原有問題與確認範圍

- MainScreen 的 PageView 以 animateToPage 搬動整個 viewport，快速反向選取會反覆重定向捲動活動，也限制了可選轉場。這是可以移除的位移成本；未以實機 Profile 量化原本卡頓比例。
- 路由、按壓、導覽列、控制列與對話框原先各有固定曲線、速度；詳情頁使用 380/320ms，按壓預設有明顯回彈，沒有全域設定。
- SettingsScreen、閱讀器監聽整個 SettingsProvider，與畫面無關的設定也可能觸發整頁 build。
- 原有詳情縮圖已具備快取命中、延後生成及 generation token 保護；按壓 Timer、圖片 Listener、閱讀進度與讀圖任務也已有清理。此次保留並以測試檢查，沒有把這些既有保護當成新修復。

2. 新增與修改檔案

新增：
- lib/core/motion.dart：不可變設定、持久化解析、全域 MotionScope、受限 Spring、共用轉場。
- lib/widgets/retained_motion_tabs.dart：保留頁面狀態的雙頁容器與單一動畫控制器。
- lib/widgets/motion_settings_panel.dart：繁中設定、速度 Slider、重設及輕量預覽。
- test/motion_settings_test.dart：40 項新測試。

修改：
- lib/core/settings_provider.dart：motion_v1 獨立設定鍵、異常值預設、載入競態防護、依序保存、重設。
- lib/core/constants.dart：整理動作時間比例與閱讀器安全例外。
- lib/core/anim_route.dart：共用可選轉場，保留 Material 路由／Android 返回生命週期，避免 Hero 疊加。
- lib/main.dart：App 層套用設定與系統減少動畫、捲動預設，移除 PageView 導覽。
- lib/screens/settings_screen.dart：整合動畫區塊，縮小 Provider 監聽範圍。
- lib/widgets/spring_press.dart：共用 None／Scale／Spring，較短時間比例、輕微縮放與受限回彈。
- lib/widgets/reader_controls_transition.dart：接入共用曲線及速度。
- lib/widgets/smooth_input_dialog.dart：接入共用轉場，保留焦點 Listener 清理。
- lib/widgets/drag_cover.dart：接入設定，關閉動畫時保留拖曳目標提示。
- lib/screens/bookshelf/bookshelf_screen.dart：捲動物理、拖曳曲線／速度、繼續閱讀路由。
- lib/screens/bookshelf/search_delegate.dart：搜尋結果進入頁面使用統一路由。
- lib/screens/details/category_detail_screen.dart：詳情捲動與閱讀器路由。
- lib/screens/details/folder_detail_screen.dart：資料夾捲動物理。
- lib/screens/reader/manga_reader_screen.dart：捲動物理、按鈕翻頁速度／曲線、縮小 Provider 監聽。
- lib/screens/reader/reader_zoom.dart：動畫停用時中止雙擊的程式化變換；保留圖片邊界修正。
- test/detail_transition_test.dart、test/navigation_motion_test.dart、test/press_rebound_test.dart、test/settings_motion_test.dart：依新預設／導航架構更新驗證，保留原有操作測試。

3. 實際套用範圍

- 四種曲線：頁面轉場、主頁切換、控制列、共用按壓、拖曳視覺與輸入對話框。
- 六種頁面效果：首頁／設定切換、書架與搜尋結果進入漫畫／資料夾詳情、閱讀器進出。None 使用零路由時間。
- 三種點擊效果：所有 SpringPress／ScaleButton，涵蓋漫畫卡、資料夾及既有主要操作按鈕；原生按鈕保留 Material 操作提示。
- 捲動：書架、設定、詳情、搜尋列表與閱讀器 PageView。閱讀器放大時仍使用 NeverScrollableScrollPhysics；方向、圖片拖曳、雙擊與雙指縮放的邏輯不變。
- 速度：150／250／400ms 與 100–600ms Slider；按壓約使用 32% 進入、48% 或 80% 恢復。使用者手勢／滑動慣性維持 Flutter 原生物理。
- 圖片矩陣縮放保留專用 200ms、有界 easeOut 曲線，以免 Spring 越界與圖片邊界修正互相干擾；總開關仍有效。
- 動畫總開關透過 App 的 MediaQuery 與 MotionScope 套用，系統 disableAnimations 優先。關閉後操作回呼、選取狀態、拖曳提示和導航仍可使用。
- 預覽使用 MotionTransition 與 SpringPress，不讀真實圖片；可重播／反覆播放，設定變更、隱藏與 dispose 時停止舊動畫。
- 預設值：Ease In Out、Fade + Slide、Scale、無回彈、250ms、啟用。

4. 效能處理

- 兩頁保留相同 Element、捲動控制器與縮圖 State；只有目前頁面繪製與啟用 TickerMode。快速切換使用同一控制器，沒有 outgoing 動畫佇列。
- 動畫更新由 Flutter Fade／Slide／Scale 元件處理，子畫面不隨每個 tick 重新 build。
- Selector／context.select 縮小設定與閱讀器的 Provider 監聽範圍；MaterialApp 不因一般動畫設定重新建立。
- 保留卡片現有 RepaintBoundary、圖片解碼尺寸、快取及延後縮圖生成保護；沒有新增全頁圖層、額外預載、擴大快取或第三方套件。
- 自訂路由不再同時執行 Hero 與整頁轉場；縮圖與圖片仍保留原有資料與顯示。

5. 穩定性與保存

- motion_v1 使用 JSON 與 enum 名稱，舊版沒有此鍵時使用預設，損壞 JSON／型別／未知值均可回復。
- 設定立即通知、依序保存；啟動載入不覆蓋已編輯設定，快速修改／重設不讓較舊寫入最後落盤。讀取復原測試驗證 SharedPreferences 持久層；未以實機強制終止程序測試。
- 保留 Android 預測式返回取消與提交處理，手勢中使用線性進度，提交映射目前進度以免閃回起點。
- Timer、動畫控制器、WidgetsBindingObserver、路由焦點及圖片 Listener 的 dispose 清理均經原有／新增測試涵蓋。
- 未修改資料庫結構、漫畫排序、匯入、資料夾、閱讀進度資料格式。

6. 驗證結果

- flutter test --reporter expanded：175 項全部通過。包含 40 項新測試。
- 新測試涵蓋 24 種轉場／曲線組合的途中返回、5 種有動畫轉場的 Spring 預測式返回取消與提交、設定保存／異常回退／啟動競態、雙頁捲動保留、預覽重播與銷毀、三種點擊效果及系統減少動畫。
- 原有測試涵蓋閱讀器翻頁與縮放、原圖解碼、拖曳排序／合併、多次返回、圖片載入、資料安全與 Listener／Timer 清理。
- flutter analyze --no-pub --no-fatal-infos：exit 0；零 error、零 warning，44 項既有 info（風格／棄用 API）。預設 flutter analyze 仍會因這些 info 回傳非零，未隱藏此限制。
- 修改的 Dart 檔已執行 dart format。
- 完整測試及分析輸出：animation_test_results.log、animation_analysis_results.log。

7. 需實機確認

- 未執行 Android 實機 Profile、GPU／UI frame timing、記憶體峰值與大量封面捲動壓力測試，因此不宣稱達到固定 FPS。
- 待實機確認 OEM／Android 版本的預測式返回、程序重啟還原、長時間閱讀及大量高解析圖片的記憶體表現。
- 主頁保留兩個頁面的 Widget 狀態，會保留設定頁的少量常駐記憶體；沒有額外保存頁面 bitmap。
