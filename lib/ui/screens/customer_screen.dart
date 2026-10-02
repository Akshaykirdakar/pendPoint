import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/customer.dart';
import '../../models/enums.dart';
import '../../services/reminder_service.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../../utils/lang.dart';

class CustomerScreen extends StatelessWidget {
  final String customerId;
  const CustomerScreen({required this.customerId, super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final cu = app.customers.firstWhere((x) => x.id == customerId);
    final led = [...cu.ledger]..sort((a, b) => b.at.compareTo(a.at));

    return PendScaffold(
      titleMr: 'ग्राहक',
      titleEn: 'Customer',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          child: Column(children: [
            CircleAvatar(
                radius: 28,
                backgroundColor: c.surface2,
                child: const Text('👤', style: TextStyle(fontSize: 26))),
            const SizedBox(height: 8),
            Text(cu.name,
                style: baloo(size: 18, weight: FontWeight.w700, color: c.ink)),
            Text(cu.mobile, style: TextStyle(color: c.muted)),
            const SizedBox(height: 10),
            Text(money(cu.outstanding),
                style: baloo(
                    size: 30,
                    weight: FontWeight.w800,
                    color: cu.outstanding > 0 ? c.serious : c.good)),
            Text(
                cu.outstanding > 0
                    ? tr('येणे बाकी · Outstanding')
                    : tr('खाते चुकते · Settled'),
                style: TextStyle(fontSize: 12, color: c.muted)),
            if (cu.outstanding > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                  width: 220,
                  child: BigButton.brand(tr('💵 पैसे जमा करा · Record payment'),
                      onTap: () => _repay(context, app, customerId))),
              const SizedBox(height: 12),
              // 🔔 Remind this customer of the due amount.
              Row(children: [
                Expanded(
                  child: BigButton.ghost('🟢 WhatsApp',
                      key: const ValueKey('customer-remind-whatsapp'),
                      onTap: () => _remind(context, app, cu,
                          ReminderChannel.whatsApp)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BigButton.ghost('💬 SMS',
                      key: const ValueKey('customer-remind-sms'),
                      onTap: () =>
                          _remind(context, app, cu, ReminderChannel.sms)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(tr('🔔 बाकीची आठवण पाठवा · Send a payment reminder'),
                  style: TextStyle(fontSize: 11.5, color: c.muted)),
            ],
          ]),
        ),
        SectionHeader(tr('व्यवहार · Ledger')),
        CardList([
          for (final e in led)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: (e.isRepayment ? c.good : c.serious)
                            .withValues(alpha: 0.15),
                        shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Icon(e.isRepayment ? Icons.south : Icons.north,
                        size: 18, color: e.isRepayment ? c.good : c.serious)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      Text(
                          e.isRepayment
                              ? tr('जमा · Payment')
                              : tr('उधार · Credit sale'),
                          style: baloo(
                              size: 13.5,
                              weight: FontWeight.w700,
                              color: c.ink)),
                      Text([dateTimeShort(e.at), if (e.note != null && e.note!.isNotEmpty) noteLabel(e.note!)].join(' · '),
                          style: TextStyle(fontSize: 11.5, color: c.ink2)),
                    ])),
                Text('${e.isRepayment ? '–' : '+'}${money(e.amount)}',
                    style: baloo(
                        size: 14,
                        weight: FontWeight.w800,
                        color: e.isRepayment ? c.good : c.serious)),
              ]),
            ),
        ]),
      ]),
    );
  }

  /// Opens WhatsApp / SMS with a reminder of [cu]'s due amount — the
  /// shopkeeper presses Send. Says so when there's no mobile number.
  Future<void> _remind(BuildContext context, AppState app, Customer cu,
      ReminderChannel channel) async {
    if (!ReminderService.hasValidMobile(cu.mobile)) {
      showToast(context,
          tr('ग्राहकाचा मोबाइल नंबर उपलब्ध नाही · Customer mobile number is not available.'));
      return;
    }
    final ok = await ReminderService.open(
        channel,
        cu.mobile,
        ReminderService.message(
            shopName: app.settings.shop,
            customerName: cu.name,
            due: cu.outstanding));
    if (!ok && context.mounted) {
      showToast(
          context,
          channel == ReminderChannel.whatsApp
              ? tr('WhatsApp उघडता आले नाही · Could not open WhatsApp')
              : tr('SMS उघडता आले नाही · Could not open SMS'));
    }
  }

  void _repay(BuildContext context, AppState app, String id) {
    final cu = app.customers.firstWhere((x) => x.id == id);
    final amtCtrl =
        TextEditingController(text: cu.outstanding.toStringAsFixed(0));
    PayMode mode = PayMode.cash;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.c.surface,
        title: Text(tr('पैसे जमा · Record payment'),
            style:
                baloo(size: 17, weight: FontWeight.w700, color: context.c.ink)),
        content: StatefulBuilder(
            builder: (ctx, setSt) =>
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${cu.name} — बाकी ${money(cu.outstanding)}',
                      style: TextStyle(fontSize: 12.5, color: context.c.ink2)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: amtCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: tr('रक्कम · Amount'), prefixText: '₹')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<PayMode>(
                      isExpanded: true,
                      initialValue: mode,
                      items: [
                        DropdownMenuItem(
                            value: PayMode.cash, child: Text(tr('रोख · Cash'))),
                        DropdownMenuItem(value: PayMode.upi, child: Text('UPI'))
                      ],
                      onChanged: (m) => setSt(() => mode = m ?? mode)),
                ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
          FilledButton(
              onPressed: () async {
                final amt = double.tryParse(amtCtrl.text) ?? 0;
                if (amt <= 0) return;
                await app.recordRepayment(id, amt, mode);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (context.mounted) {
                  showToast(context, tr('₹${amt.round()} जमा झाले · Recorded'));
                }
              },
              child: const Text('जमा')),
        ],
      ),
    );
  }
}
