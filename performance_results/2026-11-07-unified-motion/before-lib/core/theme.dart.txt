// lib/core/theme.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart'; 

class AppTheme {
  static const accent = Color(0xFF6750A4);
  static const double cornerRadius = 20;

  static void setSystemStyle(bool isDark) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    ));
  }

  static ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness);
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      textTheme: GoogleFonts.notoSansTcTextTheme(base.textTheme),
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(backgroundColor: scheme.surface, elevation: 0),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        side: BorderSide(color: scheme.outlineVariant),
        selectedColor: scheme.secondaryContainer,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
    );
  }

  static ThemeData get lightTheme => _theme(Brightness.light);
  static ThemeData get darkTheme => _theme(Brightness.dark);
}

class AppStyles {
  // 💡 我們將顏色交給 Theme 自動決定，這裡只保留字體大小與粗細設定
  static final title = GoogleFonts.notoSansTc(
    fontSize: 18, 
    fontWeight: FontWeight.w900, 
    letterSpacing: 0.5, 
  );
  
  static final subtitle = GoogleFonts.notoSansTc(
    fontSize: 12, 
    fontWeight: FontWeight.w700, 
    letterSpacing: 0.3,
  );
  
  static final cardRadius = BorderRadius.circular(8);
  static final dialogShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
}