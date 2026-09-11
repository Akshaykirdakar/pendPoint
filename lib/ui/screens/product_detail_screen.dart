import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'cart_screen.dart';

class ProductDetailScreen extends StatelessWidget {
  final String productId;
  const ProductDetailScreen({required this.productId, super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final p = app.productOf(productId);
    if (p == null) {
      return const PendScaffold(
          titleMr: 'उत्पादन',
          titleEn: 'Product',
          body: EmptyState('❓', 'Not found'));
    }
    final s = app.stockOf(productId);
    final brand = app.brandOf(p.brandId);

    Widget priceCard(String label, String value) => Expanded(
          child: Container(
            decoration: cardDecoration(context),
            padding: const EdgeInsets.all(13),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label.toUpperCase(),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: c.muted)),
                  const SizedBox(height: 4),
                  Text(value,
                      style: baloo(
                          size: 22, weight: FontWeight.w800, color: c.ink)),
                ]),
          ),
        );

    Widget stockNum(String v, String label, {Color? color}) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(v,
                  style: baloo(
                      size: 20,
                      weight: FontWeight.w800,
                      color: color ?? c.ink)),
              Text(label, style: TextStyle(fontSize: 11, color: c.muted)),
            ]);

    return PendScaffold(
      titleMr: 'उत्पादन',
      titleEn: 'Product',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // hero swatch
        Container(
          height: 130,
          decoration: BoxDecoration(
            color: Color.alphaBlend(c.brand.withValues(alpha: 0.10), c.surface),
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Text(p.swatch, style: const TextStyle(fontSize: 60)),
        ),
        const SizedBox(height: 12),
        if (brand != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.line)),
            child: Text('${brand.nameMr} · ${brand.name}',
                style: baloo(size: 11, weight: FontWeight.w600, color: c.ink2)),
          ),
        const SizedBox(height: 6),
        ProductName(p, size: 22, showEnglish: false),
        Text('${p.name} · ${p.bagWeightKg} kg bag',
            style: TextStyle(color: c.ink2)),
        const SizedBox(height: 14),
        Row(children: [
          priceCard('पूर्ण गोणी · Bag', money(p.fullBagPrice)),
          const SizedBox(width: 11),
          priceCard('प्रति किलो · Per kg', money(p.perKgPrice))
        ]),
        const SizedBox(height: 12),
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(13),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('सध्याचा साठा · In stock',
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.ink2)),
              const Spacer(),
              StatusPill(app.levelOf(productId)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              stockNum('${s.bags}', 'पूर्ण गोणी bags'),
              const SizedBox(width: 20),
              stockNum(kg(s.looseKg), 'सुटे loose'),
              const Spacer(),
              stockNum(kg(app.effKg(productId)), 'एकूण total', color: c.brand),
            ]),
          ]),
        ),
        SectionHeader('विक्री प्रकार · Sale type'),
        BigButton.primary(
            '🛍️ पूर्ण गोणी · Add full bag — ${money(p.fullBagPrice)}',
            onTap: () => _addSheet(context, app, productId, SaleType.bag)),
        const SizedBox(height: 10),
        BigButton.ghost(
            '⚖️ किलोने · Sell by weight — ${money(p.perKgPrice)}/kg',
            onTap: () => _addSheet(context, app, productId, SaleType.kg)),
      ]),
    );
  }

  void _addSheet(
      BuildContext context, AppState app, String pid, SaleType type) {
    final p = app.productOf(pid)!;
    final isBag = type == SaleType.bag;
    final rate = p.catalogRate(isBag);
    double qty = isBag ? 1 : 1;
    final controller =
        TextEditingController(text: qty.toStringAsFixed(isBag ? 0 : 1));

    showModalBottomSheet(
      context: context,
      backgroundColor: context.c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          void bump(double d) {
            final step = isBag ? 1.0 : 0.5;
            qty = ((qty + d * step).clamp(step, 100000)).toDouble();
            qty = double.parse(qty.toStringAsFixed(2));
            controller.text = isBag ? qty.toStringAsFixed(0) : qty.toString();
            setSt(() {});
          }

          return Padding(
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
                  Text(
                      isBag
                          ? 'किती गोणी? · How many bags?'
                          : 'किती किलो? · How many kg?',
                      style: baloo(
                          size: 18,
                          weight: FontWeight.w700,
                          color: context.c.ink)),
                  const SizedBox(height: 14),
                  Row(children: [
                    _stepBtn(context, Icons.remove, () => bump(-1)),
                    Expanded(
                        child: TextField(
                      controller: controller,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: baloo(
                          size: 20,
                          weight: FontWeight.w800,
                          color: context.c.ink),
                      onChanged: (v) => qty = double.tryParse(v) ?? qty,
                    )),
                    _stepBtn(context, Icons.add, () => bump(1)),
                    const SizedBox(width: 10),
                    Text(isBag ? 'गोणी' : 'किलो',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: context.c.ink2)),
                  ]),
                  const SizedBox(height: 16),
                  BigButton.primary(
                      'बिलात जोडा · Add to bill (${money(rate * (double.tryParse(controller.text) ?? qty))})',
                      onTap: () {
                    final q = double.tryParse(controller.text) ?? qty;
                    app.addToCart(pid, type, q);
                    Navigator.pop(ctx);
                    Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const CartScreen()));
                  }),
                ]),
          );
        },
      ),
    );
  }

  Widget _stepBtn(BuildContext context, IconData ic, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: context.c.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.c.line)),
            child: Icon(ic, color: context.c.brand)),
      );
}
