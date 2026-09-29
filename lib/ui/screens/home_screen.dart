import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../state/app_state.dart';
import '../../state/batch_alert_service.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../widgets/tiles.dart';
import 'alerts_screen.dart';
import 'bag_stock_screen.dart';
import 'khata_screen.dart';
import 'party_master_screen.dart';
import 'product_detail_screen.dart';
import 'purchase_entry_screen.dart';
import 'reports_screen.dart';
import 'returns_screen.dart';
import 'sales_entry_screen.dart';
import '../../utils/lang.dart';

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
    final low = app.lowStock; // low OR out of stock, for the section below
    final expired = BatchAlertService.expiredBatches(app);
    final critical = BatchAlertService.criticalBatches(app);
    final nearExpiry = BatchAlertService.nearExpiryBatches(app);
    final outOfStock = BatchAlertService.outOfStockProducts(app);
    final lowStockOnly = BatchAlertService.lowStockProducts(app); // excludes out-of-stock
    final alertCount = expired.length +
        critical.length +
        nearExpiry.length +
        outOfStock.length +
        lowStockOnly.length;

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
        // Today's sale in one big number; counts as icons, not words.
        StatTile(
            hero: true,
            label: tr('आजची विक्री · Today'),
            value: money(rev),
            sub: '🧾 ${today.length}    🛍️ $bagsSold    ⚖️ ${kg(kgSold)}'),
        const SizedBox(height: 14),
        // Everything the counter does daily — one big picture each.
        TileGrid([
          BigTile(
              key: const ValueKey('home-new-bill'),
              icon: Icons.point_of_sale_rounded,
              mr: 'नवीन बिल',
              en: 'New Sale',
              color: c.accent,
              onTap: () => _push(context, const SalesEntryScreen())),
          BigTile(
              key: const ValueKey('home-purchase'),
              icon: Icons.local_shipping_rounded,
              mr: 'खरेदी',
              en: 'Purchase',
              color: c.brand,
              onTap: () => _push(context, const PurchaseEntryScreen())),
          BigTile(
              icon: Icons.inventory_rounded,
              mr: 'गोणी साठा',
              en: 'Bag stock',
              color: c.s1,
              onTap: () => _push(context, const BagStockScreen())),
          BigTile(
              icon: Icons.receipt_long_rounded,
              mr: 'बिले',
              en: 'Bills',
              color: c.s2,
              onTap: () => _push(context, const ReturnsScreen())),
          BigTile(
              icon: Icons.menu_book_rounded,
              mr: 'उधार',
              en: 'Credit',
              color: c.serious,
              badge: app.totalOutstanding > 0 ? money(app.totalOutstanding) : null,
              badgeColor: c.serious,
              onTap: () => _push(context, const KhataScreen())),
          BigTile(
              icon: Icons.groups_rounded,
              mr: 'पार्टी',
              en: 'Parties',
              color: c.s3,
              onTap: () => _push(context, const PartyMasterScreen())),
          BigTile(
              icon: Icons.notifications_active_rounded,
              mr: 'सूचना',
              en: 'Alerts',
              color: c.critical,
              badge: alertCount > 0 ? '$alertCount' : null,
              onTap: () => _push(context, const AlertsScreen())),
          BigTile(
              icon: Icons.bar_chart_rounded,
              mr: 'अहवाल',
              en: 'Reports',
              color: c.ink2,
              onTap: () => _push(context, const ReportsScreen())),
        ]),
        if (alertCount > 0) ...[
          const SizedBox(height: 14),
          _alertSummaryCard(context, expired.length, critical.length + nearExpiry.length,
              lowStockOnly.length, outOfStock.length),
        ],

        SectionHeader(tr('⚠️ कमी साठा · Low stock'),
            action: TextButton(
                onPressed: () => _push(context, const AlertsScreen()),
                child: Text(L('सर्व', 'All')))),
        if (low.isEmpty)
          Container(
              decoration: cardDecoration(context),
              child: EmptyState(
                  '✅', tr('सर्व साठा पुरेसा आहे\nAll stock healthy')))
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
                                '🛍️ ${app.stockOf(p.id).bags}    ⚖️ ${kg(app.stockOf(p.id).looseKg)}',
                                style: TextStyle(fontSize: 12, color: c.ink2)),
                          ]),
                    ),
                    StatusPill(app.levelOf(p.id)),
                  ]),
                ),
              ),
          ]),

        SectionHeader(tr('📈 ७ दिवस विक्री · Last 7 days')),
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

      ]),
    );
  }

  /// Dashboard "🔔 Inventory Alerts" summary (spec §27C) — real counts from
  /// [BatchAlertService], each tappable straight to the Alerts screen (which
  /// shows the underlying records — spec §27O "never just display an alert
  /// without a path to resolve it").
  Widget _alertSummaryCard(
      BuildContext context, int expiredN, int expiringN, int lowN, int outN) {
    final c = context.c;
    Widget chip(String emoji, String label, int n, Color color) {
      if (n == 0) return const SizedBox.shrink();
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _push(context, const AlertsScreen()),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: 12.5, color: c.ink, fontWeight: FontWeight.w600))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999)),
              child: Text('$n', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            ),
            Icon(Icons.chevron_right, size: 16, color: c.muted),
          ]),
        ),
      );
    }

    return Container(
      decoration: cardDecoration(context),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(tr('🔔 इन्व्हेंटरी सूचना · Inventory Alerts'),
              style: baloo(size: 13.5, weight: FontWeight.w700, color: c.ink)),
        ),
        chip('🔴', tr('एक्सपायर बॅचेस · Expired batches'), expiredN, c.critical),
        chip('🟠', tr('लवकर एक्सपायर · Expiring soon'), expiringN, c.warning),
        chip('⚠️', tr('कमी साठा · Low stock products'), lowN, c.warning),
        chip('🔴', tr('संपलेला साठा · Out of stock'), outN, c.critical),
      ]),
    );
  }

  static bool _isToday(DateTime d) => _sameDay(d, DateTime.now());
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  static void _push(BuildContext ctx, Widget w) =>
      Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => w));
}
