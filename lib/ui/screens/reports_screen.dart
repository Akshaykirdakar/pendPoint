import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bill.dart';
import '../../models/enums.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _days = 7; // 1 = today

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final since = DateTime.now().subtract(Duration(days: _days - 1));
    final start = DateTime(since.year, since.month, since.day);
    final bills = app.finalBills.where((b) => b.at.isAfter(start)).toList();

    final rev = bills.fold(0.0, (s, b) => s + b.total);
    var bags = 0;
    var kgs = 0.0;
    var disc = 0.0;
    final byProd = <String, double>{};
    final overr = <({Bill bill, BillItem item})>[];
    final pay = {PayMode.cash: 0.0, PayMode.upi: 0.0, PayMode.credit: 0.0};
    for (final b in bills) {
      disc += b.discountTotal;
      for (final p in b.payments) {
        pay[p.mode] = (pay[p.mode] ?? 0) + p.amount;
      }
      for (final i in b.items) {
        if (i.saleType == SaleType.bag) {
          bags += i.qty.round();
        } else {
          kgs += i.qty;
        }
        byProd[i.productId] = (byProd[i.productId] ?? 0) + i.lineTotal;
        if (i.isPriceOverridden) overr.add((bill: b, item: i));
      }
    }
    final top = byProd.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topN = top.take(5).toList();

    Widget bar(String label, double value, Color color) {
      final pct = rev == 0 ? 0.0 : value / rev;
      return Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(money(value),
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

    return PendScaffold(
      titleMr: 'अहवाल',
      titleEn: 'Reports',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _seg(context),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: StatTile(
                  hero: true,
                  label: 'विक्री · Revenue',
                  value: money(rev),
                  sub: '${bills.length} bills')),
        ]),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(child: StatTile(label: 'गोणी · Bags', value: '$bags')),
          const SizedBox(width: 11),
          Expanded(child: StatTile(label: 'सुटे · Loose', value: kg(kgs))),
        ]),
        SectionHeader('पेमेंट विभागणी · Payment mix'),
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            bar('रोख Cash', pay[PayMode.cash] ?? 0, c.s1),
            bar('UPI', pay[PayMode.upi] ?? 0, c.s3),
            bar('उधार Credit', pay[PayMode.credit] ?? 0, c.s2),
          ]),
        ),
        SectionHeader('टॉप उत्पादने · Top products'),
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: topN.isEmpty
              ? const EmptyState('📊', 'No sales in range')
              : Column(children: [
                  for (final e in topN)
                    bar(app.productOf(e.key)?.nameMr ?? '', e.value, c.brand)
                ]),
        ),
        SectionHeader('💸 भाव-बदल अहवाल · Discount / override'),
        Container(
          decoration: cardDecoration(context),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Container(
              color: c.surface2,
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      Text('एकूण सूट दिली · Total discount',
                          style: baloo(
                              size: 13, weight: FontWeight.w700, color: c.ink)),
                      Text('${overr.length} line items had edited price',
                          style: TextStyle(fontSize: 11.5, color: c.ink2)),
                    ])),
                Text(money(disc),
                    style: baloo(
                        size: 15, weight: FontWeight.w800, color: c.serious)),
              ]),
            ),
            if (overr.isEmpty)
              const EmptyState('👍', 'कोणतीही किंमत बदलली नाही · No overrides')
            else
              for (final o in overr.take(10))
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Text(
                              '${app.productOf(o.item.productId)?.nameMr ?? ''}  #${o.bill.billNumber}',
                              style: baloo(
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: c.ink)),
                          Text(
                              'कॅटलॉग ${money(o.item.catalogRate)} → भाव ${money(o.item.rate)}',
                              style: TextStyle(fontSize: 11.5, color: c.ink2)),
                        ])),
                    Text('–${money(o.item.discountAmount)}',
                        style: baloo(
                            size: 13.5,
                            weight: FontWeight.w800,
                            color: c.serious)),
                  ]),
                ),
          ]),
        ),
        const SizedBox(height: 12),
        Text(
            'Every edited price stores the original catalogue rate — so this report shows exactly how much was discounted.',
            style: TextStyle(fontSize: 11.5, color: c.muted)),
      ]),
    );
  }

  Widget _seg(BuildContext context) {
    final c = context.c;
    Widget b(String label, int d) {
      final on = _days == d;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _days = d),
          child: Container(
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: on ? c.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                boxShadow: on
                    ? [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 6)
                      ]
                    : null),
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: on ? c.brand : c.ink2)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line)),
      child: Row(children: [b('आज', 1), b('७ दिवस', 7), b('महिना', 30)]),
    );
  }
}
