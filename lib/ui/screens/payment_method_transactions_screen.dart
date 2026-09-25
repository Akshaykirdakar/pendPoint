import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../state/app_state.dart';
import '../../state/report_query.dart';
import '../../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'bill_screen.dart';

/// One payment method's filtered transaction list — opened by tapping a row
/// in the dashboard's Payment Mix card or the Payment Mix screen (spec:
/// "Payment Mix — make it fully interactive"). Reads [buildTransactions]
/// itself with [mode] narrowing which bills are included, so it can never
/// disagree with the payment totals shown elsewhere for the same [filter].
class PaymentMethodTransactionsScreen extends StatelessWidget {
  final ReportFilter filter;
  final PayMode mode;
  const PaymentMethodTransactionsScreen(
      {required this.filter, required this.mode, super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rows = buildTransactions(
        bills: app.finalBills, products: app.products, filter: filter, payMode: mode);
    // The amount for this method's line is the bill's payment of that mode
    // (not the whole matched revenue) — a split-payment bill only counts the
    // portion actually paid via this method.
    double amountFor(TransactionRow row) =>
        row.bill.payments.where((p) => p.mode == mode).fold(0.0, (s, p) => s + p.amount);
    final total = rows.fold(0.0, (s, r) => s + amountFor(r));

    return PendScaffold(
      titleMr: _titleMr(mode),
      titleEn: '${_labelEn(mode)} Transactions',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: StatTile(
                  hero: true,
                  label: '${_labelMr(mode)} · ${_labelEn(mode)}',
                  value: money(total),
                  sub: '${rows.length} bills')),
        ]),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          Container(
            decoration: cardDecoration(context),
            child: const EmptyState('📭',
                'या पेमेंट पद्धतीसाठी व्यवहार सापडले नाहीत.\nNo transactions found for this payment method.'),
          )
        else ...[
          SectionHeader('व्यवहार · Transactions'),
          CardList([
            for (final row in rows)
              TransactionTile(
                bill: row.bill,
                bags: row.matchedBags,
                looseKg: row.matchedLooseKg,
                amount: amountFor(row),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BillScreen(billId: row.bill.id))),
              ),
          ]),
        ],
      ]),
    );
  }

  String _titleMr(PayMode m) => switch (m) {
        PayMode.cash => 'रोख व्यवहार',
        PayMode.upi => 'UPI व्यवहार',
        PayMode.credit => 'उधार व्यवहार',
      };
  String _labelMr(PayMode m) => switch (m) {
        PayMode.cash => 'रोख',
        PayMode.upi => 'UPI',
        PayMode.credit => 'उधार',
      };
  String _labelEn(PayMode m) => switch (m) {
        PayMode.cash => 'Cash',
        PayMode.upi => 'UPI',
        PayMode.credit => 'Credit',
      };
}
