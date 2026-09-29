import '../models/app_settings.dart';

/// The shop's display language (Settings → भाषा). Kept here so any label can
/// be shown in it without a BuildContext; [AppState] updates it whenever
/// settings load or change, and every screen rebuilds on that change.
AppLang appLang = AppLang.both;

final _devanagari = RegExp(r'[ऀ-ॿ]');
final _latin = RegExp(r'[A-Za-z]');
final _separator = RegExp(r' · |\n');

/// Shows a bilingual label in the chosen language.
///
/// Labels across the app are written "मराठी · English" (or Marathi and
/// English on separate lines). With Marathi-only, English-only parts are
/// dropped; with English-only, Marathi-only parts are dropped. Parts that
/// are neither (numbers, ₹ amounts) or mix both scripts are always kept, so
/// nothing that carries meaning disappears. "Both" shows the label as is.
String tr(String text) => pickLang(text, appLang);

/// A label built from separate Marathi and English text (for text that
/// embeds numbers or names, where splitting on " · " would be ambiguous).
String L(String mr, String en) => switch (appLang) {
      AppLang.mr => mr,
      AppLang.en => en,
      AppLang.both => '$mr · $en',
    };

String pickLang(String text, AppLang lang) {
  if (lang == AppLang.both || !_separator.hasMatch(text)) return text;
  final parts = <String>[];
  final seps = <String>[];
  var start = 0;
  for (final m in _separator.allMatches(text)) {
    parts.add(text.substring(start, m.start));
    seps.add(m.group(0)!);
    start = m.end;
  }
  parts.add(text.substring(start));

  bool keep(String p) {
    final mr = _devanagari.hasMatch(p);
    final en = _latin.hasMatch(p);
    if (mr == en) return true; // neutral or mixed
    return lang == AppLang.mr ? mr : en;
  }

  final out = StringBuffer();
  var wrote = false;
  for (var i = 0; i < parts.length; i++) {
    if (!keep(parts[i])) continue;
    if (wrote) out.write(seps[i - 1] == '\n' ? '\n' : ' · ');
    out.write(parts[i]);
    wrote = true;
  }
  final result = out.toString().trim();
  return result.isEmpty ? text : result;
}

/// "सर्व ब्रँड · All Brands" in the shop's language — the one label every
/// optional brand filter uses (no brand = no restriction).
String allBrandsLabel() => L('सर्व ब्रँड', 'All Brands');
