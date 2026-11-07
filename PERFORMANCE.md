# GunBook performance measurements

Instrumentation is opt-in. Use the same Pixel 6, Android version, Flutter SDK,
source dataset, charging/thermal state, and profile build for both runs. Never
clear an existing user's app data for a benchmark. Use an isolated Android user
or disposable test installation and copies of the same manga files.

The pre-optimization instrumented snapshot is available in the independent Git
repository as `perf-instrumented-baseline` (commit `2c5732f`). To create a
separate checkout inside the workspace:

```powershell
git --git-dir=.baseline-git worktree add .perf-baseline perf-instrumented-baseline
```

Run the baseline checkout and current project separately with:

```powershell
flutter pub get --offline
flutter run --profile --dart-define=GUNBOOK_PERF=true -d <device-id>
```

Installing either build with the same Android application ID updates the same
app and uses its existing storage. Use an isolated Android user/test installation
and do not clear or import into a real library for benchmarking. `flutter run`
prints Dart lines starting `GUNBOOK_PERF`; Android SAF events can be captured
with `adb logcat -s GUNBOOK_PERF:I flutter:I *:S`. The logs include counts,
bytes and durations, not source paths or titles. No metrics are emitted without
`GUNBOOK_PERF=true`.

Collect at least five runs per version, record medians and ranges, and note the
number/size/type of files and storage provider. Import scan and copy are logged
separately; `sync_ms` is the time spent in file syncs within the copy time.
Database duration measures the atomic batch write. For detail pages,
`detail_paths` measures the database path query when one is needed;
`detail_first_thumbnail` and `detail_first_row` measure until the first frame
has been rendered for one or all of indices 0–3. The row event requires those
items to be built and successfully decoded, so scroll to it if necessary.
`repeat` means the same book was opened earlier in this process; it does not
prove the OS or disk cache is cold or warm. A missing event is not zero time.
Capture cold process launch, first open and repeat open separately. Profile GPU
and CPU frame timings using Flutter DevTools, along with Android memory and
storage usage; do not infer real-device FPS or memory from these logs alone.

A synthetic desktop-only import check is available:

```powershell
flutter test --no-pub --dart-define=GUNBOOK_PERF=true tool/import_perf_test.dart
```

It creates its own temporary source and database (80 synthetic files, 5 MiB),
uses the local copy path rather than Android SAF, and removes its own fixture.
In one three-run sample on Windows, pre-optimization total times were
147/107/102 ms and after times were 131/95/86 ms; notification counts were
82 and 3 respectively. The current version ran first, so OS caching, scheduling,
and the tiny workload prevent any conclusion about speedup. These are not
Pixel 6 measurements. For baseline comparison copy this benchmark file into the
baseline checkout before running it; it is not part of that historical snapshot.
