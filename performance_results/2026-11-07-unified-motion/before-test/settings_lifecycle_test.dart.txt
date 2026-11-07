import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gun_book/core/settings_provider.dart';

void main() {
  testWidgets('settings loading after disposal does not notify',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    settings.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('an immediate user edit wins over initial preferences',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'dark_mode': 0, 'shelf_columns': 5});
    final settings = SettingsProvider();
    settings.setDarkMode(true);
    await tester.pump();
    expect(settings.isLoaded, isTrue);
    expect(settings.darkMode, isTrue);
    expect(settings.bookshelfColumns, 5);
    settings.dispose();
  });
  testWidgets('explicit defaults before load are also persisted',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'shelf_columns': 5, 'cover_crop': 0});
    final settings = SettingsProvider();
    settings.setBookshelfColumns(4);
    settings.setCropBookCovers(true);
    await tester.pump();
    expect(settings.bookshelfColumns, 4);
    expect(settings.cropBookCovers, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('shelf_columns'), 4);
    expect(prefs.getInt('cover_crop'), 1);
    settings.dispose();
  });
}
