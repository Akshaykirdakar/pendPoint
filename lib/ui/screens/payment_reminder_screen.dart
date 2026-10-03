import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/customer.dart';
import '../../services/reminder_service.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/lang.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

/// 🔔 Payment reminder — pick customers who owe money (one, several or
/// "select all"), choose WhatsApp or SMS, and send. A phone can't send
/// these in the background, so they go one at a time: WhatsApp/SMS opens
/// with the message ready, the shopkeeper presses Send, comes back and
/// taps "Next customer".
class PaymentReminderScreen extends StatefulWidget {
  const PaymentReminderScreen({super.key});
  @override
  State<PaymentReminderScreen> createState() => _PaymentReminderScreenState();
}

class _PaymentReminderScreenState extends State<PaymentReminderScreen> {
  ReminderChannel _channel = ReminderChannel.whatsApp;
  final Set<String> _selected = {};
  final Set<String> _sent = {};

  // While sending: the customers in order, and which one is open now.
  List<Customer> _queue = const [];
  int _at = -1;
  bool get _sending => _queue.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final due = app.customers.where((x) => x.outstanding > 0).toList()
      ..sort((a, b) => b.outstanding.compareTo(a.outstanding));
    final reachable =
        due.where((x) => ReminderService.hasValidMobile(x.mobile)).toList();
    _selected.removeWhere((id) => !reachable.any((x) => x.id == id));
    final allOn = reachable.isNotEmpty && _selected.length == reachable.length;
    final preview = due.where((x) => _selected.contains(x.id)).firstOrNull ??
        reachable.firstOrNull;

    return PendScaffold(
      titleMr: 'उधार आठवण',
      titleEn: 'Payment reminder',
      bottomBar: due.isEmpty ? null : _bottomBar(context, app, due),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            L('उधार बाकी असलेल्या ग्राहकांना WhatsApp किंवा SMS ने आठवण पाठवा.',
                'Remind customers who owe you, by WhatsApp or SMS.'),
            style: TextStyle(color: c.ink2, fontSize: 12.5)),
        const SizedBox(height: 12),
        if (due.isEmpty)
          Container(
              decoration: cardDecoration(context),
              child: EmptyState(
                  '🎉', tr('कोणाचीही उधार बाकी नाही · No one owes you money')))
        else ...[
          Row(children: [
            _channelButton(context, ReminderChannel.whatsApp, '🟢', 'WhatsApp'),
            const SizedBox(width: 10),
            _channelButton(context, ReminderChannel.sms, '💬', 'SMS'),
          ]),
          const SizedBox(height: 12),
          Material(
            key: const ValueKey('remind-select-all'),
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            child: CheckboxListTile(
              value: allOn,
              onChanged: _sending || reachable.isEmpty
                  ? null
                  : (on) => setState(() {
                        _selected.clear();
                        if (on == true) {
                          _selected.addAll(reachable.map((x) => x.id));
                        }
                      }),
              title: Text(
                  '${tr('सर्व निवडा · Select all')} (${reachable.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                  '${L('एकूण बाकी', 'Total due')} ${money(due.fold(0.0, (s, x) => s + x.outstanding))}',
                  style: TextStyle(fontSize: 12, color: c.ink2)),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
          const SizedBox(height: 8),
          CardList([for (final cu in due) _row(context, cu)]),
          if (preview != null) ...[
            SectionHeader(tr('संदेश · Message')),
            Container(
              key: const ValueKey('remind-preview'),
              decoration: cardDecoration(context, color: c.surface2),
              padding: const EdgeInsets.all(12),
              child: Text(_message(app, preview),
                  style: TextStyle(fontSize: 12.5, color: c.ink)),
            ),
          ],
          const SizedBox(height: 10),
          Text(
              L('प्रत्येक ग्राहकासाठी WhatsApp / SMS संदेश तयार होऊन उघडेल — "पाठवा" तुम्हीच दाबायचे आहे.',
                  'WhatsApp / SMS opens for each customer with the message ready — you press Send.'),
              style: TextStyle(fontSize: 11.5, color: c.muted)),
        ],
      ]),
    );
  }

  String _message(AppState app, Customer cu) => ReminderService.message(
      shopName: app.shopName, customerName: cu.name, due: cu.outstanding);

  Widget _channelButton(
      BuildContext context, ReminderChannel ch, String emoji, String label) {
    final c = context.c;
    final on = _channel == ch;
    return Expanded(
      child: Material(
        key: ValueKey('remind-${ch.name}'),
        color: on ? c.brand : c.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _sending ? null : () => setState(() => _channel = ch),
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: on ? c.brand : c.line, width: on ? 2 : 1.2)),
            child: Text('$emoji $label',
                style: baloo(
                    size: 16,
                    weight: FontWeight.w800,
                    color: on ? c.brandInk : c.ink)),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Customer cu) {
    final c = context.c;
    final ok = ReminderService.hasValidMobile(cu.mobile);
    final sent = _sent.contains(cu.id);
    final current = _sending && _queue[_at].id == cu.id;
    // Its own Material, so the tap ripple shows inside the card.
    return Material(
        type: MaterialType.transparency,
        child: CheckboxListTile(
          key: ValueKey('remind-row-${cu.id}'),
          value: _selected.contains(cu.id),
          onChanged: !ok || _sending
              ? null
              : (on) => setState(() =>
                  on == true ? _selected.add(cu.id) : _selected.remove(cu.id)),
          controlAffinity: ListTileControlAffinity.leading,
          tileColor: current ? c.brand.withValues(alpha: 0.10) : null,
          title: Text(cu.name,
              style: baloo(size: 14.5, weight: FontWeight.w700, color: c.ink)),
          subtitle: Text(
              ok
                  ? '${cu.mobile}${sent ? '  ·  ✓ ${L('पाठवण्यासाठी उघडले', 'Opened to send')}' : ''}'
                  : tr('⚠️ मोबाइल नंबर नाही · No mobile number'),
              style: TextStyle(
                  fontSize: 12,
                  color: ok ? (sent ? c.good : c.ink2) : c.critical,
                  fontWeight: sent || !ok ? FontWeight.w700 : FontWeight.w400)),
          secondary: Text(money(cu.outstanding),
              style:
                  baloo(size: 15, weight: FontWeight.w800, color: c.serious)),
        ));
  }

  Widget _bottomBar(BuildContext context, AppState app, List<Customer> due) {
    final c = context.c;
    if (!_sending) {
      final n = _selected.length;
      return BigButton.primary(
          n == 0
              ? tr('🔔 ग्राहक निवडा · Select customers')
              : '🔔 ${L('आठवण पाठवा', 'Send reminder')} ($n)',
          key: const ValueKey('remind-send'),
          onTap: n == 0
              ? null
              : () {
                  setState(() {
                    _queue = [
                      for (final cu in due)
                        if (_selected.contains(cu.id)) cu
                    ];
                    _at = 0;
                  });
                  _openCurrent(app);
                });
    }
    final last = _at == _queue.length - 1;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('${_at + 1} / ${_queue.length} · ${_queue[_at].name}',
          key: const ValueKey('remind-progress'),
          textAlign: TextAlign.center,
          style: baloo(size: 15, weight: FontWeight.w800, color: c.ink)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: BigButton.ghost(tr('⏹ थांबा · Stop'),
              key: const ValueKey('remind-stop'), onTap: _finish),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: last
              ? BigButton.primary(tr('✅ पूर्ण · Done'),
                  key: const ValueKey('remind-done'), onTap: _finish)
              : BigButton.primary(tr('▶ पुढील ग्राहक · Next customer'),
                  key: const ValueKey('remind-next'), onTap: () {
                  setState(() => _at++);
                  _openCurrent(app);
                }),
        ),
      ]),
    ]);
  }

  Future<void> _openCurrent(AppState app) async {
    final cu = _queue[_at];
    final ok =
        await ReminderService.open(_channel, cu.mobile, _message(app, cu));
    if (!mounted) return;
    if (ok) {
      setState(() => _sent.add(cu.id));
    } else {
      showToast(
          context,
          _channel == ReminderChannel.whatsApp
              ? tr('WhatsApp उघडता आले नाही · Could not open WhatsApp')
              : tr('SMS उघडता आले नाही · Could not open SMS'));
    }
  }

  void _finish() {
    final opened = _queue.where((x) => _sent.contains(x.id)).length;
    setState(() {
      _queue = const [];
      _at = -1;
      _selected.clear();
    });
    showToast(
        context,
        L('✅ $opened आठवणी पाठवण्यासाठी उघडल्या',
            '✅ $opened reminders opened to send'));
  }
}
