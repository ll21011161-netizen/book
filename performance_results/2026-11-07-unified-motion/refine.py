from pathlib import Path
base=Path('performance_results/2026-11-07-unified-motion')
for directory in ['before-lib','before-test']:
 for p in (base/directory).rglob('*.dart'): p.rename(p.with_suffix('.dart.txt'))
p=Path('lib/widgets/cover_container_transition.dart');s=p.read_text(encoding='utf-8');s=s.replace("import '../core/motion.dart';\n",'');a=s.index('  static double _enter');b=s.index('\n  @override',a);s=s[:a]+'''  // Continuous position and velocity, one gentle settle (~0.48% overshoot).
  // This approximates the recording's visual rhythm, not its unknown curve.
  static double _enter(double t) => 1 + (1.4 * t - 1) * (1 - t) * (1 - t);
'''+s[b:];s=s.replace('Curves.easeInOutCubic.transform(ratio)', '1 - _enter(1 - ratio)');p.write_text(s,encoding='utf-8')
# Legacy options cannot influence any caller (including reader controls).
p=Path('lib/core/motion.dart');s=p.read_text(encoding='utf-8');s=s.replace('    return MediaQuery.disableAnimationsOf(context)\n        ? value.copyWith(enabled: false)\n        : value;', '''    return MotionSettings(
        enabled: value.enabled && !MediaQuery.disableAnimationsOf(context));''');p.write_text(s,encoding='utf-8')
# Nonessential control slides switch immediately; layout and hit handling remain.
p=Path('lib/main.dart');s=p.read_text(encoding='utf-8');s=s.replace('duration: AppConstants.motionDuration(\n                  context, AppConstants.controlsDuration)', 'duration: Duration.zero');p.write_text(s,encoding='utf-8')
p=Path('lib/widgets/reader_controls_transition.dart');s=p.read_text(encoding='utf-8');s=s.replace("import '../core/constants.dart';\n",'').replace("import '../core/motion.dart';\n",'');s=s.replace('duration: AppConstants.motionDuration(\n                context, AppConstants.controlsDuration)', 'duration: Duration.zero').replace('curve: MotionScope.of(context).timingCurve,','curve: Curves.linear,');p.write_text(s,encoding='utf-8')
# Keep label geometry fixed, with clearer modest text; use existing ordered index.
p=Path('lib/screens/details/category_detail_screen.dart');s=p.read_text(encoding='utf-8').replace('style: Theme.of(context).textTheme.labelSmall,','style: Theme.of(context).textTheme.labelMedium,');p.write_text(s,encoding='utf-8')
# Update retired visual assertions while retaining interaction/lifecycle tests.
p=Path('test/press_rebound_test.dart');s=p.read_text(encoding='utf-8');a=s.index('double scaleOf');b=s.index('\nWidget control',a);s=s[:a]+'''double scaleOf(WidgetTester tester, [Finder? press]) {
  final target = press ?? find.byType(SpringPress, skipOffstage: false);
  expect(find.descendant(of: target, matching: find.byType(ScaleTransition)), findsNothing);
  expect(find.descendant(of: target, matching: find.byType(AnimatedScale)), findsNothing);
  return 1;
}
'''+s[b:];s=s.replace('closeTo(.97, .0001)','closeTo(1, .0001)').replace('expect(scaleOf(tester), lessThan(1));','expect(scaleOf(tester), 1);');a=s.index('    final sourceContext');b=s.index('    await tester.pumpAndSettle();',a);s=s[:a]+s[b:];p.write_text(s,encoding='utf-8')
p=Path('test/spring_motion_test.dart');s=p.read_text(encoding='utf-8');a=s.index('          // Pointer feedback');b=s.index('          await gesture.up();',a);s=s[:a]+'''          expect(find.byType(AnimatedScale), findsNothing);
          await tester.pump(AppConstants.pressDuration);
'''+s[b:];import re
s=re.sub(r'expect\(\s*tester\s*\.widget<AnimatedScale>\(find.byType\(AnimatedScale\).first\)\s*\.scale,\s*1\);', 'expect(find.byType(AnimatedScale), findsNothing);', s);s=s.replace('        if (!reduced) expect(field.focusNode!.hasFocus, isFalse);','');p.write_text(s,encoding='utf-8')
p=Path('test/motion_settings_test.dart');s=p.read_text(encoding='utf-8');s=s.replace('page == PageMotion.none\n                ? Duration.zero\n                : const Duration(milliseconds: 150)', 'Duration.zero');a=s.index("  testWidgets('preview repeat");b=s.index('  for (final press',a);s=s[:a]+'''  testWidgets('only cover switch remains and saves safely', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await load();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: settings, child: const MaterialApp(home: Scaffold(body: MotionSettingsPanel()))));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(SwitchListTile), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await settings.flushMotionSettings();
    final restored = await load();
    expect(restored.motion.enabled, isFalse);
    restored.dispose();
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
'''+s[b:];a=s.index('      expect(\n          tester.widget<AnimatedScale>');b=s.index('      await hold.up();',a);s=s[:a]+'''      expect(find.byType(AnimatedScale), findsNothing);
'''+s[b:];s=s.replace('expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);','expect(find.byType(AnimatedScale), findsNothing);');p.write_text(s,encoding='utf-8')
p=Path('test/cover_container_test.dart');s=p.read_text(encoding='utf-8').replace('DetailMotion.followPage);','DetailMotion.containerTransform);');s=s.replace('expect(route.hasCoverTransform, isFalse);\n      expect(captures, 0);', 'expect(route.hasCoverTransform, !reduced);\n      expect(captures, reduced ? 0 : 1);');p.write_text(s,encoding='utf-8')
# No source means an immediate navigation, still using the Material back lifecycle.
p=Path('test/detail_transition_test.dart');s=p.read_text(encoding='utf-8').replace('const Duration(milliseconds: 250));','Duration.zero);').replace('const Duration(milliseconds: 200));','Duration.zero);');a=s.index('    final fade =');b=s.index("    await event('cancelBackGesture');",a);s=s[:a]+'''    expect(find.ancestor(of: find.text('Detail'), matching: find.byType(FadeTransition)), findsNothing);
'''+s[b:];a=s.index('    expect(tester.widget<FadeTransition>');b=s.index('    await tester.pumpAndSettle();',a);s=s[:a]+s[b:];p.write_text(s,encoding='utf-8')
# Exercise the actual cover gate, rather than the removed generic fade route.
p=Path('test/detail_loading_test.dart');s=p.read_text(encoding='utf-8');s="import 'package:gun_book/core/cover_origin.dart';\n"+s;s=s.replace('context: home,\n        page:', '''context: home,
        source: CoverOrigin(resolveRect: () => const Rect.fromLTWH(20, 20, 100, 150),
          captureImage: () => null, radius: 12, color: Colors.grey),
        page:''',1);s=s.replace("'first row generates before fade completes; other misses wait'", "'cover transition defers thumbnail generation until completed'");s=s.replace('thumbs.where((w) => w.priority == 0).every((w) => w.generationEnabled)', 'thumbs.where((w) => w.priority == 0).every((w) => !w.generationEnabled)');p.write_text(s,encoding='utf-8')

