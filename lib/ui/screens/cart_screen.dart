import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/cart_line.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'checkout_screen.dart';
import 'scan_screen.dart';

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
          const EmptyState('🧾', 'बिल रिकामे आहे\nCart is empty'),
          const SizedBox(height: 8),
          BigButton.brand('📷 उत्पादन जोडा · Add product',
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
        BigButton.ghost('＋ आणखी उत्पादन · Add more',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ScanScreen()))),
        const SizedBox(height: 14),
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            _totalRow(context, 'उप-बेरीज · Subtotal', money(app.cartSubtotal)),
            if (app.cartDiscount > 0) ...[
              const SizedBox(height: 6),
              _totalRow(context, 'सूट · Discount given',
                  '–${money(app.cartDiscount)}',
                  color: c.serious),
            ],
            Divider(height: 22, color: c.line),
            Row(children: [
              Text('एकूण · Total',
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
        BigButton.primary('पेमेंट करा · Checkout — ${money(app.cartTotal)}',
            onTap: () => Navigator.of(context).push(
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
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PhotoSwatch(p, size: 46),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ProductName(p),
                const SizedBox(height: 2),
                Row(children: [
                  Text(l.isBag ? '${money(l.rate)}/bag' : '${money(l.rate)}/kg',
                      style: TextStyle(fontSize: 12, color: c.ink2)),
                  if (l.isOverridden) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: c.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999)),
                      child: Text('भाव बदलला',
                          style: baloo(
                              size: 10,
                              weight: FontWeight.w700,
                              color: c.accent)),
                    ),
                  ],
                ]),
                const SizedBox(height: 7),
                Row(children: [
                  _mini(context, Icons.remove, () => app.changeLineQty(i, -1)),
                  const SizedBox(width: 8),
                  SizedBox(
                      width: 44,
                      child: Text(qtyLabel(l.isBag, l.qty),
                          textAlign: TextAlign.center,
                          style: baloo(
                              size: 14,
                              weight: FontWeight.w800,
                              color: c.ink))),
                  const SizedBox(width: 8),
                  _mini(context, Icons.add, () => app.changeLineQty(i, 1)),
                  const SizedBox(width: 8),
                  _mini(context, Icons.currency_rupee,
                      () => _editRate(context, app, i),
                      label: '✎'),
                  const Spacer(),
                  _mini(context, Icons.delete_outline, () => app.removeLine(i),
                      color: c.critical),
                ]),
              ]),
        ),
        const SizedBox(width: 8),
        Text(money(l.lineTotal),
            style: baloo(size: 15, weight: FontWeight.w800, color: c.ink)),
      ]),
    );
  }

  Widget _mini(BuildContext context, IconData ic, VoidCallback onTap,
          {Color? color, String? label}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: context.c.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: context.c.line)),
          child: Icon(ic, size: 16, color: color ?? context.c.ink),
        ),
      );

  // ---- price override: floor check + PIN gate ----
  void _editRate(BuildContext context, AppState app, int i) {
    final l = app.cart[i];
    final p = app.productOf(l.productId)!;
    final floor = p.floorRate(l.isBag);
    final controller = TextEditingController(text: l.rate.toStringAsFixed(0));
    String? error;

    showModalBottomSheet(
      context: context,
      backgroundColor: context.c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        Future<void> apply() async {
          final val = double.tryParse(controller.text) ?? l.rate;
          final check = app.checkRate(l, val);
          if (check == null) {
            app.setLineRate(i, val);
            Navigator.pop(ctx);
            if (val != l.catalogRate) {
              showToast(context, 'भाव बदलला · Price edited — logged for owner');
            }
            return;
          }
          if (check == 'NEEDS_PIN') {
            final ok = await _askOwnerPin(ctx, app, l, val);
            if (!ctx.mounted || !context.mounted) return;
            if (ok) {
              app.setLineRate(i, val);
              Navigator.pop(ctx);
              showToast(context, 'मंजूर · Approved — price updated');
            } else {
              setSt(() =>
                  error = 'चुकीचा PIN किंवा रद्द · Wrong PIN / cancelled');
            }
            return;
          }
          setSt(() => error = check); // floor message
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
                Text('भाव बदला · Edit price',
                    style: baloo(
                        size: 18,
                        weight: FontWeight.w700,
                        color: context.c.ink)),
                const SizedBox(height: 4),
                Text(
                    'कॅटलॉग ${money(l.catalogRate)} · किमान floor ${money(floor)}',
                    style: TextStyle(color: context.c.muted, fontSize: 12.5)),
                const SizedBox(height: 12),
                TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(prefixText: '₹ ')),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('⛔ $error',
                          style: TextStyle(
                              color: context.c.critical,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5))),
                const SizedBox(height: 14),
                BigButton.brand('लागू करा · Apply', onTap: apply),
              ]),
        );
      }),
    );
  }

  Future<bool> _askOwnerPin(
      BuildContext context, AppState app, CartLine l, double val) async {
    final pinCtrl = TextEditingController();
    final discPct = ((l.catalogRate - val) / l.catalogRate * 100).round();
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: context.c.surface,
            title: Text('मालक PIN · Owner PIN',
                style: baloo(
                    size: 18, weight: FontWeight.w700, color: context.c.ink)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                  '₹${l.catalogRate.round()} → ₹${val.round()} ($discPct% सूट) साठी PIN आवश्यक',
                  style: TextStyle(fontSize: 12.5, color: context.c.ink2)),
              const SizedBox(height: 12),
              TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  decoration: const InputDecoration(
                      hintText: 'PIN (demo 1234)', counterText: '')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('रद्द')),
              FilledButton(
                  onPressed: () =>
                      Navigator.pop(ctx, app.verifyOwnerPin(pinCtrl.text)),
                  child: const Text('मंजूर')),
            ],
          ),
        ) ??
        false;
  }
}
