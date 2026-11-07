from pathlib import Path
root=Path('.')
def write(p,s): (root/p).write_text(s,encoding='utf-8')
def edit(p,a,b):
 s=(root/p).read_text(encoding='utf-8'); assert a in s,(p,a);write(p,s.replace(a,b))
write('lib/widgets/spring_press.dart', '''import 'package:flutter/material.dart';

/// Immediate gestures with a stable hit region; no press controller or timer.
/// The name and arguments remain compatible with existing cards and buttons.
class SpringPress extends StatelessWidget {
  const SpringPress({super.key, required this.child, required this.onTap,
    this.onLongPress, this.suppressMotion = false});
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool suppressMotion;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {
      if (!TickerMode.of(context) || ModalRoute.of(context)?.isCurrent == false) return;
      onTap();
    },
    onLongPress: onLongPress,
    child: child,
  );
}
''')
write('lib/widgets/retained_motion_tabs.dart', '''import 'package:flutter/material.dart';

/// Switch immediately while retaining both pages and their scroll positions.
class RetainedMotionTabs extends StatelessWidget {
  const RetainedMotionTabs({super.key, required this.index, required this.children});
  final int index;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
    for (var i = 0; i < children.length; i++)
      Offstage(offstage: i != index,
        child: TickerMode(enabled: i == index, child: children[i]))
  ]);
}
''')
write('lib/widgets/motion_settings_panel.dart', '''import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/settings_provider.dart';

/// Only the accessibility switch survives the retired animation preferences.
class MotionSettingsPanel extends StatelessWidget {
  const MotionSettingsPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final enabled = context.select<SettingsProvider, bool>((s) => s.motion.enabled);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('封面展開／縮回動畫'),
      subtitle: const Text('從點選的封面展開；遵循系統減少動態效果設定。'),
      value: enabled,
      onChanged: (value) {
        final settings = context.read<SettingsProvider>();
        settings.setMotion(settings.motion.copyWith(enabled: value));
      },
    );
  }
}
''')
# Preserve the legacy serialized model, but never select old visual modes.
edit('lib/core/motion.dart','this.page = PageMotion.fadeSlide','this.page = PageMotion.none')
edit('lib/core/motion.dart','this.detail = DetailMotion.followPage','this.detail = DetailMotion.containerTransform')
edit('lib/core/motion.dart','this.press = PressMotion.scale','this.press = PressMotion.none')
edit('lib/core/motion.dart',"data['page'], PageMotion.fadeSlide", "data['page'], PageMotion.none")
edit('lib/core/motion.dart',"data['detail'], DetailMotion.followPage", "data['detail'], DetailMotion.containerTransform")
edit('lib/core/motion.dart',"data['press'], PressMotion.scale", "data['press'], PressMotion.none")
s=Path('lib/core/motion.dart').read_text(encoding='utf-8'); start=s.index('  ScrollPhysics get scrollPhysics');end=s.index('  MotionSettings copyWith', start);s=s[:start]+'''  // Old bounce preferences remain readable but no longer affect scrolling.
  ScrollPhysics get scrollPhysics =>
      const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
'''+s[end:];start=s.index('    if (!settings.enabled || settings.page');s=s[:start]+'''    // Legacy callers retain their child without another page animation.
    return child;
  }
}
''';write('lib/core/motion.dart',s)
p='lib/core/anim_route.dart';s=Path(p).read_text();s=s.replace('/// Configurable route retaining','/// Single cover transition retaining');s=s.replace('if (_motion.enabled &&\n        _motion.detail == DetailMotion.containerTransform &&\n        source != null)', 'if (_motion.enabled && source != null)');start=s.index('  Duration _coverDuration');end=s.index('  @override\n  bool canTransitionFrom',start);s=s[:start]+'''  @override
  Duration get transitionDuration => hasCoverTransform
      ? AppConstants.coverEnterDuration : Duration.zero;
  @override
  Duration get reverseTransitionDuration => hasCoverTransform
      ? AppConstants.coverExitDuration : Duration.zero;
'''+s[end:];write(p,s)
p='lib/widgets/cover_hero.dart';s=Path(p).read_text();start=s.index('  @override\n  Widget build(BuildContext context) => Hero(');s=s[:start]+'''  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: _surface, child: widget.builder(report));
}
''';s=s.replace("import '../core/config.dart';\n",'').replace("import 'page_thumbnail.dart';\n",'').replace("import '../core/theme.dart';\n",'');write(p,s)
for p in ['lib/widgets/book_card.dart','lib/widgets/folder_card.dart']:
 s=Path(p).read_text(encoding='utf-8');s=s.replace("import '../core/motion.dart';\n",'');start=s.index('          suppressMotion:');end=s.index('          onTap:',start);s=s[:start]+s[end:];write(p,s)
p='lib/screens/settings_screen.dart';s=Path(p).read_text(encoding='utf-8').replace('child: ListView(','child: ListView(\n              physics: const ClampingScrollPhysics(),');write(p,s)
p='lib/widgets/smooth_input_dialog.dart';s=Path(p).read_text(encoding='utf-8');s=s.replace("import '../core/motion.dart';\n",'').replace("import '../core/constants.dart';",'//');start=s.index('    final duration =');end=s.index('    return Navigator',start);s=s[:start]+s[end:];s=s.replace('transitionDuration: duration','transitionDuration: Duration.zero');start=s.index('        transitionBuilder:');end=s.index('\n      ),',start);s=s[:start]+'''        transitionBuilder: (ctx, animation, secondary, child) => child,
        reverseDuration: Duration.zero,'''+s[end:];write(p,s)
p='lib/screens/bookshelf/bookshelf_screen.dart';s=Path(p).read_text(encoding='utf-8');s=s.replace('duration: AppConstants.motionDuration(\n                            context, AppConstants.animDurationNormal)', 'duration: Duration.zero');start=s.index('    final reduced = MediaQuery.disableAnimationsOf(context);',s.index('class PhysicsDragFeedback'));s=s[:start]+'''    // The drag overlay follows the pointer directly; no decorative lift/tilt.
    return child;
  }
}
''';write(p,s)
p='lib/widgets/drag_cover.dart';s=Path(p).read_text();s=s.replace("import 'dart:math' as math;\n",'').replace("import '../core/constants.dart';\n",'').replace("import '../core/motion.dart';\n",'');start=s.index('    final duration =');end=s.index('        child: Stack',start);s=s[:start]+'''    return SizedBox(
'''+s[end:];s=s.replace('child: AnimatedContainer(\n                duration: duration,','child: Container(');s=s.replace('child: AnimatedSwitcher(\n                  duration: duration,\n                  child: active','child: active');s=s.replace(': const SizedBox.shrink(),\n                ),',': const SizedBox.shrink(),');s=s.replace('      );\n    });','      );');write(p,s)
