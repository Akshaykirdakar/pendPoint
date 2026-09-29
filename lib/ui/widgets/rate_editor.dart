import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../state/cart_line.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import 'common.dart';
import '../../utils/lang.dart';

/// Price override for cart line [i]: enforces the price floor and asks for
/// the Owner PIN above the discount gate (see [AppState.checkRate]). Shared
/// by the cart and the sales entry grid.
void showEditRateSheet(BuildContext context, AppState app, int i) {
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
            showToast(context, tr('या बिलाचा दर बदलला · Rate changed for this bill'));
          }
          return;
        }
        if (check == 'NEEDS_PIN') {
          final ok = await askOwnerPin(ctx, app, l, val);
          if (!ctx.mounted || !context.mounted) return;
          if (ok) {
            app.setLineRate(i, val);
            Navigator.pop(ctx);
            showToast(context, tr('मंजूर · Approved — rate changed for this bill'));
          } else {
            setSt(
                () => error = tr('चुकीचा PIN किंवा रद्द · Wrong PIN / cancelled'));
          }
          return;
        }
        setSt(() => error = tr(check)); // floor message
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
              Text(tr('बिलासाठी दर बदला · Change rate for this bill'),
                  style: baloo(
                      size: 18, weight: FontWeight.w700, color: context.c.ink)),
              const SizedBox(height: 4),
              Text(
                  '${L('कॅटलॉग', 'Catalogue')} ${money(l.catalogRate)} · ${L('किमान', 'Floor')} ${money(floor)}',
                  style: TextStyle(color: context.c.muted, fontSize: 12.5)),
              const SizedBox(height: 6),
              Text(
                  L('हा दर फक्त या बिलासाठी आहे — उत्पादनाचा मूळ भाव बदलणार नाही.',
                      'This rate is for this bill only — the product price stays the same.'),
                  key: const ValueKey('rate-sheet-bill-only'),
                  style: TextStyle(
                      color: context.c.ink2,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
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
              BigButton.brand(tr('लागू करा · Apply'), onTap: apply),
            ]),
      );
    }),
  );
}

Future<bool> askOwnerPin(
    BuildContext context, AppState app, CartLine l, double val) async {
  final pinCtrl = TextEditingController();
  final discPct = ((l.catalogRate - val) / l.catalogRate * 100).round();
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.c.surface,
          title: Text(tr('मालक PIN · Owner PIN'),
              style: baloo(
                  size: 18, weight: FontWeight.w700, color: context.c.ink)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                L('₹${l.catalogRate.round()} → ₹${val.round()} ($discPct% सूट) साठी PIN आवश्यक',
                    'PIN needed for ₹${l.catalogRate.round()} → ₹${val.round()} ($discPct% discount)'),
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
                child: Text(L('रद्द', 'Cancel'))),
            FilledButton(
                onPressed: () =>
                    Navigator.pop(ctx, app.verifyOwnerPin(pinCtrl.text)),
                child: Text(L('मंजूर', 'Approve'))),
          ],
        ),
      ) ??
      false;
}
