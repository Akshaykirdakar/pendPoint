import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../state/app_state.dart';
import '../../state/report_query.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'bill_screen.dart';
import '../../utils/lang.dart';

/// Revenue drill-down (spec: "Revenue card must become clickable"). Reads the
/// same [ReportFilter] the Reports dashboard used and recomputes
/// [buildReport]/[buildTransactions] itself — the same pattern already used
/// by [PaymentMixScreen]/[ProductHistoryScreen] — so it can never disagree
/// with the dashboard's numbers (reviewed spec §20).
class RevenueAnalyticsScreen extends StatelessWidget {
  final ReportFilter filter;
  const RevenueAnalyticsScreen({required this.filter, super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final result =
        buildReport(bills: app.finalBills, products: app.products, filter: filter);
    final transactions =
        buildTransactions(bills: app.finalBills, products: app.products, filter: filter);
    final daily = dailySeries(transactions);
    final productsById = {for (final p in app.products) p.id: p};
    final brandStats = brandStatsFrom(result.products, productsById);
    final brand = filter.brandId == null ? null : app.brandOf(filter.brandId!);
    final product = filter.productId == null ? null : app.productOf(filter.productId!);

    return PendScaffold(
      titleMr: 'विक्री विश्लेषण',
      titleEn: 'Revenue Analytics',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('लागू फिल्टर · Filters applied'),
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: c.muted)),
            const SizedBox(height: 6),
            Text('${dayFull(filter.start)} → ${dayFull(filter.end)}',
                style: baloo(size: 13.5, weight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 3),
            if (app.branches.length > 1)
              Text(
                  tr('शाखा · Branch: ${filter.branchId == null ? 'सर्व · All' : (app.branchOf(filter.branchId!)?.nameMr ?? filter.branchId!)}'),
                  style: TextStyle(fontSize: 12, color: c.ink2)),
            Text(
                '${L('ब्रँड', 'Brand')}: ${brand == null ? L('सर्व', 'All') : '${brand.nameMr} · ${brand.name}'}',
                style: TextStyle(fontSize: 12, color: c.ink2)),
            Text(
                '${L('उत्पाद', 'Product')}: ${product == null ? L('सर्व', 'All') : (product.nameMr.isNotEmpty ? product.nameMr : product.name)}',
                style: TextStyle(fontSize: 12, color: c.ink2)),
            Text('${L('विक्री प्रकार', 'Sale Type')}: ${_saleTypeLabel(filter.saleType)}',
                style: TextStyle(fontSize: 12, color: c.ink2)),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: StatTile(
                  hero: true,
                  label: tr('एकूण विक्री · Total Revenue'),
                  value: money(result.revenue),
                  sub: L('${result.billCount} बिले', '${result.billCount} bills'))),
        ]),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(
              child: StatTile(
                  label: tr('एकूण बिले · Total Bills'), value: '${result.billCount}')),
          const SizedBox(width: 11),
          Expanded(
              child: StatTile(
                  label: tr('सरासरी बिल · Avg Bill'),
                  value: result.billCount == 0
                      ? money(0)
                      : money(result.revenue / result.billCount))),
        ]),
        if (result.isEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: cardDecoration(context),
            child: EmptyState('📭',
                tr('निवडलेल्या फिल्टरसाठी विक्री सापडली नाही.\nNo sales found for the selected filters.')),
          ),
        ] else ...[
          SectionHeader(tr('पेमेंट पद्धत · Payment method')),
          Container(
            decoration: cardDecoration(context),
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              PaymentMixBar(
                  label: tr('रोख · Cash'),
                  value: result.paymentTotals[PayMode.cash] ?? 0,
                  total: result.revenue,
                  color: c.s1),
              PaymentMixBar(
                  label: 'UPI',
                  value: result.paymentTotals[PayMode.upi] ?? 0,
                  total: result.revenue,
                  color: c.s3),
              PaymentMixBar(
                  label: L('उधार (या कालावधीत नोंदवलेले)', 'Credit (recorded in period)'),
                  value: result.paymentTotals[PayMode.credit] ?? 0,
                  total: result.revenue,
                  color: c.s2),
            ]),
          ),
          SectionHeader(tr('गोणी व सुटे विक्री · Bags & Loose sales')),
          Row(children: [
            Expanded(
                child: StatTile(
                    label: tr('गोणी विक्री · Bags Sales'),
                    value: money(result.bagsRevenue),
                    sub: '🛍️ ${result.bags}')),
            const SizedBox(width: 11),
            Expanded(
                child: StatTile(
                    label: tr('सुटे विक्री · Loose Sales'),
                    value: money(result.looseRevenue),
                    sub: kg(result.looseKg))),
          ]),
          SectionHeader(tr('विक्री कल · Revenue trend')),
          Container(
            decoration: cardDecoration(context),
            padding: const EdgeInsets.all(14),
            child: RevenueTrendChart(daily),
          ),
          SectionHeader(tr('दैनंदिन विभागणी · Daily breakdown')),
          CardList([
            for (final d in daily.reversed)
              Padding(
                padding: const EdgeInsets.all(13),
                child: Row(children: [
                  Expanded(
                      child: Text(dayFull(d.day),
                          style: baloo(size: 13, weight: FontWeight.w700, color: c.ink))),
                  Text(L('${d.billCount} बिले', '${d.billCount} bills'),
                      style: TextStyle(fontSize: 11.5, color: c.ink2)),
                  const SizedBox(width: 10),
                  Text(money(d.revenue),
                      style: baloo(size: 13.5, weight: FontWeight.w800, color: c.ink)),
                ]),
              ),
          ]),
          SectionHeader(tr('टॉप उत्पादने · Top-selling products')),
          CardList([
            for (final stat in result.products.take(5))
              _productRow(context, app, stat, result.revenue),
          ]),
          SectionHeader(tr('ब्रँडनुसार विक्री · Revenue by brand')),
          CardList([
            for (final b in brandStats) _brandRow(context, app, b, result.revenue),
          ]),
          SectionHeader(tr('व्यवहार · Transactions')),
          CardList([
            for (final row in transactions)
              TransactionTile(
                bill: row.bill,
                bags: row.matchedBags,
                looseKg: row.matchedLooseKg,
                amount: row.matchedRevenue,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BillScreen(billId: row.bill.id))),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _productRow(
      BuildContext context, AppState app, ProductStat stat, double totalRevenue) {
    final c = context.c;
    final p = app.productOf(stat.productId);
    final pct = totalRevenue == 0 ? 0.0 : stat.revenue / totalRevenue;
    return Padding(
      padding: const EdgeInsets.all(13),
      child: Row(children: [
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
              Text(p?.nameMr.isNotEmpty == true ? p!.nameMr : (p?.name ?? stat.productId),
                  style: baloo(size: 14, weight: FontWeight.w700, color: c.ink)),
              Text(L('विक्रीच्या ${(pct * 100).toStringAsFixed(0)}%', '${(pct * 100).toStringAsFixed(0)}% of revenue'),
                  style: TextStyle(fontSize: 11.5, color: c.muted)),
            ])),
        Text(money(stat.revenue),
            style: baloo(size: 14, weight: FontWeight.w800, color: c.ink)),
      ]),
    );
  }

  Widget _brandRow(BuildContext context, AppState app, BrandStat stat, double totalRevenue) {
    final c = context.c;
    final b = app.brandOf(stat.brandId);
    final pct = totalRevenue == 0 ? 0.0 : stat.revenue / totalRevenue;
    return Padding(
      padding: const EdgeInsets.all(13),
      child: Row(children: [
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
              Text(b == null ? stat.brandId : '${b.nameMr} · ${b.name}',
                  style: baloo(size: 14, weight: FontWeight.w700, color: c.ink)),
              Text(L('विक्रीच्या ${(pct * 100).toStringAsFixed(0)}%', '${(pct * 100).toStringAsFixed(0)}% of revenue'),
                  style: TextStyle(fontSize: 11.5, color: c.muted)),
            ])),
        Text(money(stat.revenue),
            style: baloo(size: 14, weight: FontWeight.w800, color: c.ink)),
      ]),
    );
  }

  String _saleTypeLabel(SaleTypeFilter f) => switch (f) {
        SaleTypeFilter.all => tr('सर्व · All'),
        SaleTypeFilter.bags => tr('बॅग · Bags'),
        SaleTypeFilter.loose => tr('सुटे · Loose'),
      };
}
