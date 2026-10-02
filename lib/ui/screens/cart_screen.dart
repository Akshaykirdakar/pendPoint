import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../widgets/rate_editor.dart';
import 'checkout_screen.dart';
import 'scan_screen.dart';
import '../../utils/lang.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;

    if (app.cart.isEmpty) {
      return PendScaffold(
        titleMr: 'सध्याचे बिल',
        titleEn: 'Current bill',
        body: Column(children: [
          const SizedBox(height: 40),
          EmptyState('🧾', tr('बिल रिकामे आहे\nCart is empty')),
          const SizedBox(height: 8),
          BigButton.brand(tr('📷 उत्पादन जोडा · Add product'),
              onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const ScanScreen()))),
        ]),
      );
    }

    return PendScaffold(
      titleMr: 'सध्याचे बिल',
      titleEn: 'Current bill',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CardList(
            [for (var i = 0; i < app.cart.length; i++) _line(context, app, i)]),
        const SizedBox(height: 12),
        BigButton.ghost(tr('＋ आणखी उत्पादन · Add more'),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ScanScreen()))),
        const SizedBox(height: 14),
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            _totalRow(
                context, tr('उप-बेरीज · Subtotal'), money(app.cartSubtotal)),
            if (app.cartDiscount > 0) ...[
              const SizedBox(height: 6),
              _totalRow(context, tr('सूट · Discount given'),
                  '–${money(app.cartDiscount)}',
                  color: c.serious),
            ],
            Divider(height: 22, color: c.line),
            Row(children: [
              Text(tr('एकूण · Total'),
                  style:
                      baloo(size: 17, weight: FontWeight.w800, color: c.ink)),
              const Spacer(),
              Text(money(app.cartTotal),
                  style:
                      baloo(size: 22, weight: FontWeight.w800, color: c.brand)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        BigButton.primary(tr('पेमेंट करा · Checkout — ${money(app.cartTotal)}'),
            key: const ValueKey('cart-checkout'),
            onTap: app.shortLines.isNotEmpty
                // Never sell more than is in stock.
                ? () => showToast(context, AppState.shortStockMessage)
                : () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CheckoutScreen()))),
      ]),
    );
  }

  Widget _totalRow(BuildContext context, String label, String value,
          {Color? color}) =>
      Row(children: [
        Text(label, style: TextStyle(color: context.c.ink2)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w700, color: color ?? context.c.ink)),
      ]);

  Widget _line(BuildContext context, AppState app, int i) {
    final c = context.c;
    final l = app.cart[i];
    final p = app.productOf(l.productId)!;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PhotoSwatch(p, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProductName(p),
                  const SizedBox(height: 2),
                  Wrap(spacing: 6, children: [
                    Text(
                        l.isBag
                            ? '${money(l.rate)}/${tr('गोणी · bag')}'
                            : '${money(l.rate)}/kg',
                        style: TextStyle(fontSize: 12, color: c.ink2)),
                    if (l.isOverridden) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                            color: c.accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999)),
                        child: Text(tr('भाव बदलला · Price edited'),
                            style: baloo(
                                size: 10,
                                weight: FontWeight.w700,
                                color: c.accent)),
                      ),
                    ],
                  ]),
                ]),
          ),
          const SizedBox(width: 8),
          Text(money(l.lineTotal),
              style: baloo(size: 16, weight: FontWeight.w800, color: c.ink)),
        ]),
        // Quantity controls get the full card width.
        const SizedBox(height: 10),
        Row(children: [
          _mini(context, Icons.remove, () => app.changeLineQty(i, -1)),
          const SizedBox(width: 8),
          SizedBox(
              width: 44,
              child: Text(qtyLabel(l.isBag, l.qty),
                  textAlign: TextAlign.center,
                  style:
                      baloo(size: 14, weight: FontWeight.w800, color: c.ink))),
          const SizedBox(width: 8),
          _mini(context, Icons.add, () => app.changeLineQty(i, 1)),
          const SizedBox(width: 8),
          _mini(context, Icons.currency_rupee,
              () => showEditRateSheet(context, app, i),
              label: '✎'),
          const Spacer(),
          _mini(context, Icons.delete_outline, () => app.removeLine(i),
              color: c.critical),
        ]),
      ]),
    );
  }

  Widget _mini(BuildContext context, IconData ic, VoidCallback onTap,
          {Color? color, String? label}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: context.c.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: context.c.line)),
          child: Icon(ic, size: 16, color: color ?? context.c.ink),
        ),
      );
}
