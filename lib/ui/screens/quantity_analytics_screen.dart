import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/report_query.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'bill_screen.dart';
import '../../utils/lang.dart';

/// Bags Sales Analytics / Loose Sales Analytics — one parametrized screen for
/// both (spec: a reusable drill-down architecture rather than isolated
/// screens/handlers per card). [kind] must be `.bags` or `.loose` — `.all`
/// isn't a valid drill-down target from the dashboard's Bags/Loose tiles.
/// Applies `filter.copyWith(saleType: kind)` and recomputes
/// [buildReport]/[buildTransactions] itself, same as every other drill-down
/// screen in this module (reviewed spec §20).
class QuantityAnalyticsScreen extends StatelessWidget {
  final ReportFilter filter;
  final SaleTypeFilter kind;
  const QuantityAnalyticsScreen({required this.filter, required this.kind, super.key})
      : assert(kind != SaleTypeFilter.all);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final scoped = filter.copyWith(saleType: kind);
    final result =
        buildReport(bills: app.finalBills, products: app.products, filter: scoped);
    final transactions =
        buildTransactions(bills: app.finalBills, products: app.products, filter: scoped);
    final productsById = {for (final p in app.products) p.id: p};
    final brandStats = brandStatsFrom(result.products, productsById);
    final isBags = kind == SaleTypeFilter.bags;

    return PendScaffold(
      titleMr: isBags ? 'गोणी विक्री विश्लेषण' : 'सुटी विक्री विश्लेषण',
      titleEn: isBags ? 'Bags Sales Analytics' : 'Loose Sales Analytics',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: StatTile(
                  hero: true,
                  label: isBags ? tr('एकूण गोणी · Total Bags') : tr('एकूण सुटे · Total kg'),
                  value: isBags ? '${result.bags}' : kg(result.looseKg),
                  sub: money(isBags ? result.bagsRevenue : result.looseRevenue))),
        ]),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(
              child: StatTile(
                  label: tr('विक्री · Revenue'),
                  value: money(isBags ? result.bagsRevenue : result.looseRevenue))),
          const SizedBox(width: 11),
          Expanded(
              child: StatTile(label: tr('बिले · Bills'), value: '${result.billCount}')),
        ]),
        if (result.isEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: cardDecoration(context),
            child: EmptyState('📭',
                tr('निवडलेल्या फिल्टरसाठी विक्री सापडली नाही.\nNo sales found for the selected filters.')),
          ),
        ] else ...[
          SectionHeader(tr('उत्पादननिहाय विभागणी · Product-wise breakdown')),
          CardList([
            for (final stat in result.products)
              Padding(
                padding: const EdgeInsets.all(13),
                child: Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text(
                            (() {
                              final p = app.productOf(stat.productId);
                              return p?.nameMr.isNotEmpty == true
                                  ? p!.nameMr
                                  : (p?.name ?? stat.productId);
                            })(),
                            style: baloo(size: 14, weight: FontWeight.w700, color: c.ink)),
                        Text(isBags ? '🛍️ ${stat.bags} ${L('गोणी', 'bags')}' : '${kg(stat.looseKg)} ${L('सुटे', 'loose')}',
                            style: TextStyle(fontSize: 11.5, color: c.muted)),
                      ])),
                  Text(money(stat.revenue),
                      style: baloo(size: 14, weight: FontWeight.w800, color: c.ink)),
                ]),
              ),
          ]),
          SectionHeader(tr('ब्रँडनिहाय विभागणी · Brand-wise breakdown')),
          CardList([
            for (final b in brandStats)
              Padding(
                padding: const EdgeInsets.all(13),
                child: Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text(
                            (() {
                              final br = app.brandOf(b.brandId);
                              return br == null ? b.brandId : '${br.nameMr} · ${br.name}';
                            })(),
                            style: baloo(size: 14, weight: FontWeight.w700, color: c.ink)),
                        Text(isBags ? '🛍️ ${b.bags} ${L('गोणी', 'bags')}' : '${kg(b.looseKg)} ${L('सुटे', 'loose')}',
                            style: TextStyle(fontSize: 11.5, color: c.muted)),
                      ])),
                  Text(money(b.revenue),
                      style: baloo(size: 14, weight: FontWeight.w800, color: c.ink)),
                ]),
              ),
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
}
