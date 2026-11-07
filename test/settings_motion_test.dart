import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gun_book/core/settings_provider.dart';
import 'package:gun_book/screens/settings_screen.dart';

void main() {
  testWidgets('zoom scrubbing rebuilds locally and saves only on release',
      (tester) async {
    SharedPreferences.setMockInitialValues({'z_level': 2.5});
    final settings = SettingsProvider();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: settings, child: const MaterialApp(home: SettingsScreen())));
    await tester.pump();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('reader_zoom_setting')), 300,
        scrollable: find.byType(Scrollable));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    final slider = tester
        .widget<Slider>(find.byKey(const ValueKey('reader_zoom_setting')));
    slider.onChanged!(3.2);
    await tester.pump();
    expect(tester.widget<ListView>(find.byType(ListView)), same(list));
    expect(settings.zoomLevel, 2.5);
    expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('reader_zoom_setting')))
            .value,
        3.2);
    tester
        .widget<Slider>(find.byKey(const ValueKey('reader_zoom_setting')))
        .onChangeEnd!(3.2);
    await tester.pump();
    expect(settings.zoomLevel, 3.2);
    expect((await SharedPreferences.getInstance()).getDouble('z_level'), 3.2);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
}
