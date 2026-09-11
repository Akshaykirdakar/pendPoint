import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'customer_screen.dart';

class KhataScreen extends StatelessWidget {
  const KhataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final cs = [...app.customers]
      ..sort((a, b) => b.outstanding.compareTo(a.outstanding));

    return PendScaffold(
      titleMr: 'उधार खाते',
      titleEn: 'Credit / Khata',
      actions: [BarAction('＋ ग्राहक', onTap: () => _addCustomer(context, app))],
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StatTile(
            hero: true,
            label: 'एकूण उधार बाकी · Total outstanding',
            value: money(app.totalOutstanding),
            sub:
                '${cs.where((x) => x.outstanding > 0).length} customers with dues'),
        const SizedBox(height: 16),
        CardList([
          for (final cu in cs)
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CustomerScreen(customerId: cu.id))),
              child: Padding(
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
                        Text(cu.name,
                            style: baloo(
                                size: 14.5,
                                weight: FontWeight.w700,
                                color: c.ink)),
                        Text(cu.mobile,
                            style: TextStyle(fontSize: 12, color: c.ink2)),
                      ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(money(cu.outstanding),
                        style: baloo(
                            size: 15,
                            weight: FontWeight.w800,
                            color: cu.outstanding > 0 ? c.serious : c.good)),
                    Text(cu.outstanding > 0 ? 'बाकी due' : 'चुकते clear',
                        style: TextStyle(fontSize: 10.5, color: c.muted)),
                  ]),
                ]),
              ),
            ),
        ]),
      ]),
    );
  }

  void _addCustomer(BuildContext context, AppState app) {
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
                await app.saveCustomer(
                    name: nameCtrl.text.trim(), mobile: mobCtrl.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('जतन')),
        ],
      ),
    );
  }
}
