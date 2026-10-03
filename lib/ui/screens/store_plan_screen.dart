import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/platform.dart';
import '../../models/store.dart';
import '../../state/app_state.dart';
import '../../state/platform_service.dart' show ddmmyyyy;
import '../../utils/formatters.dart';
import '../../utils/lang.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

String planStatusLabel(String s) => switch (s) {
      PlanStatus.trial => L('ट्रायल', 'Trial'),
      PlanStatus.active => L('सुरू', 'Active'),
      PlanStatus.expiring => L('मुदत संपत आहे', 'Expiring'),
      PlanStatus.expired => L('मुदत संपली', 'Expired'),
      PlanStatus.suspended => L('स्थगित', 'Suspended'),
      _ => L('प्लॅन नाही', 'No plan'),
    };

/// 💳 Super Admin → a store's plan: current plan, change plan / extend
/// expiry, record a payment or renewal, payment history. Live from the
/// store document.
class StorePlanScreen extends StatefulWidget {
  final String storeId;
  const StorePlanScreen({required this.storeId, super.key});
  @override
  State<StorePlanScreen> createState() => _StorePlanScreenState();
}

class _StorePlanScreenState extends State<StorePlanScreen> {
  late final Stream<Store?> _store =
      context.read<AppState>().repo.platform.watchStore(widget.storeId);
  late Future<List<StorePayment>> _payments;
  late Future<List<Plan>> _plans;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final p = context.read<AppState>().platform;
    setState(() {
      _payments = p.payments(widget.storeId);
      _plans = p.plans();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PendScaffold(
      titleMr: 'प्लॅन व पेमेंट',
      titleEn: 'Plan & payments',
      body: StreamBuilder<Store?>(
        stream: _store,
        builder: (context, snap) {
          final st = snap.data;
          if (st == null) {
            return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()));
          }
          final now = DateTime.now();
          final status = st.planStatusAt(now);
          String d(DateTime? x) => x == null ? '—' : ddmmyyyy(x);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              decoration: cardDecoration(context),
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${st.storeName} · ${st.id}',
                    key: const ValueKey('plan-store-name'),
                    style: baloo(size: 17, weight: FontWeight.w800, color: c.ink)),
                const SizedBox(height: 6),
                Text('${L('प्लॅन', 'Plan')}: ${st.planName ?? '—'} · ${planStatusLabel(status)}',
                    key: const ValueKey('plan-status')),
                Text('${L('सुरुवात', 'Started')}: ${d(st.planStartDate)} · ${L('मुदत', 'Expires')}: ${d(st.planExpiryDate)}'),
                Text('${L('नूतनीकरण रक्कम', 'Renewal amount')}: ${st.renewalAmount == null ? '—' : money(st.renewalAmount!)}'),
                Text('${L('पेमेंट', 'Payment')}: ${st.paymentStatus ?? '—'} · ${L('शेवटचे', 'last')} ${d(st.lastPaymentDate)} · ${L('पुढचे', 'next')} ${d(st.nextPaymentDate)}'),
                if (st.gracePeriodUntil != null)
                  Text('${L('जास्तीची मुदत', 'Grace until')}: ${d(st.gracePeriodUntil)}'),
                if (st.ownerName.isNotEmpty || st.ownerPhone.isNotEmpty)
                  Text('${L('मालक', 'Owner')}: ${st.ownerName} ${st.ownerPhone}',
                      style: TextStyle(color: c.ink2)),
              ]),
            ),
            const SizedBox(height: 12),
            BigButton.primary(tr('💰 पेमेंट / नूतनीकरण नोंदवा · Record payment / renewal'),
                key: const ValueKey('plan-record-payment'),
                onTap: () => _recordPayment(st)),
            const SizedBox(height: 8),
            BigButton.ghost(tr('✏️ प्लॅन बदला · Change plan / expiry'),
                key: const ValueKey('plan-change'),
                onTap: () => _changePlan(st)),
            SectionHeader(tr('पेमेंट इतिहास · Payment history')),
            FutureBuilder<List<StorePayment>>(
              future: _payments,
              builder: (context, ps) {
                if (ps.hasError) return EmptyState('⚠️', '${ps.error}');
                final list = ps.data;
                if (list == null) return const Center(child: CircularProgressIndicator());
                if (list.isEmpty) return EmptyState('💳', tr('अजून पेमेंट नाही · No payments yet'));
                return CardList([
                  for (final p in list)
                    ListTile(
                      key: ValueKey('payment-${p.id}'),
                      title: Text('${money(p.amount)} · ${p.status}'),
                      subtitle: Text(
                          '${ddmmyyyy(p.paymentDate)}${p.method.isEmpty ? '' : ' · ${p.method}'}${p.transactionId.isEmpty ? '' : ' · ${p.transactionId}'}'
                          '${p.periodEnd == null ? '' : '\n${L('पर्यंत', 'until')} ${ddmmyyyy(p.periodEnd!)}'}${p.notes.isEmpty ? '' : '\n${p.notes}'}'),
                    ),
                ]);
              },
            ),
          ]);
        },
      ),
    );
  }

  Future<void> _recordPayment(Store st) async {
    final app = context.read<AppState>();
    final plans = await _plans.catchError((_) => <Plan>[]);
    if (!mounted) return;
    final amount = TextEditingController(
        text: st.renewalAmount == null ? '' : st.renewalAmount!.round().toString());
    final method = TextEditingController();
    final txn = TextEditingController();
    final notes = TextEditingController();
    var status = PaymentStatus.paid;
    var renew = true;
    Plan? plan = plans.where((p) => p.id == st.planId).firstOrNull;
    String? error;
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(tr('पेमेंट नोंदवा · Record payment')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  key: const ValueKey('pay-amount'),
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: L('रक्कम ₹', 'Amount ₹'))),
              DropdownButtonFormField<String>(
                key: const ValueKey('pay-status'),
                isExpanded: true,
                initialValue: status,
                decoration: InputDecoration(labelText: L('स्थिती', 'Status')),
                items: [
                  for (final s in PaymentStatus.all)
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (v) => setSt(() => status = v ?? status),
              ),
              if (plans.isNotEmpty)
                DropdownButtonFormField<String?>(
                  key: const ValueKey('pay-plan'),
                  isExpanded: true,
                  initialValue: plan?.id,
                  decoration: InputDecoration(labelText: L('प्लॅन', 'Plan')),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(L('डीफॉल्ट', 'Default'))),
                    for (final p in plans)
                      DropdownMenuItem<String?>(
                          value: p.id, child: Text('${p.name} · ${money(p.price)} · ${p.durationDays}d')),
                  ],
                  onChanged: (v) => setSt(() {
                    plan = plans.where((p) => p.id == v).firstOrNull;
                    if (plan != null) amount.text = plan!.price.round().toString();
                  }),
                ),
              TextField(
                  key: const ValueKey('pay-method'),
                  controller: method,
                  decoration: InputDecoration(labelText: L('पद्धत (UPI / रोख / बँक)', 'Method (UPI / cash / bank)'))),
              TextField(
                  key: const ValueKey('pay-txn'),
                  controller: txn,
                  decoration: InputDecoration(labelText: L('व्यवहार क्रमांक', 'Transaction ID'))),
              TextField(
                  key: const ValueKey('pay-notes'),
                  controller: notes,
                  decoration: InputDecoration(labelText: L('टीप', 'Notes'))),
              if (status == PaymentStatus.paid)
                CheckboxListTile(
                  key: const ValueKey('pay-renew'),
                  contentPadding: EdgeInsets.zero,
                  value: renew,
                  title: Text(tr('प्लॅनची मुदत वाढवा · Renew / extend the plan')),
                  onChanged: (v) => setSt(() => renew = v ?? true),
                ),
              if (error != null)
                Text(error!, style: TextStyle(color: ctx.c.critical)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L('रद्द', 'Cancel'))),
            FilledButton(
                key: const ValueKey('pay-save'),
                onPressed: () async {
                  final e = await app.platform.recordPayment(st,
                      amount: double.tryParse(amount.text.trim()) ?? 0,
                      status: status,
                      method: method.text,
                      transactionId: txn.text,
                      plan: plan,
                      renew: renew,
                      notes: notes.text);
                  if (e != null) {
                    setSt(() => error = e);
                  } else if (ctx.mounted) {
                    Navigator.pop(ctx, true);
                  }
                },
                child: Text(L('नोंदवा', 'Record'))),
          ],
        ),
      ),
    );
    if (done == true && mounted) {
      showToast(context, tr('✅ नोंदवले · Recorded'));
      _reload();
    }
  }

  Future<void> _changePlan(Store st) async {
    final app = context.read<AppState>();
    final plans = await _plans.catchError((_) => <Plan>[]);
    if (!mounted) return;
    Plan? plan = plans.where((p) => p.id == st.planId).firstOrNull;
    var status = PlanStatus.settable.contains(st.planStatus) ? st.planStatus! : PlanStatus.active;
    DateTime? expiry = st.planExpiryDate;
    final notes = TextEditingController();
    String? error;
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(tr('प्लॅन बदला · Change plan')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String?>(
                key: const ValueKey('cp-plan'),
                isExpanded: true,
                initialValue: plan?.id,
                decoration: InputDecoration(labelText: L('प्लॅन', 'Plan')),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(L('बदल नाही', 'No change'))),
                  for (final p in plans)
                    DropdownMenuItem<String?>(value: p.id, child: Text('${p.name} · ${money(p.price)}')),
                ],
                onChanged: (v) => setSt(() => plan = plans.where((p) => p.id == v).firstOrNull),
              ),
              DropdownButtonFormField<String>(
                key: const ValueKey('cp-status'),
                isExpanded: true,
                initialValue: status,
                decoration: InputDecoration(labelText: L('स्थिती', 'Status')),
                items: [
                  for (final s in PlanStatus.settable)
                    DropdownMenuItem(value: s, child: Text(planStatusLabel(s))),
                ],
                onChanged: (v) => setSt(() => status = v ?? status),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey('cp-expiry'),
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime(now.year - 2),
                      lastDate: DateTime(now.year + 10),
                      initialDate: expiry ?? now.add(const Duration(days: 365)));
                  if (d != null) setSt(() => expiry = d);
                },
                child: Text('${L('मुदत', 'Expiry')}: ${expiry == null ? '—' : ddmmyyyy(expiry!)}'),
              ),
              TextField(
                  key: const ValueKey('cp-notes'),
                  controller: notes,
                  decoration: InputDecoration(labelText: L('नूतनीकरण टीप', 'Renewal notes'))),
              if (error != null) Text(error!, style: TextStyle(color: ctx.c.critical)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L('रद्द', 'Cancel'))),
            FilledButton(
                key: const ValueKey('cp-save'),
                onPressed: () async {
                  final e = await app.platform.changePlan(st,
                      plan: plan,
                      planStatus: status,
                      expiry: expiry != st.planExpiryDate ? expiry : null,
                      notes: notes.text);
                  if (e != null) {
                    setSt(() => error = e);
                  } else if (ctx.mounted) {
                    Navigator.pop(ctx, true);
                  }
                },
                child: Text(L('जतन', 'Save'))),
          ],
        ),
      ),
    );
    if (done == true && mounted) showToast(context, tr('✅ जतन झाले · Saved'));
  }
}

/// 📋 Super Admin → Plans (name, days, price).
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  late Future<List<Plan>> _plans;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final next = context.read<AppState>().platform.plans();
    setState(() {
      _plans = next;
    });
  }

  @override
  Widget build(BuildContext context) => PendScaffold(
        titleMr: 'प्लॅन',
        titleEn: 'Plans',
        actions: [
          BarAction('＋ प्लॅन · Plan',
              key: const ValueKey('plan-add'), onTap: () => _edit(null)),
        ],
        body: FutureBuilder<List<Plan>>(
          future: _plans,
          builder: (context, snap) {
            if (snap.hasError) return EmptyState('⚠️', '${snap.error}');
            final list = snap.data;
            if (list == null) return const Center(child: CircularProgressIndicator());
            if (list.isEmpty) return EmptyState('📋', tr('अजून प्लॅन नाही · No plans yet'));
            return CardList([
              for (final p in list)
                ListTile(
                  key: ValueKey('plan-${p.id}'),
                  title: Text('${p.name}${p.active ? '' : ' (${L('बंद', 'inactive')})'}'),
                  subtitle: Text('${money(p.price)} · ${p.durationDays} ${L('दिवस', 'days')}'),
                  trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(p)),
                ),
            ]);
          },
        ),
      );

  Future<void> _edit(Plan? old) async {
    final app = context.read<AppState>();
    final name = TextEditingController(text: old?.name ?? '');
    final days = TextEditingController(text: '${old?.durationDays ?? 365}');
    final price = TextEditingController(text: old == null ? '' : old.price.round().toString());
    var active = old?.active ?? true;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(old == null ? tr('नवीन प्लॅन · New plan') : tr('प्लॅन बदला · Edit plan')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const ValueKey('plan-name'), controller: name,
                decoration: InputDecoration(labelText: L('नाव', 'Name'))),
            TextField(key: const ValueKey('plan-days'), controller: days,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: L('दिवस', 'Duration (days)'))),
            TextField(key: const ValueKey('plan-price'), controller: price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: L('किंमत ₹', 'Price ₹'))),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: active,
                title: Text(L('सुरू', 'Active')),
                onChanged: (v) => setSt(() => active = v)),
            if (error != null) Text(error!, style: TextStyle(color: ctx.c.critical)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L('रद्द', 'Cancel'))),
            FilledButton(
                key: const ValueKey('plan-save'),
                onPressed: () async {
                  final e = await app.platform.savePlan(Plan(
                      id: old?.id ?? app.platform.newId(),
                      name: name.text.trim(),
                      durationDays: int.tryParse(days.text.trim()) ?? 0,
                      price: double.tryParse(price.text.trim()) ?? -1,
                      active: active));
                  if (e != null) {
                    setSt(() => error = e);
                  } else if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                },
                child: Text(L('जतन', 'Save'))),
          ],
        ),
      ),
    );
    if (mounted) _reload();
  }
}

/// "12 days left" / "expired 3 days ago" for a store's plan.
String daysLeftText(Store st, DateTime now) {
  final d = st.daysToExpiry(now);
  if (d == null) return '';
  if (d < 0) return L('${-d} दिवसांपूर्वी संपला', 'expired ${-d} days ago');
  if (d == 0) return L('आज संपतो', 'expires today');
  return L('$d दिवस बाकी', '$d days left');
}
