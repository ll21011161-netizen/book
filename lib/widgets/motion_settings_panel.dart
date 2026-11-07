import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/settings_provider.dart';

/// Only the accessibility switch survives the retired animation preferences.
class MotionSettingsPanel extends StatelessWidget {
  const MotionSettingsPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final enabled =
        context.select<SettingsProvider, bool>((s) => s.motion.enabled);
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
