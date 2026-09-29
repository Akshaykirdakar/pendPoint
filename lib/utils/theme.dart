import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_settings.dart';

/// Design tokens for पेंड Point — a bold emerald brand with a single
/// harvest-amber action accent (green + grain), warm-biased neutrals, and
/// colorblind-safe chart hues. Available in both light and dark.
@immutable
class PendColors extends ThemeExtension<PendColors> {
  final Color brand, brand2, brandInk;
  final Color accent, accentInk;
  final Color ground, surface, surface2;
  final Color ink, ink2, muted, line;
  final Color good, warning, serious, critical;
  final Color s1, s2, s3; // chart series (blue / orange / aqua)

  const PendColors({
    required this.brand,
    required this.brand2,
    required this.brandInk,
    required this.accent,
    required this.accentInk,
    required this.ground,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.line,
    required this.good,
    required this.warning,
    required this.serious,
    required this.critical,
    required this.s1,
    required this.s2,
    required this.s3,
  });

  static const light = PendColors(
    brand: Color(0xFF0B8457),
    brand2: Color(0xFF0A6F49),
    brandInk: Color(0xFFFFFFFF),
    accent: Color(0xFFF2A30F),
    accentInk: Color(0xFF3A2A00),
    ground: Color(0xFFF4F3EE),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF8F7F3),
    ink: Color(0xFF16190F),
    ink2: Color(0xFF585A4E),
    muted: Color(0xFF8B8C7F),
    line: Color(0xFFE4E2D8),
    good: Color(0xFF0CA30C),
    warning: Color(0xFFD98A00),
    serious: Color(0xFFEC835A),
    critical: Color(0xFFD03B3B),
    s1: Color(0xFF2A78D6),
    s2: Color(0xFFEB6834),
    s3: Color(0xFF1BAF7A),
  );

  static const dark = PendColors(
    brand: Color(0xFF16A86E),
    brand2: Color(0xFF12915E),
    brandInk: Color(0xFF04150D),
    accent: Color(0xFFF5B32E),
    accentInk: Color(0xFF2A1D00),
    ground: Color(0xFF0D0F0A),
    surface: Color(0xFF181B13),
    surface2: Color(0xFF1F2318),
    ink: Color(0xFFF2F3EA),
    ink2: Color(0xFFB9BBAC),
    muted: Color(0xFF83867A),
    line: Color(0xFF2B2F22),
    good: Color(0xFF0CA30C),
    warning: Color(0xFFFAB219),
    serious: Color(0xFFEC835A),
    critical: Color(0xFFE05A5A),
    s1: Color(0xFF3987E5),
    s2: Color(0xFFD95926),
    s3: Color(0xFF199E70),
  );

  /// This palette with the brand (and, where needed, accent) colours of
  /// [theme]. Semantic colours — good / warning / serious / critical — and
  /// the neutrals are deliberately NOT themed, so success, warnings and
  /// errors look the same whichever colour theme the shop picks.
  PendColors themed(AppColorTheme theme) {
    final dark = brightness == Brightness.dark;
    final b = BrandPalette.of(theme, dark: dark);
    return PendColors(
      brand: b.brand,
      brand2: b.brand2,
      brandInk: b.brandInk,
      accent: b.accent ?? accent,
      accentInk: b.accentInk ?? accentInk,
      ground: ground,
      surface: surface,
      surface2: surface2,
      ink: ink,
      ink2: ink2,
      muted: muted,
      line: line,
      good: good,
      warning: warning,
      serious: serious,
      critical: critical,
      s1: s1,
      s2: s2,
      s3: s3,
    );
  }

  Brightness get brightness =>
      ThemeData.estimateBrightnessForColor(ground);

  @override
  PendColors copyWith() => this;

  @override
  PendColors lerp(ThemeExtension<PendColors>? other, double t) => this;
}

/// The brand colours of one colour theme (Settings → रंगाची थीम), in light
/// and dark. This is the ONE place theme colours are defined — widgets only
/// ever read `context.c.brand` etc. Each [brandInk] is chosen to keep text
/// on a [brand] background readable (≥ 4.5:1 contrast, checked in tests).
@immutable
class BrandPalette {
  final Color brand, brand2, brandInk;
  final Color? accent, accentInk; // null = keep the harvest-amber accent
  const BrandPalette(this.brand, this.brand2, this.brandInk,
      {this.accent, this.accentInk});

  static BrandPalette of(AppColorTheme theme, {required bool dark}) =>
      switch ((theme, dark)) {
        // Green = the original पेंड Point emerald (the default).
        (AppColorTheme.green, false) => const BrandPalette(
            Color(0xFF0B8457), Color(0xFF0A6F49), Color(0xFFFFFFFF)),
        (AppColorTheme.green, true) => const BrandPalette(
            Color(0xFF16A86E), Color(0xFF12915E), Color(0xFF04150D)),
        (AppColorTheme.blue, false) => const BrandPalette(
            Color(0xFF1565C0), Color(0xFF0D47A1), Color(0xFFFFFFFF)),
        (AppColorTheme.blue, true) => const BrandPalette(
            Color(0xFF5AA2EE), Color(0xFF3F8BDB), Color(0xFF03101E)),
        // Orange brand + a teal accent, so the amber accent (and the amber
        // warning colour) never blend into the brand.
        (AppColorTheme.orange, false) => const BrandPalette(
            Color(0xFFB45309), Color(0xFF92400E), Color(0xFFFFFFFF),
            accent: Color(0xFF0E7490), accentInk: Color(0xFFFFFFFF)),
        (AppColorTheme.orange, true) => const BrandPalette(
            Color(0xFFF08C2E), Color(0xFFD97A1E), Color(0xFF231200),
            accent: Color(0xFF2CC6DF), accentInk: Color(0xFF032A31)),
        (AppColorTheme.purple, false) => const BrandPalette(
            Color(0xFF6D28D9), Color(0xFF5B21B6), Color(0xFFFFFFFF)),
        (AppColorTheme.purple, true) => const BrandPalette(
            Color(0xFFA98BFA), Color(0xFF9170F0), Color(0xFF170A33)),
        // Plain = calm slate, no strong colour.
        (AppColorTheme.plain, false) => const BrandPalette(
            Color(0xFF37474F), Color(0xFF263238), Color(0xFFFFFFFF)),
        (AppColorTheme.plain, true) => const BrandPalette(
            Color(0xFFB0BEC5), Color(0xFF90A4AE), Color(0xFF0F1417)),
      };
}

/// Applies the Settings font size to everything below it by multiplying
/// the phone's own text scale — real text reflow through [TextScaler], not
/// a visual zoom, so touch targets and layouts stay intact.
class AppTextScale extends StatelessWidget {
  final AppFontSize fontSize;
  final Widget child;
  const AppTextScale({required this.fontSize, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final system = mq.textScaler.scale(100) / 100;
    final scale = (system * fontSize.scale).clamp(0.8, 2.0);
    return MediaQuery(
        data: mq.copyWith(textScaler: TextScaler.linear(scale)), child: child);
  }
}

/// Convenience accessor: `context.c.brand`.
extension PendColorsX on BuildContext {
  PendColors get c => Theme.of(this).extension<PendColors>()!;
}

/// Baloo 2 — the display / big-number face (Devanagari-capable).
TextStyle baloo(
        {double size = 16,
        FontWeight weight = FontWeight.w700,
        Color? color,
        double? height,
        double? spacing}) =>
    GoogleFonts.baloo2(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: spacing);

ThemeData buildTheme(Brightness brightness,
    [AppColorTheme colorTheme = AppColorTheme.green]) {
  final pc = (brightness == Brightness.dark ? PendColors.dark : PendColors.light)
      .themed(colorTheme);
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final textTheme = GoogleFonts.muktaTextTheme(base.textTheme).apply(
    bodyColor: pc.ink,
    displayColor: pc.ink,
  );
  return base.copyWith(
    scaffoldBackgroundColor: pc.ground,
    canvasColor: pc.ground,
    textTheme: textTheme,
    colorScheme: base.colorScheme.copyWith(
      brightness: brightness,
      primary: pc.brand,
      onPrimary: pc.brandInk,
      secondary: pc.accent,
      onSecondary: pc.accentInk,
      surface: pc.surface,
      onSurface: pc.ink,
      error: pc.critical,
    ),
    dividerColor: pc.line,
    extensions: [pc],
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: pc.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: pc.line, width: 1.5)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: pc.line, width: 1.5)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: pc.brand, width: 2)),
      labelStyle: TextStyle(color: pc.ink2, fontWeight: FontWeight.w600),
    ),
  );
}
