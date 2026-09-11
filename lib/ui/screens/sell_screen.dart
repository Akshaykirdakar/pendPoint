import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';
import 'scan_screen.dart';

/// Sell entry point: scan a QR or search the catalogue by brand / product.
class SellScreen extends StatefulWidget {
  const SellScreen({super.key});
  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cartN = app.cart.length;
    final q = _q.toLowerCase();
    final results = app.products.where((p) {
      final b = app.brandOf(p.brandId);
      final hay = '${p.name}${p.nameMr}${b?.name ?? ''}${b?.nameMr ?? ''}'
          .toLowerCase();
      return q.isEmpty || hay.contains(q);
    }).toList();

    return PendScaffold(
      titleMr: 'नवीन बिल',
      titleEn: 'New Sale',
      actions: [
        BarAction('🧾 बिल${cartN > 0 ? ' ($cartN)' : ''}',
            onTap: () => _push(context, const CartScreen())),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        BigButton.brand('📷 QR स्कॅन करा · Scan QR',
            icon: Icons.qr_code_scanner_rounded,
            onTap: () => _push(context, const ScanScreen())),
        const SizedBox(height: 14),
        TextField(
          decoration: const InputDecoration(
              hintText: 'शोधा · Search brand or product',
              prefixIcon: Icon(Icons.search_rounded)),
          onChanged: (v) => setState(() => _q = v),
        ),
        const SizedBox(height: 6),
        if (results.isEmpty)
          const Padding(
              padding: EdgeInsets.only(top: 20),
              child: EmptyState('🔍', 'काही सापडले नाही · No match'))
        else
          ..._byBrand(context, app, results),
      ]),
    );
  }

  List<Widget> _byBrand(
      BuildContext context, AppState app, List<Product> list) {
    final out = <Widget>[];
    for (final b in app.brands) {
      final ps = list.where((p) => p.brandId == b.id).toList();
      if (ps.isEmpty) continue;
      out.add(SectionHeader(b.name));
      out.add(CardList([for (final p in ps) _row(context, app, p)]));
    }
    return out;
  }

  Widget _row(BuildContext context, AppState app, Product p) {
    final c = context.c;
    return InkWell(
      onTap: () => _push(context, ProductDetailScreen(productId: p.id)),
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
                      '${p.bagWeightKg}kg · ${money(p.fullBagPrice)}/bag · ${money(p.perKgPrice)}/kg',
                      style: TextStyle(fontSize: 12, color: c.ink2)),
                ]),
          ),
          StatusPill(app.levelOf(p.id), label: '${app.stockOf(p.id).bags}b'),
        ]),
      ),
    );
  }

  static void _push(BuildContext ctx, Widget w) =>
      Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => w));
}
