import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'alerts_screen.dart';
import 'product_detail_screen.dart';
import 'reports_screen.dart';
import 'scan_screen.dart';
import 'stock_in_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final today = app.finalBills.where((b) => _isToday(b.at)).toList();
    final rev = today.fold(0.0, (s, b) => s + b.total);
    var bagsSold = 0;
    var kgSold = 0.0;
    for (final b in today) {
      for (final i in b.items) {
        if (i.saleType == SaleType.bag) {
          bagsSold += i.qty.round();
        } else {
          kgSold += i.qty;
        }
      }
    }
    final low = app.lowStock;
    final alertCount = low.length;

    // last 7 days revenue
    final days = List.generate(7, (i) {
      final d = DateTime.now().subtract(Duration(days: 6 - i));
      final v = app.finalBills
          .where((b) => _sameDay(b.at, d))
          .fold(0.0, (s, b) => s + b.total);
      return (label: weekdayShort(d), v: v);
    });
    final maxV = days.map((d) => d.v).fold(1.0, (a, b) => a > b ? a : b);

    return PendScaffold(
      titleMr: 'नमस्कार 👋',
      titleEn: app.settings.shop,
      actions: [
        BarAction('🔔 $alertCount',
            onTap: () => _push(context, const AlertsScreen()))
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // hero + quick actions
        StatTile(
            hero: true,
            label: 'आजची विक्री · Today',
            value: money(rev),
            sub: '${today.length} bills · $bagsSold bags · ${kg(kgSold)}'),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(
              child: StatTile(
                  label: '＋ नवीन बिल',
                  value: 'New Sale',
                  sub: 'Scan or search',
                  valueColor: c.accent,
                  onTap: () => _push(context, const ScanScreen()))),
          const SizedBox(width: 11),
          Expanded(
              child: StatTile(
                  label: '📦 साठा भरा',
                  value: 'Stock in',
                  sub: 'Add purchase',
                  valueColor: c.brand,
                  onTap: () => _push(context, const StockInScreen()))),
        ]),

        SectionHeader('⚠️ कमी साठा · Low stock',
            action: TextButton(
                onPressed: () => _push(context, const AlertsScreen()),
                child: const Text('सर्व'))),
        if (low.isEmpty)
          Container(
              decoration: cardDecoration(context),
              child: const EmptyState(
                  '✅', 'सर्व साठा पुरेसा आहे\nAll stock healthy'))
        else
          CardList([
            for (final p in low.take(4))
              InkWell(
                onTap: () =>
                    _push(context, ProductDetailScreen(productId: p.id)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    PhotoSwatch(p, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ProductName(p),
                            const SizedBox(height: 2),
                            Text(
                                '${app.stockOf(p.id).bags} bags · ${kg(app.stockOf(p.id).looseKg)} loose',
                                style: TextStyle(fontSize: 12, color: c.ink2)),
                          ]),
                    ),
                    StatusPill(app.levelOf(p.id)),
                  ]),
                ),
              ),
          ]),

        SectionHeader('📈 ७ दिवस विक्री · Last 7 days'),
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          height: 150,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in days)
                Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          height: (d.v / maxV * 96).clamp(3, 96),
                          decoration: BoxDecoration(
                              color: c.s1,
                              borderRadius: BorderRadius.circular(6)),
                        ),
                        const SizedBox(height: 5),
                        Text(d.label,
                            style: TextStyle(
                                fontSize: 10,
                                color: c.muted,
                                fontWeight: FontWeight.w600)),
                      ]),
                ),
            ],
          ),
        ),

        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: StatTile(
                  label: '📒 उधार बाकी',
                  value: money(app.totalOutstanding),
                  sub:
                      '${app.customers.where((x) => x.outstanding > 0).length} owe',
                  valueColor: c.serious)),
          const SizedBox(width: 11),
          Expanded(
              child: StatTile(
                  label: '📊 अहवाल',
                  value: 'Reports',
                  sub: 'Sales & discounts',
                  onTap: () => _push(context, const ReportsScreen()))),
        ]),
      ]),
    );
  }

  static bool _isToday(DateTime d) => _sameDay(d, DateTime.now());
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  static void _push(BuildContext ctx, Widget w) =>
      Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => w));
}
