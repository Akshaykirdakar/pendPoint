import 'package:flutter/material.dart';

import '../../models/app_settings.dart';
import '../../utils/lang.dart';
import '../../utils/theme.dart';

/// A big picture tile: a large coloured icon and one or two words, for
/// people who recognise pictures and colours faster than they read.
/// Shows [mr] or [en] per the language setting (both: Marathi large,
/// English small underneath). [badge] is a count/amount shown in a corner.
class BigTile extends StatelessWidget {
  final IconData icon;
  final String mr;
  final String en;
  final Color color;
  final VoidCallback? onTap;
  final String? badge;
  final Color? badgeColor;

  const BigTile({
    required this.icon,
    required this.mr,
    required this.en,
    required this.color,
    required this.onTap,
    this.badge,
    this.badgeColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final enabled = onTap != null;
    final main = appLang == AppLang.en ? en : mr;
    final tile = Material(
      color: color.withValues(alpha: enabled ? 0.13 : 0.06),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 124),
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: color.withValues(alpha: enabled ? 0.45 : 0.2),
                width: 1.5),
          ),
          child: Stack(clipBehavior: Clip.none, children: [
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                      color: enabled ? color : color.withValues(alpha: 0.35),
                      shape: BoxShape.circle),
                  // White on dark circles, near-black on light ones (e.g.
                  // the pale brand colours of dark mode) — always visible.
                  child: Icon(icon,
                      size: 32,
                      color: ThemeData.estimateBrightnessForColor(color) ==
                              Brightness.dark
                          ? Colors.white
                          : Colors.black87),
                ),
                const SizedBox(height: 9),
                Text(main,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: baloo(
                        size: 17,
                        weight: FontWeight.w800,
                        color: enabled ? c.ink : c.muted)),
                if (appLang == AppLang.both)
                  Text(en,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: c.muted)),
              ]),
            ),
            if (badge != null && badge!.isNotEmpty)
              Positioned(
                top: -4,
                right: -2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: badgeColor ?? c.critical,
                      borderRadius: BorderRadius.circular(999)),
                  child: Text(badge!,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ),
              ),
          ]),
        ),
      ),
    );
    return Semantics(button: true, label: '$mr $en', child: tile);
  }
}

/// Lays tiles out in equal columns — 2 on a phone, 3 on wider screens
/// (or [columns] when given).
class TileGrid extends StatelessWidget {
  final List<Widget> children;
  final int? columns;
  final double gap;
  const TileGrid(this.children, {this.columns, this.gap = 12, super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cols = columns ?? (box.maxWidth >= 560 ? 4 : (box.maxWidth >= 420 ? 3 : 2));
      // Never negative: during a page transition or in a very narrow
      // window the space can briefly be smaller than the gaps.
      final w = ((box.maxWidth - gap * (cols - 1)) / cols)
          .clamp(0.0, double.infinity);
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final t in children) SizedBox(width: w, child: t)],
      );
    });
  }
}
