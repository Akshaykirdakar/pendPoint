import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bill.dart';
import '../../models/customer.dart';
import '../../models/enums.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'bill_screen.dart';

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
    app.payments
      ..clear()
      ..add(Payment(PayMode.cash, app.cartTotal));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final total = app.cartTotal;
    final cust = app.cartCustomerId != null
        ? app.customers.firstWhere((x) => x.id == app.cartCustomerId)
        : null;
    final paid = app.payments.fold(0.0, (s, p) => s + p.amount);

    return PendScaffold(
      titleMr: 'पेमेंट',
      titleEn: 'Checkout',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Text('देय रक्कम · Amount due',
                style: TextStyle(fontWeight: FontWeight.w600, color: c.ink2)),
            const Spacer(),
            Text(money(total),
                style:
                    baloo(size: 24, weight: FontWeight.w800, color: c.brand)),
          ]),
        ),
        SectionHeader('ग्राहक · Customer (ऐच्छिक)'),
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
                    Text('${cust.mobile} · बाकी ${money(cust.outstanding)}',
                        style: TextStyle(fontSize: 12, color: c.ink2)),
                  ])),
              IconButton(
                  onPressed: () => app.setCartCustomer(null),
                  icon: const Icon(Icons.close)),
            ]),
          )
        else
          BigButton.ghost('＋ ग्राहक निवडा · Add customer (needed for उधार)',
              onTap: () => _pickCustomer(context, app)),
        SectionHeader('पेमेंट प्रकार · Payment'),
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            for (var i = 0; i < app.payments.length; i++)
              _payRow(context, app, i),
            const SizedBox(height: 4),
            BigButton.ghost('＋ विभागून भरा · Split payment', onTap: () {
              app.addSplitPayment();
              setState(() {});
            }),
            const SizedBox(height: 11),
            Row(children: [
              Text('भरले · Entered',
                  style: TextStyle(color: c.ink2, fontSize: 13)),
              const Spacer(),
              Text('${money(paid)} / ${money(total)}',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: (paid - total).abs() < 0.5 ? c.good : c.critical)),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        BigButton.primary('✅ बिल पूर्ण करा · Finalize sale',
            onTap: () => _finalize(context, app)),
        const SizedBox(height: 10),
        Text(
            'साठा फक्त बिल पूर्ण झाल्यावरच वजा होतो · Stock is deducted only on finalize.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, fontSize: 11.5)),
      ]),
    );
  }

  Widget _payRow(BuildContext context, AppState app, int i) {
    final p = app.payments[i];
    final ctrl = TextEditingController(text: p.amount.toStringAsFixed(0));
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(children: [
        Expanded(
          child: DropdownButtonFormField<PayMode>(
            initialValue: p.mode,
            items: const [
              DropdownMenuItem(value: PayMode.cash, child: Text('रोख Cash')),
              DropdownMenuItem(value: PayMode.upi, child: Text('UPI')),
              DropdownMenuItem(
                  value: PayMode.credit, child: Text('उधार Credit')),
            ],
            onChanged: (m) {
              if (m != null) {
                app.setPayment(i, mode: m);
                setState(() {});
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(prefixText: '₹'),
            onChanged: (v) =>
                app.setPayment(i, amount: double.tryParse(v) ?? 0),
          ),
        ),
        if (app.payments.length > 1)
          IconButton(
              onPressed: () {
                app.removePayment(i);
                setState(() {});
              },
              icon: const Icon(Icons.close, size: 18)),
      ]),
    );
  }

  Future<void> _finalize(BuildContext context, AppState app) async {
    final res = await app.finalizeSale();
    if (!context.mounted) return;
    if (!res.ok) {
      showToast(context, res.error ?? 'त्रुटी');
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => BillScreen(billId: res.bill!.id)),
      (route) => route.isFirst,
    );
  }

  void _pickCustomer(BuildContext context, AppState app) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                Text('ग्राहक निवडा · Choose customer',
                    style: baloo(
                        size: 18,
                        weight: FontWeight.w700,
                        color: context.c.ink)),
                const SizedBox(height: 12),
                BigButton.ghost('＋ नवीन ग्राहक · New customer', onTap: () {
                  Navigator.pop(ctx);
                  _newCustomer(context, app);
                }),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    child: CardList([
                      for (final cu in app.customers)
                        InkWell(
                          onTap: () {
                            app.setCartCustomer(cu.id);
                            Navigator.pop(ctx);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(children: [
                              CircleAvatar(
                                  backgroundColor: context.c.surface2,
                                  child: const Text('👤')),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                    Text(cu.name,
                                        style: baloo(
                                            size: 14,
                                            weight: FontWeight.w700,
                                            color: context.c.ink)),
                                    Text(
                                        '${cu.mobile} · बाकी ${money(cu.outstanding)}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: context.c.ink2)),
                                  ])),
                            ]),
                          ),
                        ),
                    ]),
                  ),
                ),
              ]),
        ),
      ),
    );
  }

  void _newCustomer(BuildContext context, AppState app) {
    final nameCtrl = TextEditingController();
    final mobCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.c.surface,
        title: Text('नवीन ग्राहक · New customer',
            style:
                baloo(size: 17, weight: FontWeight.w700, color: context.c.ink)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'नाव · Name')),
          const SizedBox(height: 10),
          TextField(
              controller: mobCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'मोबाइल · Mobile')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
          FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final Customer c = await app.saveCustomer(
                    name: nameCtrl.text.trim(), mobile: mobCtrl.text.trim());
                app.setCartCustomer(c.id);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('जतन')),
        ],
      ),
    );
  }
}
