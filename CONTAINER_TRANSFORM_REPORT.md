封面容器展開／縮回轉場完成紀錄（2026-11-07）

1. 採用方案

採用方案 A：沿用 MaterialPageRoute／DetailRoute 的 Navigator 與 Android 返回生命週期，實作自訂 Container Transform。以來源封面的真實矩形到 Navigator viewport 做插值，搭配圓角、封面快照與詳情內容交接。沒有新增 animations 套件，也沒有在詳情頁加上大封面或假的 Hero 終點。

CoverHero 保留既有 tag／provider 回報與 legacy flightShuttleBuilder；新效果使用它自己的封面繪製邊界取得來源，DetailRoute 繼續以 HeroMode 關閉額外飛行，避免同一封面被兩套系統移動。

2. 設定與使用

設定 → 動畫與動態效果 → 詳情頁切換動畫 →「封面彈出／縮回（Container Transform）」。只有主動選取後啟用，預設仍沿用頁面切換。原有六種頁面效果照常運作；閱讀器與沒有封面來源的入口仍沿用原設定。

同區提供一個不載入漫畫圖片的示意封面，點擊會開啟真正的預覽路由，返回時縮回示意封面。

新 detail enum 經現有 motion_v1 JSON／SettingsProvider 儲存。舊設定與未知 detail 值回到 followPage，不改動其他設定。

3. 動畫參數與幾何

- 標準速度：進入 380ms、退出 300ms，依原有速度設定調整並限制在 100–600ms。
- 進入前段 easeOutCubic，最後 30% 使用強阻尼 GentleSpring，僅對最後一小段幾何距離施加彈性；測試逐幀確認展開尺寸不超過完整頁面的 102%。
- 內容在進度 45%～90% 淡入，封面快照於早／中段淡出；退出內容先淡出，容器以 easeInOutCubic 縮回，沒有退出超越終點。
- 來源只包含封面，不包含標題、頁數與進度標示。座標由 RenderBox transform 換算到實際 Navigator，不固定從畫面中央開始。
- 詳情內容持續以完整 viewport 大小 layout，FittedBox 只變換繪製結果；動畫 tick 不重建詳情子樹、不反覆重新排整個網格。
- 中途返回及預測式返回取消會從當下顯示的矩形重新接續，避免因切換曲線而跳動；互動式手勢使用線性進度。

4. 返回來源與失效容錯

每個實際卡片持有自己的 CoverHeroState key，不使用全域 tag→位置 registry，也不把拖曳 feedback 的 Hero 當來源。

返回時重新查詢同一來源的 mounted 狀態、tag、封面 identity、RenderBox 與 viewport／scrollport 可見範圍，因此可以跟隨仍存在的卡片位置。來源被回收、刪除、換成別本漫畫、封面 identity 改變或完全離開可見範圍時，退回淡出＋輕微縮放。

若來源在收回途中才消失，會從當下矩形重接 fallback，不瞬間跳到中心。部分可見的封面仍使用真實矩形，由 viewport 裁切。捲動控制器、排序資料與資料夾資料沒有因轉場被修改。

5. 圖片、記憶體與按壓處理

- 進入時以 RenderRepaintBoundary.toImageSync 取得已繪製封面的「小尺寸快照」，最長邊不超過 512px，不讀檔、不等待完整原圖解碼，不呼叫 toByteData 或 PNG 編碼。
- 快照在整次路由期間固定，涵蓋 Cover／Contain 的已繪製結果與資料夾四格組合，不會因縮圖晚到、GIF 換幀或快取置換而突然換圖。展開時保持快照比例，以裁切代替拉扁圖片。
- 每個開啟路由只持有一張有界快照，返回／dispose 後釋放 ui.Image；捕捉失敗時使用安全的色塊容器，不阻塞導航。
- 漫畫詳情頁沿用原有縮圖快取及 generation token；Container Transform 期間延後首列的高成本生成。資料夾詳情頁的卡片縮圖工作延後初次展開完成才開始，之後進出子頁不拆掉已載入的縮圖。
- 保留資料庫非同步查詢與現有圖片尺寸限制；轉場不增加完整漫畫原圖預載。
- 選用 Container Transform 的封面不再執行 SpringPress 縮放，避免來源尺寸移動／回彈與幾何轉場重複；長按、選取與拖曳回呼保留。
- 只使用路由現有的動畫，沒有為每個封面／轉場建立新 AnimationController。新增封面 RepaintBoundary 用於精準擷取封面，另有一個詳情繪製邊界隔離變形；沒有 BackdropFilter。

6. 修改檔案

新增：
- lib/core/cover_origin.dart：路由區域來源引用與快照資源所有權。
- lib/widgets/cover_container_transition.dart：容器矩形、圓角、內容交接、反向接續及失效退回。
- test/cover_container_test.dart：22 項專項測試及四張視覺檢查畫面輸出。

修改：
- lib/core/anim_route.dart：依 detail 選項啟用、有來源才捕捉、380／300ms、資源釋放與既有預測式返回串接。
- lib/core/constants.dart：集中轉場時間、快照尺寸與淡入區間。
- lib/core/motion.dart：DetailMotion 設定、copy／比較／JSON 舊版相容。
- lib/widgets/cover_hero.dart：封面繪製邊界、真實座標與來源驗證、小快照擷取。
- lib/widgets/book_card.dart、lib/widgets/folder_card.dart：每個卡片的來源 key 與 onOpen；保留 onTap 相容性。
- lib/widgets/spring_press.dart：封面交接時安全停用縮放。
- lib/widgets/motion_settings_panel.dart：詳情頁選項與無圖片的實際路由預覽。
- lib/screens/bookshelf/bookshelf_screen.dart：漫畫／資料夾點擊傳遞來源。
- lib/screens/details/category_detail_screen.dart：容器轉場期間延後首列高成本圖片工作。
- lib/screens/details/folder_detail_screen.dart：資料夾內的漫畫來源、初次展開圖片工作 gate 與 Listener 清理。
- test/hero_motion_test.dart：擴充普通／容器模式下真正漫畫及資料夾詳情頁的途中返回與減少動畫整合測試。

7. 原本 Hero 沒有展開的原因

來源 CoverHero 有 tag，但漫畫／資料夾詳情頁沒有配對的目標 Hero；此外 DetailRoute 包了 HeroMode(enabled: false)，用來避免原本的路由轉場疊加飛行。因此只有普通頁面轉場。此次改為共享「來源幾何與繪製快照」，而不是為目前布局硬加一張大封面或配對 Hero。

8. 驗證結果與限制

- flutter test --reporter expanded：201 項全部通過（原有 175，加 22 項專項測試及 4 項擴充整合情境）。
- 涵蓋不同封面位置、Cover／Contain、資料夾、3／4／5 欄與原捲動位置、快速雙指點擊只推一頁、十次途中返回、收回終點與圓角、2% 幾何上限、來源移動／刪除／途中消失、圖片讀取失敗、設定保存及系統減少動畫。
- 亦涵蓋真實 CategoryDetailScreen／FolderDetailScreen 的容器模式返回、Hero tag 唯一性、舊版功能、閱讀器縮放、排序／合併與圖片生命週期回歸。
- Android 預測式返回：透過 Flutter backGesture channel 驗證開始、更新、取消、提交及提交前後幾何連續性。
- flutter analyze --no-pub --no-fatal-infos：exit 0，零 error、零 warning；44 項原有風格／棄用 API info。未宣稱預設 analyze（info 也視為失敗）完全無提示。
- 已執行 dart format。
- 視覺檢查：build/container_preview/start.png、expanding.png、complete.png、closing.png。這些由 Flutter Widget Test 實際繪製產生；測試字型／圖示可能呈現測試用方塊，不能當作實機 UI 截圖。
- 日誌：container_tests.log、container_analysis.log。
- 尚未執行 Android 實機 Profile。仍需量測實機 snapshot 擷取成本、UI／Raster frame timing、極大量封面／動態 GIF 的記憶體峰值，以及不同 Android／OEM 的返回手勢。沒有 60／120 FPS 的實測宣稱。
