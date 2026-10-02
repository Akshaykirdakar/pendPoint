import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/bill.dart';
import '../../models/enums.dart';
import '../../state/app_state.dart';
import '../../state/payment_split.dart';
import '../../utils/formatters.dart';
import '../../utils/lang.dart';
import '../../utils/theme.dart';
import 'common.dart';

/// Split payment rows for the bill on screen (e.g. cash + credit): mode and
/// amount per row, "+ Split payment", what's entered against the total and
/// a Full / Remaining / Over line. Rows auto-balance so the total is never
/// exceeded (see [PaymentSplit]). Shared by Checkout and the sale screen.
class PaymentSplitEditor extends StatefulWidget {
  const PaymentSplitEditor({super.key});
  @override
  State<PaymentSplitEditor> createState() => _PaymentSplitEditorState();
}

class _PaymentSplitEditorState extends State<PaymentSplitEditor> {
  // One field per payment row, kept across rebuilds so typing is never
  // interrupted; rows the user is NOT typing in follow the auto-balance.
  final List<TextEditingController> _amount = [];
  final List<FocusNode> _focus = [];

  @override
  void dispose() {
    for (final c in _amount) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
  }

  static String _fmt(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// Grows/shrinks the field list to the row count and copies each row's
  /// amount into its field unless the user is typing there.
  void _syncFields(List<Payment> pays) {
    while (_amount.length < pays.length) {
      _amount.add(TextEditingController());
      _focus.add(FocusNode());
    }
    while (_amount.length > pays.length) {
      // The removed row's field is still mounted during this build —
      // dispose its controller only after the frame.
      final ctrl = _amount.removeLast(), focus = _focus.removeLast();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ctrl.dispose();
        focus.dispose();
      });
    }
    for (var i = 0; i < pays.length; i++) {
      if (_focus[i].hasFocus) continue;
      final shown = double.tryParse(_amount[i].text);
      if (shown == null ||
          PaymentSplit.paise(shown) != PaymentSplit.paise(pays[i].amount)) {
        _amount[i].text = _fmt(pays[i].amount);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final total = app.cartTotal;
    final pays = app.payments;
    _syncFields(pays);
    final entered = PaymentSplit.entered(pays);
    final excess = PaymentSplit.excess(pays, total);
    final complete = PaymentSplit.isComplete(pays, total);
    final canAdd = PaymentSplit.freeModes(pays).isNotEmpty;

    return Column(children: [
      for (var i = 0; i < pays.length; i++) _payRow(context, app, i),
      const SizedBox(height: 4),
      BigButton.ghost(tr('＋ विभागून भरा · Split payment'),
          key: const ValueKey('pay-add'),
          onTap: canAdd ? app.addSplitPayment : null),
      Divider(height: 22, color: c.line),
      Row(children: [
        Expanded(
          child: Text(tr('भरले · Entered'),
              style: TextStyle(color: c.ink2, fontSize: 13)),
        ),
        Text('${money(entered)} / ${money(total)}',
            key: const ValueKey('pay-entered'),
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: complete ? c.good : c.critical)),
      ]),
      const SizedBox(height: 6),
      _status(context, pays, total, complete, excess),
    ]);
  }

  /// Full / remaining / over — one clear line under the payment rows.
  Widget _status(BuildContext context, List<Payment> pays, double total,
      bool complete, double excess) {
    final c = context.c;
    final (String text, Color color) = complete
        ? ('✅ ${L('पूर्ण रक्कम', 'Full Amount')}', c.good)
        : excess > 0
            ? (
                '❌ ${L('पेमेंट रक्कम बिलाच्या रकमेपेक्षा जास्त आहे.', 'Payment amount cannot exceed the bill total.')}',
                c.critical
              )
            : (
                '${L('बाकी', 'Remaining')} ${money(PaymentSplit.remaining(pays, total))}',
                c.warning
              );
    return Container(
      key: const ValueKey('pay-status'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10)),
      child: Text(text,
          style: TextStyle(fontWeight: FontWeight.w800, color: c.ink)),
    );
  }

  Widget _payRow(BuildContext context, AppState app, int i) {
    final p = app.payments[i];
    final modes = PaymentSplit.freeModes(app.payments, exceptIndex: i);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(children: [
        Expanded(
          child: DropdownButtonFormField<PayMode>(
            key: ValueKey('pay-row-$i-mode-${p.mode.name}'),
            isExpanded: true,
            initialValue: p.mode,
            items: [
              for (final m in modes)
                DropdownMenuItem(value: m, child: Text(payModeLabel(m))),
            ],
            onChanged: (m) {
              if (m != null) app.setPayment(i, mode: m);
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 112,
          child: TextField(
            key: ValueKey('pay-row-$i-amount'),
            controller: _amount[i],
            focusNode: _focus[i],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: const InputDecoration(prefixText: '₹'),
            onChanged: (v) {
              final typed = double.tryParse(v) ?? 0;
              app.setPayment(i, amount: typed);
              // Capped at the bill total — show the capped amount at once.
              final kept = app.payments[i].amount;
              if (PaymentSplit.paise(kept) != PaymentSplit.paise(typed)) {
                final t = _fmt(kept);
                _amount[i].value = TextEditingValue(
                    text: t,
                    selection: TextSelection.collapsed(offset: t.length));
              }
            },
          ),
        ),
        if (app.payments.length > 1)
          IconButton(
              key: ValueKey('pay-row-$i-remove'),
              tooltip: L('हा प्रकार काढा', 'Remove this payment'),
              onPressed: () {
                FocusScope.of(context).unfocus();
                app.removePayment(i);
              },
              icon: const Icon(Icons.close, size: 18)),
      ]),
    );
  }
}
