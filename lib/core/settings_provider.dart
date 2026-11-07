// lib/core/settings_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'motion.dart';
import 'config.dart';
import 'utils.dart';

class SettingsProvider extends ChangeNotifier {
  MotionSettings _motion = const MotionSettings();
  MotionSettings get motion => _motion;
  Future<void> _motionWrites = Future<void>.value();

  void setMotion(MotionSettings value) {
    if (_isLoaded && value == _motion) return;
    _edited.add('motion_v1');
    _motion = value;
    final encoded = jsonEncode(value.toJson());
    // Serialize writes so a fast slider/reset cannot restore an older value.
    _motionWrites = _motionWrites.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString('motion_v1', encoded)) {
        throw StateError('Motion settings were not saved');
      }
    }).catchError((Object error) {
      debugPrint('Motion save failed: $error');
    });
    notifyListeners();
  }

  Future<void> flushMotionSettings() => _motionWrites;
  void resetMotion() => setMotion(const MotionSettings());

  double _zoomLevel = AppConfig.zoomMin;
  bool _rtlMode = false;
  bool _darkMode = false;
  int _bookshelfColumns = 4;
  bool _cropBookCovers = true;
  bool _isLoaded = false;
  bool _disposed = false;
  final Set<String> _edited = {};

  bool get isLoaded => _isLoaded;
  double get zoomLevel => _zoomLevel;
  bool get rtlMode => _rtlMode;
  bool get darkMode => _darkMode;
  int get bookshelfColumns => _bookshelfColumns;
  bool get cropBookCovers => _cropBookCovers;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      if (!_edited.contains('motion_v1')) {
        try {
          final raw = prefs.get('motion_v1');
          final decoded = raw is String ? jsonDecode(raw) : null;
          if (decoded is Map<String, dynamic>) {
            _motion = MotionSettings.fromJson(decoded);
          }
        } catch (_) {
          _motion = const MotionSettings();
        }
      }
      if (!_edited.contains('z_level')) {
        _zoomLevel = (prefs.getDouble('z_level') ?? 2.5)
            .clamp(AppConfig.zoomMin, AppConfig.zoomMax);
      }
      if (!_edited.contains('read_rtl')) {
        _rtlMode = prefs.getInt('read_rtl') == 1;
      }
      if (!_edited.contains('dark_mode')) {
        _darkMode = prefs.getInt('dark_mode') == 1;
      }
      if (!_edited.contains('shelf_columns')) {
        _bookshelfColumns = (prefs.getInt('shelf_columns') ?? 4).clamp(3, 5);
      }
      if (!_edited.contains('cover_crop')) {
        _cropBookCovers = (prefs.getInt('cover_crop') ?? 1) == 1;
      }
    } catch (error) {
      debugPrint('Settings load failed: $error');
    } finally {
      if (!_disposed) {
        _isLoaded = true;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void setZoomLevel(double value) {
    _edited.add('z_level');
    _zoomLevel = value.clamp(AppConfig.zoomMin, AppConfig.zoomMax).toDouble();
    AppSettings.setDouble('z_level', _zoomLevel);
    notifyListeners();
  }

  void setBookshelfColumns(int value) {
    _edited.add('shelf_columns');
    final columns = value.clamp(3, 5).toInt();
    if (_isLoaded && _bookshelfColumns == columns) return;
    _bookshelfColumns = columns;
    AppSettings.setInt('shelf_columns', columns);
    notifyListeners();
  }

  void setCropBookCovers(bool value) {
    _edited.add('cover_crop');
    if (_isLoaded && _cropBookCovers == value) return;
    _cropBookCovers = value;
    AppSettings.setInt('cover_crop', value ? 1 : 0);
    notifyListeners();
  }

  void setRtlMode(bool value) {
    _edited.add('read_rtl');
    _rtlMode = value;
    AppSettings.setInt('read_rtl', value ? 1 : 0);
    notifyListeners();
  }

  void setDarkMode(bool value) {
    _edited.add('dark_mode');
    _darkMode = value;
    AppSettings.setInt('dark_mode', value ? 1 : 0);
    notifyListeners();
  }
}
