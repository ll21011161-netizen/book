# GunBook 輕量按壓回彈修復

## 原因與處理

1. 原 `_tap()` 在同步 `Navigator.push` 後設定 `_snap = true`，使 AnimatedScale 的時長變成零，正常回彈被取消。這段原本用來保護舊封面 Hero 的量測；目前詳情頁已移除 Hero 目的地，正常導航不再需要這項重置。
2. 原有曲線從 0.95 回到 1 時，只產生約 1.002 的過衝，且 210ms 較短，視覺上不明顯。
3. 同一幀內按下並放開時，AnimatedScale 可能尚未繪製縮小狀態，目標便回到 1。新增 48ms 最短視覺按壓，僅延後縮放狀態的釋放，onTap 仍同步執行。

正常放開啟動回彈，不再因頁面導航設為零時長。`_snap` 保留於 TickerMode 停用、減少動畫、pointer 取消及 tap arena 交給捲動／拖曳時，確保來源卡片返回後不殘留縮小狀態。短按 Timer 在新按壓、取消、停用動畫與 dispose 時取消。

## 修改檔案

| 檔案 | 修改 |
| --- | --- |
| `lib/widgets/spring_press.dart` | 移除導航後 snap；加入短按視覺保護與取消清理；捲動／拖曳取消按壓時直接復位；非當前路由不再次觸發 onTap，避免兩個待結束的卡片手勢重複導航。保留 AnimatedScale 與穩定命中範圍，不新增 AnimationController、圖片 Overlay 或 RepaintBoundary。 |
| `lib/core/constants.dart` | 調整共用按壓參數，新增專屬 pressReleaseCurve 及 pressMinDuration。原對話框及 DragCover 使用的 springCurve 保持原值。 |
| `test/press_rebound_test.dart`（新增） | 14 項測試，量測 ScaleTransition 實際值，涵蓋書本／資料夾／按鈕、8ms 與 16ms 取樣、單次過衝、最終復位、短點擊同步導航、來源在淡入下可見、快速點擊、取消、TickerMode／減少動畫、dispose、捲動及雙卡片待處理手勢。 |
| `test/hero_motion_test.dart` | 擴充為真實漫畫與資料夾詳情頁，正常／減少動畫均測試中斷返回及來源尺寸復位。 |

已檢查 BookCard、FolderCard、ScaleButton、DetailRoute、書架與資料夾詳情手勢。前三者均共用單一 SpringPress，無需再包一層縮放。ScaleButton 目前在 lib 內沒有實際呼叫點，本次用相同 Widget 測試與實機測試版本驗證它的共用手感。

## 動畫參數

| 參數 | 修改前 | 修改後 |
| --- | --- | --- |
| 按下比例 | 0.95 | 0.94 |
| 按下時間 | 90ms | 100ms |
| 放開時間 | 210ms | 280ms |
| 按下曲線 | easeOutCubic | easeOutCubic |
| 回彈曲線 | Cubic(0.2, 0.85, 0.35, 1.15) | Cubic(0.2, 1.75, 0.35, 1) |
| 完整按壓的回彈峰值 | 約 1.002 | 約 1.0096 |
| 最短視覺按壓 | 無 | 48ms，導航不等待 |

新曲線只有一次過衝，完整按壓時約在放開後 102ms 達峰值，再柔和回到 1。短按或快速接續按壓會從當下比例接續，峰值隨按壓深度減少，不強制跳到固定過衝值。

## 導航、圖片與手勢

維持 DetailRoute 380ms 進入、320ms 返回及既有預測返回機制。沒有增加目標頁縮放、封面或轉場圖層。來源卡片在淡入初期仍可見且 TickerMode 啟用，回彈與導航同步播放；Widget 測試驗證短點擊的導航回呼立即執行，來源在新頁透明度低於 0.4 時已出現過衝。

技術取捨：回彈後段會逐漸被詳情頁遮住，但主要過衝發生於淡入初期；不為展示整段回彈而延後導航。當詳情頁完整遮住來源後，來源可安全立即復位。

按壓只更新 SpringPress 的狀態及縮放，child 保留同一 Widget；既有測試持續檢查圖片 Element 不因重複按壓更換。沒有更動圖片快取、縮圖排程、資料庫、原圖或閱讀器。拖曳的 300ms 起始、500ms 合併、排序／合併框選及浮起旋轉維持；捲動或拖曳贏得手勢時取消卡片按壓，避免同時回彈。

## 驗證結果

- 格式檢查通過，四個修改的 Dart 檔案無待格式化變更。
- 完整 `flutter test --no-pub`：135 項全部通過，包含新增 14 項與擴充導航測試。結果在 `performance_results/2026-11-07-press-repair/tests.log`。
- `flutter analyze --no-pub`：0 error、0 warning、44 項既有 info。分析結束碼為 1，來源為 info，不能宣稱完全零提示。
- 新回彈在 8ms／16ms 模擬取樣中，峰值均介於 1.007～1.012，且峰值後單調收斂至 1；這是 Widget 測試，並非 120Hz 實機驗證。
- Android arm64 profile APK 建置成功，使用獨立套件 `com.example.flutter_application_1manga.pressrepair20261107`、合成圖片及測試資料庫。未修改正式 App。
- 先前兩次執行因手機鎖定，腳本在畫面建立前查找卡片失敗，記錄在 `profile-first-failed.log` 與 `profile-retry-failed.log`，均不納入效能結論。隔離 harness 已增加前景及首幀等待；使用者解鎖後重測完成，正式 App 程式碼未再變動。

## 已完成的 Android profile 重測

Pixel 6、Android 17、profile 模式，本次顯示刷新率 90Hz，系統減少動畫原為關閉。合成圖片及獨立測試資料庫，套件 ID 與正式 App 分開。

一般動畫及減少動畫各執行：書本、資料夾、按鈕各 20 次按壓、10 次輸入視窗開關、10 次排序、1 次合併及快速捲動。兩模式皆完成，累計排序 20 次、合併 2 次，未記錄 `spring_failure` 或 `spring_error`。

一般動畫按壓的 PerfFrames 記錄如下；每個視窗包含重複按壓及最終回彈收尾，並非單幀微基準：

| 元件／20 次按壓 | 幀數 | 平均 UI | 平均 Raster | 最大 UI | 最大 Raster | 超過 16.67ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| BookCard | 367 | 1.156ms | 3.732ms | 7.673ms | 11.385ms | 0 |
| FolderCard | 366 | 1.018ms | 3.661ms | 2.799ms | 12.261ms | 0 |
| ScaleButton | 364 | 1.147ms | 2.926ms | 3.019ms | 6.740ms | 0 |

這三組沒有超過 16.67ms 的幀，但書本／資料夾 Raster 峰值超過 90Hz 的 11.11ms 預算，不能宣稱每幀都符合 90Hz 或 120Hz。減少動畫模式三組按壓沒有產生新的可量測動畫幀，平均值無定義，不能將其當成「0ms 渲染」。

拖曳操作完成，但仍觀察到 UI 尖峰：一般排序 10／426 幀超過 16.67ms、UI 最大 51.364ms；減少動畫排序 10／173 幀、UI 最大 50.984ms。一般合併 0／72 幀超時；減少動畫合併 1／38 幀超時。沒有同條件修改前 profile 對照，因此不將這些尖峰歸因於或宣稱已由本次按壓修改改善；相關書架效能仍可另行追查。

重測結果在 `profile.log`、`profile.json`、`summary.json`；最初擷取中的三組一般按壓及刷新率記錄另存 `initial-capture.json`，避免裝置 logcat 環形緩衝區後續覆寫。完整事件 JSON 合併初次擷取與完成時的擷取。數據為單機單次執行，未提供改善百分比。

修改前的兩個執行檔快照、程式差異、擴充按鈕測試的隔離 harness，以及建置與測試輸出均保存於 `performance_results/2026-11-07-press-repair/`。

尚未驗證的部分：真實使用者對彈性的主觀感受、60Hz／120Hz 實機對照，以及實機導航期間的完整視覺連續性；本次實機 harness 的卡片按壓使用空 onTap，不將其當成導航期間量測。實際漫畫／資料夾詳情導航仍由 Widget 測試驗證。未宣稱效能改善比例。
