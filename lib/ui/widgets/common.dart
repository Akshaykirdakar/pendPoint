import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../models/enums.dart';
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../utils/theme.dart';

/// Card surface used across the app.
BoxDecoration cardDecoration(BuildContext context,
    {Color? color, double radius = 16}) {
  final c = context.c;
  return BoxDecoration(
    color: color ?? c.surface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: c.line),
    boxShadow: [
      BoxShadow(
          color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.35
                  : 0.05),
          blurRadius: 18,
          offset: const Offset(0, 8)),
    ],
  );
}

/// Section header with an optional trailing action.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const SectionHeader(this.title, {this.action, super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 9),
        child: Row(children: [
          Expanded(
              child: Text(title,
                  style: baloo(
                      size: 15.5,
                      weight: FontWeight.w700,
                      color: context.c.ink))),
          if (action != null) action!,
        ]),
      );
}

/// A colored status pill (OK / Low / Out) — encodes state in color + shape.
class StatusPill extends StatelessWidget {
  final StockLevel level;
  final String? label;
  const StatusPill(this.level, {this.label, super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    late Color fg;
    late String text;
    switch (level) {
      case StockLevel.ok:
        fg = c.good;
        text = label ?? 'पुरेसे OK';
        break;
      case StockLevel.low:
        fg = c.warning;
        text = label ?? 'कमी Low';
        break;
      case StockLevel.out:
        fg = c.critical;
        text = label ?? 'संपले Out';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(text,
            style: TextStyle(
                color: fg, fontWeight: FontWeight.w700, fontSize: 11)),
      ]),
    );
  }
}

/// Placeholder product photo — a tinted swatch keyed by the product's emoji.
/// Replace with an Image.network(product.photoUrl) + on-device cache in prod.
class PhotoSwatch extends StatelessWidget {
  final Product product;
  final double size;
  const PhotoSwatch(this.product, {this.size = 46, super.key});

  static const _map = {
    '🟩': Color(0xFF0B8457),
    '🟢': Color(0xFF16A86E),
    '🟨': Color(0xFFEDA100),
    '🟫': Color(0xFF9A6A3A),
    '⬜': Color(0xFF8B8C7F),
    '🟧': Color(0xFFEB6834),
  };

  @override
  Widget build(BuildContext context) {
    final tint = _map[product.swatch] ?? context.c.brand;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color:
            Color.alphaBlend(tint.withValues(alpha: 0.18), context.c.surface),
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      alignment: Alignment.center,
      child: Text(product.swatch, style: TextStyle(fontSize: size * 0.48)),
    );
  }
}

/// Bilingual product name honoring the language setting.
class ProductName extends StatelessWidget {
  final Product product;
  final bool showEnglish;
  final double size;
  const ProductName(this.product,
      {this.showEnglish = true, this.size = 14.5, super.key});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().settings.lang;
    final c = context.c;
    if (lang == AppLang.en) {
      return Text(product.name,
          style: baloo(size: size, weight: FontWeight.w600, color: c.ink));
    }
    final mr = Text(product.nameMr.isEmpty ? product.name : product.nameMr,
        style: baloo(size: size, weight: FontWeight.w700, color: c.ink));
    if (lang == AppLang.mr || !showEnglish) return mr;
    return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(child: mr),
          const SizedBox(width: 6),
          Flexible(
              child: Text(product.name,
                  style: GoogleFonts.mukta(
                      fontSize: 12,
                      color: c.muted,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis)),
        ]);
  }
}

/// A big-number stat tile. [hero] paints the emerald gradient.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final bool hero;
  final Color? valueColor;
  final VoidCallback? onTap;
  const StatTile(
      {required this.label,
      required this.value,
      this.sub,
      this.hero = false,
      this.valueColor,
      this.onTap,
      super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final content = Container(
      padding: const EdgeInsets.all(14),
      decoration: hero
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                  colors: [c.brand, c.brand2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight))
          : cardDecoration(context),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: hero ? c.brandInk.withValues(alpha: 0.9) : c.muted)),
            const SizedBox(height: 6),
            Text(value,
                style: baloo(
                    size: hero ? 30 : 24,
                    weight: FontWeight.w800,
                    color: hero ? c.brandInk : (valueColor ?? c.ink))),
            if (sub != null) ...[
              const SizedBox(height: 3),
              Text(sub!,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color:
                          hero ? c.brandInk.withValues(alpha: 0.85) : c.muted)),
            ],
          ]),
    );
    if (onTap == null) return content;
    return InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(16), child: content);
  }
}

/// Primary / brand / ghost action button used across screens.
class BigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final _Kind _kind;
  final IconData? icon;
  const BigButton.primary(this.label, {this.onTap, this.icon, super.key})
      : _kind = _Kind.primary;
  const BigButton.brand(this.label, {this.onTap, this.icon, super.key})
      : _kind = _Kind.brand;
  const BigButton.ghost(this.label, {this.onTap, this.icon, super.key})
      : _kind = _Kind.ghost;
  const BigButton.danger(this.label, {this.onTap, this.icon, super.key})
      : _kind = _Kind.danger;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    late Color bg, fg;
    Border? border;
    switch (_kind) {
      case _Kind.primary:
        bg = c.accent;
        fg = c.accentInk;
        break;
      case _Kind.brand:
        bg = c.brand;
        fg = c.brandInk;
        break;
      case _Kind.ghost:
        bg = c.surface2;
        fg = c.ink;
        border = Border.all(color: c.line);
        break;
      case _Kind.danger:
        bg = c.critical.withValues(alpha: 0.14);
        fg = c.critical;
        break;
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13), border: border),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 8)
                ],
                Flexible(
                    child: Text(label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w700,
                            fontSize: 15))),
              ]),
        ),
      ),
    );
  }
}

enum _Kind { primary, brand, ghost, danger }

/// A simple list row card wrapper.
class CardList extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  const CardList(this.children, {this.padding = EdgeInsets.zero, super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) rows.add(Divider(height: 1, color: c.line));
    }
    return Container(
      decoration: cardDecoration(context),
      padding: padding,
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

/// Small empty state.
class EmptyState extends StatelessWidget {
  final String emoji;
  final String text;
  const EmptyState(this.emoji, this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(30),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 38)),
          const SizedBox(height: 8),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.c.muted, fontSize: 13.5)),
        ]),
      );
}

class InlineLoadingNotice extends StatelessWidget {
  final String text;
  const InlineLoadingNotice(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        decoration: cardDecoration(context),
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.c.brand,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: context.c.ink2,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}

void showToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      backgroundColor: context.c.ink,
    ));
}
