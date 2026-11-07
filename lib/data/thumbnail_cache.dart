import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/perf_log.dart';
import '../core/config.dart';
import 'thumbnail_scheduler.dart';

/// Disposable, app-cache-only thumbnails. Originals are never modified.
class ThumbnailCache {
  ThumbnailCache(
      {Future<Directory> Function()? directory,
      int maxConcurrent = 1,
      this.maxBytes = 256 * 1024 * 1024})
      : _directory = directory ?? _defaultDirectory,
        _scheduler = ThumbnailScheduler(maxConcurrent: maxConcurrent);
  static final instance = ThumbnailCache(
      maxConcurrent:
          const int.fromEnvironment('GUNBOOK_THUMB_WORKERS', defaultValue: 1));
  // Keep one LRU directory across key versions so obsolete thumbnails still
  // count toward the quota. The version/width in each key prevents stale hits.
  static Future<Directory> _defaultDirectory() async => Directory(
      p.join((await getTemporaryDirectory()).path, 'gunbook_thumbnails_v1'));
  final Future<Directory> Function() _directory;
  Future<Directory>? _directoryRequest;
  final ThumbnailScheduler _scheduler;
  final int maxBytes;
  final Map<String, Future<String?>> _pending = {};
  final Map<String, Future<String?>> _lookups = {};
  final Map<String, List<_Demand>> _demand = {};
  final Map<String, int> _leases = {};
  final Map<String, String> _targets = {};
  final Set<String> _writing = {};
  final Map<String, FileStat> _validated = {};
  Future<void>? _cleaning;
  DateTime? _lastCleanup;

  // path_provider uses a platform call. Resolve once per cache instance and
  // share concurrent requests, while allowing transient provider failures to
  // recover on the next request.
  Future<Directory> _cacheDirectory() async {
    final request = _directoryRequest ??= Future.sync(_directory);
    try {
      return await request;
    } catch (_) {
      if (identical(_directoryRequest, request)) _directoryRequest = null;
      rethrow;
    }
  }

  void retain(String source) =>
      _leases.update(source, (n) => n + 1, ifAbsent: () => 1);
  void release(String source) {
    final count = _leases[source] ?? 0;
    if (count > 1) {
      _leases[source] = count - 1;
    } else {
      _leases.remove(source);
      if (!_pending.containsKey(source)) _targets.remove(source);
    }
  }

  Future<String?> get(String source,
      {bool Function()? isNeeded, int Function()? priority}) {
    (_demand[source] ??= [])
        .add(_Demand(isNeeded ?? () => true, priority ?? () => 0));
    return _pending[source] ??= _request(source);
  }

  /// Hit-only lookup for covers: a miss must not put the first visible image
  /// behind the serial PNG generation queue. Call get after it has rendered.
  Future<String?> getExisting(String source) =>
      _lookups[source] ??= _lookup(source);

  Future<String?> _lookup(String source) async {
    final watch = Stopwatch()..start();
    try {
      final entry = await _locate(source);
      if (entry == null) return null;
      final result = await _hit(entry.target, watch, kind: 'lookup');
      if (result == null) PerfLog.event('thumbnail_miss', {'kind': 'lookup'});
      return result;
    } catch (_) {
      return null;
    } finally {
      _lookups.remove(source);
      if (!_leases.containsKey(source) && !_pending.containsKey(source)) {
        _targets.remove(source);
      }
    }
  }

  Future<({FileStat stat, Directory directory, File target})?> _locate(
      String source) async {
    final stat = await File(source).stat();
    if (stat.type != FileSystemEntityType.file || stat.size <= 0) return null;
    final key = sha256
        .convert(utf8.encode(
            'v${AppConfig.thumbnailCacheVersion}:${AppConfig.diskThumbnailWidth}:$source\u0000${stat.size}\u0000${stat.modified.microsecondsSinceEpoch}'))
        .toString();
    final directory = await _cacheDirectory();
    final target = File(p.join(directory.path, '$key.png'));
    _targets[source] = target.path;
    return (stat: stat, directory: directory, target: target);
  }

  Future<String?> _hit(File target, Stopwatch watch,
      {required String kind}) async {
    final stat = await _valid(target);
    if (stat == null) return null;
    if (DateTime.now().difference(stat.modified).inHours >= 1) {
      await target.setLastModified(DateTime.now());
    }
    PerfLog.event('thumbnail_hit',
        {'elapsed_us': watch.elapsedMicroseconds, 'kind': kind});
    return target.path;
  }

  Future<String?> _request(String source) async {
    final watch = Stopwatch()..start();
    try {
      final entry = await _locate(source);
      if (entry == null) return null;
      final (:stat, :directory, :target) = entry;
      final hit = await _hit(target, watch, kind: 'generate');
      if (hit != null) return hit;
      PerfLog.event('thumbnail_miss', {'kind': 'generate'});
      return await _scheduler.run(
          () async {
            final queueUs = watch.elapsedMicroseconds;
            final decodeWatch = Stopwatch()..start();
            _writing.add(target.path);
            try {
              final result = await _generate(source, stat, directory, target);
              PerfLog.event('thumbnail_generate', {
                'queue_us': queueUs,
                'elapsed_us': decodeWatch.elapsedMicroseconds,
                'success': result != null,
                ...PerfLog.memory()
              });
              return result;
            } finally {
              _writing.remove(target.path);
            }
          },
          isNeeded: () => _demand[source]?.any((d) => d.needed()) ?? false,
          priority: () {
            final active = _demand[source]?.where((d) => d.needed());
            return active == null || active.isEmpty
                ? 2
                : active
                    .map((d) => d.priority())
                    .reduce((a, b) => a < b ? a : b);
          });
    } catch (_) {
      return null;
    } finally {
      _pending.remove(source);
      _demand.remove(source);
      if (!_leases.containsKey(source)) _targets.remove(source);
      // Maintenance must not compete with the visible thumbnail batch for I/O.
      if (_pending.isEmpty) _scheduleCleanup();
    }
  }

  // Atomic writes protect generated results; both ends reject truncation.
  // Decoder errors in the middle are handled by invalidate + original fallback.
  Future<FileStat?> _valid(File file) async {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file || stat.size < 45) return null;
    final known = _validated.remove(file.path);
    if (known != null &&
        known.size == stat.size &&
        known.modified == stat.modified) {
      _remember(file.path, stat);
      return stat;
    }
    final reader = await file.open();
    try {
      final head = await reader.read(8);
      await reader.setPosition(await reader.length() - 12);
      final end = await reader.read(12);
      final valid = base64Encode(head) == 'iVBORw0KGgo=' &&
          base64Encode(end) == 'AAAAAElFTkSuQmCC';
      if (valid) _remember(file.path, stat);
      return valid ? stat : null;
    } finally {
      await reader.close();
    }
  }

  void _remember(String path, FileStat stat) {
    _validated.remove(path);
    if (_validated.length >= 256) _validated.remove(_validated.keys.first);
    _validated[path] = stat;
  }

  Future<void> invalidate(String source, String cached) async {
    if (_targets[source] != cached || _writing.contains(cached)) return;
    final directory = await _cacheDirectory();
    if (p.dirname(cached) != directory.path ||
        !RegExp(r'^[a-f0-9]{64}\.png$').hasMatch(p.basename(cached))) {
      return;
    }
    try {
      await File(cached).delete();
      _validated.remove(cached);
    } on FileSystemException {/* evicted */}
  }

  Future<String?> _generate(
      String source, FileStat stat, Directory directory, File target) async {
    await directory.create(recursive: true);
    ui.Codec? codec;
    ui.Image? image;
    File? temporary;
    try {
      final stage = Stopwatch();
      if (PerfLog.enabled) stage.start();
      final buffer = await ui.ImmutableBuffer.fromFilePath(source);
      codec = await ui.instantiateImageCodecFromBuffer(buffer,
          targetWidth: AppConfig.diskThumbnailWidth, allowUpscaling: false);
      image = (await codec.getNextFrame()).image;
      final decodeUs = stage.elapsedMicroseconds;
      stage.reset();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      final encodeUs = stage.elapsedMicroseconds;
      stage.reset();
      final now = await File(source).stat();
      if (now.type != FileSystemEntityType.file ||
          now.size != stat.size ||
          now.modified != stat.modified) {
        return null;
      }
      temporary =
          File('${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
      await temporary.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      await temporary.rename(target.path);
      _remember(target.path, await target.stat());
      if (PerfLog.enabled) {
        PerfLog.event('thumbnail_stages', {
          'decode_us': decodeUs,
          'encode_us': encodeUs,
          'write_validate_us': stage.elapsedMicroseconds,
          'bytes': data.lengthInBytes,
          'width': image.width,
          'height': image.height
        });
      }
      return target.path;
    } finally {
      image?.dispose();
      codec?.dispose();
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  void _scheduleCleanup() {
    final now = DateTime.now();
    if (_lastCleanup != null && now.difference(_lastCleanup!).inMinutes < 10) {
      return;
    }
    _lastCleanup = now;
    unawaited(trim());
  }

  /// Best effort LRU; never visits original directories. Active widget leases
  /// protect displayed results; recent unleased files still obey the quota.
  Future<void> trim() =>
      _cleaning ??= _trim().whenComplete(() => _cleaning = null);
  Future<void> _trim() async {
    try {
      final directory = await _cacheDirectory();
      if (!await directory.exists()) return;
      final files = <MapEntry<File, FileStat>>[];
      var bytes = 0;
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is! File ||
            !RegExp(r'^[a-f0-9]{64}\.png$').hasMatch(p.basename(entry.path))) {
          continue;
        }
        final stat = await entry.stat();
        bytes += stat.size;
        files.add(MapEntry(entry, stat));
      }
      files.sort((a, b) => a.value.modified.compareTo(b.value.modified));
      final now = DateTime.now();
      for (final entry in files) {
        final age = now.difference(entry.value.modified);
        if (bytes <= maxBytes && age.inDays < 30) continue;
        if (_writing.contains(entry.key.path) ||
            _targets.containsValue(entry.key.path)) {
          continue;
        }
        await entry.key.delete();
        _validated.remove(entry.key.path);
        bytes -= entry.value.size;
      }
      PerfLog.event('thumbnail_trim', {'remaining_bytes': bytes});
    } catch (_) {/* Cache cleanup must not prevent reading. */}
  }
}

class _Demand {
  _Demand(this.needed, this.priority);
  final bool Function() needed;
  final int Function() priority;
}
