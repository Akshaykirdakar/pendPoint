import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../state/batch_alert_service.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'product_detail_screen.dart';
import '../../utils/lang.dart';

/// Inventory alerts — batch-aware per the reviewed spec §27: expired batches,
/// critical/near-expiry batches (real remaining quantity, real expiry, real
/// supplier — never hardcoded), low-stock and out-of-stock products. Reads
/// everything through [BatchAlertService] so the same batch shows the same
/// status here as on the dashboard, in Reports, and at POS.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final expired = BatchAlertService.expiredBatches(app);
    final critical = BatchAlertService.criticalBatches(app);
    final near = BatchAlertService.nearExpiryBatches(app);
    final outOfStock = BatchAlertService.outOfStockProducts(app);
    final lowStock = BatchAlertService.lowStockProducts(app);

    return PendScaffold(
      titleMr: 'सूचना',
      titleEn: 'Alerts',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(tr('⛔ एक्सपायर झालेला साठा · Expired stock')),
        if (expired.isEmpty)
          Container(
              decoration: cardDecoration(context),
              child: const EmptyState('👍', 'No expired batches'))
        else
          CardList([for (final e in expired) _batchRow(context, app, e, c.critical)]),

        SectionHeader(tr('🔴 गंभीर एक्सपायरी · Critical expiry (≤${app.settings.criticalExpiryDays}d)')),
        if (critical.isEmpty)
          Container(
              decoration: cardDecoration(context),
              child: const EmptyState('👍', 'काहीही तातडीचे नाही · Nothing critical'))
        else
          CardList([for (final e in critical) _batchRow(context, app, e, c.critical)]),

        SectionHeader(tr('🟡 नजीक एक्सपायरी · Near expiry (≤${app.settings.nearExpiryDays}d)')),
        if (near.isEmpty)
          Container(
              decoration: cardDecoration(context),
              child: const EmptyState('👍', 'No items near expiry'))
        else
          CardList([for (final e in near) _batchRow(context, app, e, c.warning)]),

        SectionHeader(tr('🔴 संपलेला साठा · Out of stock')),
        if (outOfStock.isEmpty)
          Container(
              decoration: cardDecoration(context),
              child: const EmptyState('✅', 'काहीही संपलेले नाही · Nothing out of stock'))
        else
          CardList([for (final p in outOfStock) _productRow(context, app, p)]),

        SectionHeader(tr('⚠️ कमी साठा · Low stock')),
        if (lowStock.isEmpty)
          Container(
              decoration: cardDecoration(context),
              child: const EmptyState('✅', 'All healthy'))
        else
          CardList([for (final p in lowStock) _productRow(context, app, p)]),

        const SizedBox(height: 12),
        Text(
            L('कमी साठा एकूण किलोवर मोजला जातो (गोणी × वजन + सुटे). बॅचमध्ये साठा असेपर्यंतच एक्सपायरी सूचना दिसते. मर्यादा सेटिंग्जमध्ये बदलता येतात.',
                'Low-stock is measured on total kg (bags × weight + loose). Expiry alerts only show while a batch still has stock. Thresholds are configurable in Settings.'),
            style: TextStyle(fontSize: 11.5, color: c.muted)),
      ]),
    );
  }

  Widget _batchRow(BuildContext context, AppState app, ExpiryAlert e, Color color) {
    final c = context.c;
    final p = app.productOf(e.batch.productId);
    final supplier = e.batch.supplierId == null ? null : app.supplierOf(e.batch.supplierId!);
    return InkWell(
      onTap: p == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ProductDetailScreen(productId: p.id))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          if (p != null) ...[PhotoSwatch(p, size: 46), const SizedBox(width: 12)],
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text(p?.nameMr.isNotEmpty == true ? p!.nameMr : (p?.name ?? e.batch.productId),
                    style: baloo(size: 13.5, weight: FontWeight.w700, color: c.ink)),
                Text(
                    '${L('बॅच', 'Batch')} ${e.batch.batchNo}'
                    '${supplier != null ? ' · ${supplier.name}' : ''}',
                    style: TextStyle(fontSize: 11.5, color: c.ink2)),
                Text('🛍️ ${e.batch.bagsAvailable} · ${kg(e.batch.looseKgAvailable)}',
                    style: TextStyle(fontSize: 11.5, color: c.muted)),
              ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999)),
            child: Text(
                e.isExpired
                    ? L('${-e.daysRemaining} दिवसांपूर्वी संपली', 'Expired ${-e.daysRemaining} days ago')
                    : L('${e.daysRemaining} दिवस', '${e.daysRemaining} days'),
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
          ),
        ]),
      ),
    );
  }

  Widget _productRow(BuildContext context, AppState app, Product p) {
    final c = context.c;
    return InkWell(
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: p.id))),
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
                    '🛍️ ${app.stockOf(p.id).bags} / ${p.lowStockThresholdBags}    ⚖️ ${kg(app.effKg(p.id))}',
                    style: TextStyle(fontSize: 12, color: c.ink2)),
              ])),
          StatusPill(app.levelOf(p.id)),
        ]),
      ),
    );
  }
}
