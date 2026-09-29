import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/bag_stock.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../widgets/pickers.dart';
import '../../utils/lang.dart';

/// Daily bag stock — Product | Brand | Bags, the view the shop checks every
/// day. Bags only: loose kg from opened bags is intentionally not shown here
/// (it is still tracked and sold; see the Inventory tab for it).
class BagStockScreen extends StatefulWidget {
  const BagStockScreen({super.key});
  @override
  State<BagStockScreen> createState() => _BagStockScreenState();
}

class _BagStockScreenState extends State<BagStockScreen> {
  final _search = TextEditingController();
  String? _brandId;
  bool _inStockOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final rows = bagStockReport(
      products: app.products,
      brandOf: app.brandOf,
      stockOf: app.stockOf,
      query: _search.text,
      brandId: _brandId,
      inStockOnly: _inStockOnly,
    );
    final brand = _brandId == null ? null : app.brandOf(_brandId!);
    final now = DateTime.now();

    TextStyle head =
        TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c.ink2);

    return PendScaffold(
      titleMr: 'गोणी साठा',
      titleEn: 'Daily bag stock',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(L('${dayFull(now)} · ${timeShort(now)} पर्यंत', 'As of ${dayFull(now)} · ${timeShort(now)}'),
            style: TextStyle(color: c.ink2, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('bagstock-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              hintText: tr('उत्पादन, कोड किंवा ब्रँड · Product, code or brand')),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          InputChip(
            avatar: const Icon(Icons.sell_rounded, size: 16),
            label: Text(brand?.name ?? allBrandsLabel()),
            onPressed: () async {
              final b = await pickBrand(context, app, includeInactive: true);
              if (b != null) setState(() => _brandId = b.brand?.id);
            },
            onDeleted:
                brand == null ? null : () => setState(() => _brandId = null),
          ),
          FilterChip(
            label: Text(tr('साठा असलेले · In stock only')),
            selected: _inStockOnly,
            onSelected: (v) => setState(() => _inStockOnly = v),
          ),
        ]),
        const SizedBox(height: 12),
        Container(
          decoration: cardDecoration(context),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Container(
              color: c.surface2,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Expanded(
                    flex: 5, child: Text(tr('उत्पादन · Product'), style: head)),
                Expanded(flex: 3, child: Text(tr('ब्रँड · Brand'), style: head)),
                SizedBox(
                    width: 64,
                    child: Text(tr('गोणी · Bags'),
                        textAlign: TextAlign.right, style: head)),
              ]),
            ),
            if (rows.isEmpty)
              EmptyState('📦', tr('काही सापडले नाही · Nothing found'))
            else
              for (final r in rows) ...[
                Divider(height: 1, color: c.line),
                Padding(
                  key: ValueKey('bagstock-row-${r.product.id}'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Expanded(
                        flex: 5,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(r.product.nameMr,
                                  style: baloo(
                                      size: 13.5,
                                      weight: FontWeight.w700,
                                      color: c.ink)),
                              Text(
                                  '${r.product.name} · ${r.product.bagWeightKg}kg',
                                  style:
                                      TextStyle(fontSize: 11, color: c.muted)),
                            ])),
                    Expanded(
                        flex: 3,
                        child: Text(r.brand?.name ?? '—',
                            style: TextStyle(fontSize: 12.5, color: c.ink2))),
                    SizedBox(
                      width: 64,
                      child: Text('${r.bags}',
                          textAlign: TextAlign.right,
                          style: baloo(
                              size: 17,
                              weight: FontWeight.w800,
                              color: r.bags <= 0
                                  ? c.critical
                                  : (r.bags < r.product.lowStockThresholdBags
                                      ? c.serious
                                      : c.ink))),
                    ),
                  ]),
                ),
              ],
            Divider(height: 1, color: c.line),
            Container(
              color: c.surface2,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(children: [
                Expanded(
                    child: Text(L('एकूण (${rows.length} उत्पादने)', 'Total (${rows.length} products)'),
                        style: TextStyle(
                            fontWeight: FontWeight.w800, color: c.ink))),
                Text('${totalBags(rows)}',
                    key: const ValueKey('bagstock-total'),
                    style: baloo(
                        size: 19, weight: FontWeight.w800, color: c.brand)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}
