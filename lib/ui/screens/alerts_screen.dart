import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'product_detail_screen.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final low = app.lowStock;
    final exp = app.nearExpiry;

    return PendScaffold(
      titleMr: 'सूचना',
      titleEn: 'Alerts',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader('⚠️ कमी / संपलेला साठा · Low stock'),
        if (low.isEmpty)
          Container(
              decoration: cardDecoration(context),
              child: const EmptyState('✅', 'All healthy'))
        else
          CardList([
            for (final p in low)
              InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ProductDetailScreen(productId: p.id))),
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
                              '${app.stockOf(p.id).bags} bags · ${kg(app.effKg(p.id))} total · threshold ${p.lowStockThresholdBags} bags',
                              style: TextStyle(fontSize: 12, color: c.ink2)),
                        ])),
                    StatusPill(app.levelOf(p.id)),
                  ]),
                ),
              ),
          ]),
        SectionHeader('⏳ एक्सपायरी जवळ · Near expiry (30d)'),
        if (exp.isEmpty)
          Container(
              decoration: cardDecoration(context),
              child: const EmptyState('👍', 'No items near expiry'))
        else
          CardList([
            for (final e in exp)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  PhotoSwatch(e.product, size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        ProductName(e.product),
                        const SizedBox(height: 2),
                        Text(
                            'बॅच ${e.batch ?? '—'} · ${kg(app.effKg(e.product.id))} in stock',
                            style: TextStyle(fontSize: 12, color: c.ink2)),
                      ])),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                        color: c.serious.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(e.days < 0 ? 'संपली' : '${e.days} दिवस',
                        style: TextStyle(
                            color: c.serious,
                            fontWeight: FontWeight.w700,
                            fontSize: 11)),
                  ),
                ]),
              ),
          ]),
        const SizedBox(height: 12),
        Text(
            'Low-stock is measured on total kg (bags × weight + loose), so loose stock is never ignored.',
            style: TextStyle(fontSize: 11.5, color: c.muted)),
      ]),
    );
  }
}
