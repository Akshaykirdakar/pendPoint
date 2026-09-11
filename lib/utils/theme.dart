import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  @override
  PendColors copyWith() => this;

  @override
  PendColors lerp(ThemeExtension<PendColors>? other, double t) => this;
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

ThemeData buildTheme(Brightness brightness) {
  final pc = brightness == Brightness.dark ? PendColors.dark : PendColors.light;
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
