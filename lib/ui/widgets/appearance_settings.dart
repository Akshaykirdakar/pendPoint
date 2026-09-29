import 'package:flutter/material.dart';

import '../../models/app_settings.dart';
import '../../state/app_state.dart';
import '../../utils/lang.dart';
import '../../utils/theme.dart';
import 'common.dart';

/// Font size + colour theme pickers (Settings). Saved with the other shop
/// settings, so the whole app — every screen — switches at once.
class AppearanceSettings extends StatelessWidget {
  final AppState app;
  const AppearanceSettings({required this.app, super.key});

  static String fontLabel(AppFontSize f) => switch (f) {
        AppFontSize.small => L('छोटा', 'Small'),
        AppFontSize.medium => L('मध्यम', 'Medium'),
        AppFontSize.large => L('मोठा', 'Large'),
        AppFontSize.extraLarge => L('खूप मोठा', 'Extra Large'),
      };

  static String themeLabel(AppColorTheme t) => switch (t) {
        AppColorTheme.green => L('हिरवा', 'Green'),
        AppColorTheme.blue => L('निळा', 'Blue'),
        AppColorTheme.orange => L('नारंगी', 'Orange'),
        AppColorTheme.purple => L('जांभळा', 'Purple'),
        AppColorTheme.plain => L('साधी', 'Plain'),
      };

  Future<void> _save(
      BuildContext context, void Function(AppSettings) mutate) async {
    try {
      await app.updateSettings(mutate);
      if (context.mounted) showToast(context, L('जतन झाले', 'Saved'));
    } catch (_) {
      if (context.mounted) {
        showToast(context,
            L('सेटिंग्ज जतन करता आल्या नाहीत', 'Unable to save settings'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = app.settings;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(L('अक्षरांचा आकार', 'Font Size')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final f in AppFontSize.values)
          ChoiceChip(
            key: ValueKey('font-size-${f.name}'),
            selected: s.fontSize == f,
            showCheckmark: true,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            avatar: s.fontSize == f
                ? null
                : Text('अ',
                    style: TextStyle(
                        fontSize: 14 * f.scale,
                        fontWeight: FontWeight.w800,
                        color: c.ink)),
            label: Text(fontLabel(f),
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14 * f.scale)),
            onSelected: (_) => _save(context, (x) => x.fontSize = f),
          ),
      ]),
      const SizedBox(height: 6),
      Text(
          L('नमुना: 10 गोणी × ₹1,200 = ₹12,000',
              'Sample: 10 bags × ₹1,200 = ₹12,000'),
          key: const ValueKey('font-size-sample'),
          style: TextStyle(color: c.ink2)),
      SectionHeader(L('रंगाची थीम', 'Colour Theme')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in AppColorTheme.values)
          ChoiceChip(
            key: ValueKey('color-theme-${t.name}'),
            selected: s.colorTheme == t,
            showCheckmark: true,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            avatar: CircleAvatar(
                backgroundColor: BrandPalette.of(t, dark: dark).brand,
                radius: 9),
            label: Text(themeLabel(t),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            onSelected: (_) => _save(context, (x) => x.colorTheme = t),
          ),
      ]),
    ]);
  }
}
