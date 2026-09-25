import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../models/bill.dart';
import '../../models/enums.dart';
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../state/report_query.dart';
import '../../utils/formatters.dart';
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
    final fallback = Container(
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
    final url = product.photoUrl;
    if (url == null ||
        url.trim().isEmpty ||
        !(Uri.tryParse(url)?.hasScheme ?? false)) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .24),
      child: Image.network(url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, __, ___) => fallback,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : fallback),
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

/// Small inline note shown on Reports/Khata/Returns/History while bills,
/// customers, or stock logs are still loading in the background — after the
/// counter screen has already appeared — so a genuinely-still-loading list
/// doesn't read as a false "no data" empty state.
class HistoryLoadingNote extends StatelessWidget {
  const HistoryLoadingNote({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.muted)),
        const SizedBox(width: 9),
        Text('इतिहास लोड होत आहे... · Loading history...',
            style: TextStyle(fontSize: 12.5, color: c.muted)),
      ]),
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

/// Bottom sheet offering PDF/Excel export — shared by Reports and Product
/// History so the two screens don't grow slightly-different export UIs.
void showExportSheet(
  BuildContext context, {
  required Future<void> Function() onPdf,
  required Future<void> Function() onExcel,
  Future<void> Function()? onShare,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: context.c.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                        color: context.c.line,
                        borderRadius: BorderRadius.circular(9)))),
            Text('रिपोर्ट एक्सपोर्ट · Export Report',
                style: baloo(
                    size: 18, weight: FontWeight.w700, color: context.c.ink)),
            const SizedBox(height: 14),
            BigButton.primary('📄 PDF डाउनलोड करा · Download PDF', onTap: () {
              Navigator.pop(ctx);
              onPdf();
            }),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                  'या अहवालाची छपाईयोग्य PDF आवृत्ती तयार करते.\n'
                  'Create a print-ready PDF version of this report.',
                  style: TextStyle(fontSize: 11, color: context.c.muted)),
            ),
            const SizedBox(height: 14),
            BigButton.ghost('📊 Excel/CSV डाउनलोड करा · Download Excel', onTap: () {
              Navigator.pop(ctx);
              onExcel();
            }),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                  'स्प्रेडशीट-सुसंगत फाईल म्हणून अहवाल डेटा डाउनलोड करते.\n'
                  'Download report data as a spreadsheet-compatible file.',
                  style: TextStyle(fontSize: 11, color: context.c.muted)),
            ),
            if (onShare != null) ...[
              const SizedBox(height: 14),
              BigButton.ghost('🔗 शेअर करा · Share', onTap: () {
                Navigator.pop(ctx);
                onShare();
              }),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                    'हा अहवाल दुसऱ्या अ‍ॅप किंवा व्यक्तीसोबत शेअर करा.\n'
                    'Share this report with another app or person.',
                    style: TextStyle(fontSize: 11, color: context.c.muted)),
              ),
            ],
          ]),
    ),
  );
}

/// Small bilingual "what does this do" hint — a compact info icon that shows
/// [text] as a tooltip (hover on Web/Desktop, long-press on touch) and also
/// as a toast on tap, so the help is discoverable on every input method
/// without needing a hover-only affordance. Used throughout the Reports
/// module (date range, brand, product, payment mix, export) so every control
/// has a one-line bilingual explanation (see reviewed spec — help text).
class InfoTooltip extends StatelessWidget {
  final String text;
  final double size;
  const InfoTooltip(this.text, {this.size = 15, super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: text,
      triggerMode: TooltipTriggerMode.longPress,
      child: Semantics(
        label: text,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => showToast(context, text),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(Icons.info_outline_rounded, size: size, color: c.muted),
          ),
        ),
      ),
    );
  }
}

/// A field label with a trailing [InfoTooltip] — used for every Reports
/// filter/section header that needs a short "what this does" explanation.
class LabelWithHelp extends StatelessWidget {
  final String label;
  final String help;
  final TextStyle? style;
  const LabelWithHelp(this.label, this.help, {this.style, super.key});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: style ??
                      TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: context.c.muted))),
          const SizedBox(width: 3),
          InfoTooltip(help, size: 13),
        ],
      );
}

/// One payment-method row: label, amount, percentage and a progress bar —
/// shared by the Reports dashboard summary and the Payment Mix detail screen
/// so the two never compute or render this differently (reviewed spec §20).
class PaymentMixBar extends StatelessWidget {
  final String label;
  final double value;
  final double total;
  final Color color;
  const PaymentMixBar(
      {required this.label,
      required this.value,
      required this.total,
      required this.color,
      super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pct = total == 0 ? 0.0 : value / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('${money(value)} · ${(pct * 100).toStringAsFixed(0)}%',
              style: baloo(size: 13, weight: FontWeight.w700, color: c.ink))
        ]),
        const SizedBox(height: 4),
        ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: LinearProgressIndicator(
                value: pct.clamp(0, 1),
                minHeight: 8,
                backgroundColor: c.surface2,
                color: color)),
      ]),
    );
  }
}

/// One bill row in a transaction/drill-down list — the shared shape used by
/// Revenue Analytics, the Cash/UPI/Credit transaction screens, and the
/// Bags/Loose transaction screens, so "Bill #1025 · 13 Sep 2026 · 11:42 AM ·
/// ₹2,450 · Cash · 3 Bags + 12 kg Loose" is defined exactly once (reviewed
/// spec — reusable drill-down architecture). Tapping opens the caller's
/// [onTap], always the real [Bill] — never a duplicate bill view.
class TransactionTile extends StatelessWidget {
  final Bill bill;
  final int bags;
  final double looseKg;
  final double amount;
  final VoidCallback onTap;
  const TransactionTile({
    required this.bill,
    required this.bags,
    required this.looseKg,
    required this.amount,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final modes = bill.payments.map((p) => _modeLabel(p.mode)).toSet().join(' + ');
    final composition = [
      if (bags > 0) '$bags गोणी Bags',
      if (looseKg > 0) '${kg(looseKg)} सुटे Loose',
    ].join(' + ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text('बिल #${bill.billNumber}',
                    style: baloo(size: 13.5, weight: FontWeight.w700, color: c.ink)),
                Text(
                    bill.customerName.isEmpty
                        ? dateTimeShort(bill.at)
                        : '${dateTimeShort(bill.at)} · ${bill.customerName}',
                    style: TextStyle(fontSize: 11.5, color: c.ink2)),
                if (composition.isNotEmpty)
                  Text(composition, style: TextStyle(fontSize: 11.5, color: c.muted)),
                if (bill.creditAmount > 0)
                  Text(
                      'भरले Paid ${money(bill.total - bill.creditAmount)} · बाकी Outstanding ${money(bill.creditAmount)}',
                      style: TextStyle(
                          fontSize: 11, color: c.serious, fontWeight: FontWeight.w600)),
              ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(money(amount),
                style: baloo(size: 14, weight: FontWeight.w800, color: c.ink)),
            const SizedBox(height: 3),
            if (modes.isNotEmpty)
              Text(modes, style: TextStyle(fontSize: 11, color: c.muted)),
          ]),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 18, color: c.muted),
        ]),
      ),
    );
  }

  String _modeLabel(PayMode m) => switch (m) {
        PayMode.cash => 'Cash',
        PayMode.upi => 'UPI',
        PayMode.credit => 'Credit',
      };
}

/// A simple day-by-day revenue bar chart — no charting dependency, just
/// proportional-height bars in the same visual language as [PaymentMixBar]'s
/// progress bars. Shared by Revenue Analytics and the Payment Mix screen's
/// daily trend so both draw it identically.
class RevenueTrendChart extends StatelessWidget {
  final List<DailyPoint> points;
  const RevenueTrendChart(this.points, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (points.isEmpty) return const SizedBox.shrink();
    final maxRevenue = points.map((p) => p.revenue).fold(0.0, (a, b) => a > b ? a : b);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final p in points)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Tooltip(
                message: '${dayShort(p.day)}\n${money(p.revenue)} · ${p.billCount} bills',
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 22,
                    height: 6 +
                        (maxRevenue == 0 ? 0 : (p.revenue / maxRevenue) * 90),
                    decoration: BoxDecoration(
                        color: c.brand,
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(height: 4),
                  Text(dayShort(p.day),
                      style: TextStyle(fontSize: 9.5, color: c.muted)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
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
