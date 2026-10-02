import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bill.dart';
import '../../models/enums.dart';
import '../../state/app_state.dart';
import '../../state/payment_split.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/payment_editor.dart';
import '../widgets/pend_scaffold.dart';
import '../widgets/pickers.dart';
import 'bill_screen.dart';
import '../../utils/lang.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final total = app.cartTotal;
    // Mutated directly (no notify) — this runs while the route is building.
    final List<Payment> next;
    if (app.payments.length > 1) {
      // A split (e.g. an edited bill) keeps its modes and amounts; the first
      // row takes up any change in the total.
      next = PaymentSplit.fit(app.payments, total);
    } else {
      // Keep the chosen mode (an edited credit bill stays credit), at the
      // current total.
      final mode =
          app.payments.length == 1 ? app.payments.first.mode : PayMode.cash;
      next = [Payment(mode, PaymentSplit.rupees(PaymentSplit.paise(total)))];
    }
    app.payments
      ..clear()
      ..addAll(next);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final total = app.cartTotal;
    final cust = app.cartCustomerId != null
        ? app.customers.firstWhere((x) => x.id == app.cartCustomerId)
        : null;
    final excess = PaymentSplit.excess(app.payments, total);

    return PendScaffold(
      titleMr: 'पेमेंट',
      titleEn: 'Checkout',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(
              child: Text(tr('देय रक्कम · Amount due'),
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.ink2)),
            ),
            Text(money(total),
                key: const ValueKey('checkout-due'),
                style:
                    baloo(size: 24, weight: FontWeight.w800, color: c.brand)),
          ]),
        ),
        SectionHeader(tr('पार्टी (ऐच्छिक) · Party (optional)')),
        if (cust != null)
          Container(
            decoration: cardDecoration(context),
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              CircleAvatar(
                  backgroundColor: c.surface2, child: const Text('👤')),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Text(cust.name,
                        style: baloo(
                            size: 14.5, weight: FontWeight.w700, color: c.ink)),
                    Text(
                        '${cust.code.isEmpty ? '' : '${L('कोड', 'Code')} ${cust.code} · '}${cust.mobile} · ${L('बाकी', 'Due')} ${money(cust.outstanding)}',
                        style: TextStyle(fontSize: 12, color: c.ink2)),
                  ])),
              IconButton(
                  tooltip: L('पार्टी काढा', 'Remove party'),
                  onPressed: () => app.setCartCustomer(null),
                  icon: const Icon(Icons.close)),
            ]),
          )
        else
          BigButton.ghost(
              tr('🔍 पार्टी शोधा (उधारसाठी आवश्यक) · Search party (needed for credit)'),
              key: const ValueKey('checkout-party'),
              onTap: () => _pickCustomer(context, app)),
        SectionHeader(tr('पेमेंट प्रकार · Payment')),
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: const PaymentSplitEditor(),
        ),
        const SizedBox(height: 16),
        BigButton.primary(
            app.editingBillId == null
                ? tr('✅ बिल पूर्ण करा · Finalize Bill')
                : tr('✅ दुरुस्त बिल सेव्ह करा · Save corrected bill'),
            key: const ValueKey('checkout-save'),
            onTap:
                _saving || excess > 0 ? null : () => _finalize(context, app)),
        if (app.editingBillId == null) ...[
          const SizedBox(height: 10),
          // Not finished yet — keep it (payment split included) for later.
          BigButton.ghost(tr('💾 ड्राफ्ट सेव्ह करा · Save Draft'),
              key: const ValueKey('checkout-save-draft'),
              onTap: _saving ? null : () => _saveDraft(context, app)),
        ],
        const SizedBox(height: 10),
        Text(
            tr('साठा फक्त बिल पूर्ण झाल्यावरच वजा होतो · Stock is deducted only on finalize.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, fontSize: 11.5)),
      ]),
    );
  }

  bool _saving = false;

  Future<void> _finalize(BuildContext context, AppState app) async {
    setState(() => _saving = true);
    final res = await app.finalizeSale();
    if (!context.mounted) return;
    setState(() => _saving = false);
    if (!res.ok) {
      showToast(context, res.error ?? L('त्रुटी', 'Error'));
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => BillScreen(billId: res.bill!.id, justSaved: true)),
      (route) => route.isFirst,
    );
  }

  /// Keeps the bill as a draft — no stock, payment or credit is recorded —
  /// and goes back to the start, ready for the next customer.
  Future<void> _saveDraft(BuildContext context, AppState app) async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final r = await app.saveDraft();
    if (!context.mounted) return;
    setState(() => _saving = false);
    if (!r.ok) {
      showToast(context, r.error!);
      return;
    }
    showToast(
        context,
        L('✅ ड्राफ्ट सेव्ह झाला · #${r.draft!.label}',
            '✅ Draft saved · #${r.draft!.label}'));
    app.closeBill();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Searchable party picker (code / name / mobile) with "＋ New party".
  Future<void> _pickCustomer(BuildContext context, AppState app) async {
    final party = await pickParty(context, app, purchase: false);
    if (party != null) app.setCartCustomer(party.id);
  }
}
