import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bill.dart';
import '../../models/enums.dart';
import '../../models/party.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'bill_screen.dart';
import 'draft_bills_screen.dart';
import 'sales_entry_screen.dart';
import '../../utils/lang.dart';

/// Bills — 📝 drafts (unfinished, no effect yet) first, then ✅ final
/// bills: search by bill no. or party (code / name / mobile), open, edit,
/// partially return or void. Final bills are never deleted: void and edit
/// keep the original, marked, for the audit trail.
class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});
  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final q = _search.text.trim().toLowerCase().replaceAll('#', '');
    final bills = app.bills.where((b) {
      if (q.isEmpty) return true;
      if ('${b.billNumber}' == q) return true;
      if (b.customerName.toLowerCase().contains(q)) return true;
      final party = b.customerId == null ? null : app.partyOf(b.customerId!);
      return party != null && partyMatchRank(party, q) != null;
    }).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    final recent = bills.take(q.isEmpty ? 30 : 100).toList();
    final drafts = app.draftsNewestFirst.where((d) {
      if (q.isEmpty) return true;
      if (d.label.toLowerCase() == q || '${d.number}' == q) return true;
      final party = d.customerId == null ? null : app.partyOf(d.customerId!);
      return (party?.name ?? d.customerName).toLowerCase().contains(q);
    }).toList();

    return PendScaffold(
      titleMr: 'बिले',
      titleEn: 'Bills',
      actions: [
        // Always a fresh, empty bill (the same as Home → New Sale Bill).
        BarAction('＋ नवीन बिल · New Bill',
            key: const ValueKey('bills-new-bill'),
            onTap: () => openNewBill(context)),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          key: const ValueKey('bills-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              hintText: tr('बिल क्र. किंवा पार्टी · Bill no. or party')),
        ),
        const SizedBox(height: 8),
        Text(
            tr('बिल दुरुस्त/रद्द केल्यास साठा आपोआप दुरुस्त होतो. बिले कधीही हटवली जात नाहीत · Editing or voiding fixes stock automatically. Bills are kept (marked), never deleted.'),
            style: TextStyle(color: c.ink2, fontSize: 12)),
        SectionHeader(
            '📝 ${L('ड्राफ्ट बिले', 'Draft Bills')} (${drafts.length})',
            action: TextButton(
                key: const ValueKey('bills-all-drafts'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const DraftBillsScreen())),
                child: Text(L('सर्व', 'All')))),
        if (drafts.isEmpty)
          Text(tr('ड्राफ्ट बिले नाहीत · No draft bills'),
              style: TextStyle(color: c.muted, fontSize: 12.5))
        else
          for (final d in drafts.take(q.isEmpty ? 5 : 20)) ...[
            DraftCard(d),
            const SizedBox(height: 10),
          ],
        SectionHeader('✅ ${L('पूर्ण बिले', 'Final Bills')}'),
        if (app.historyLoading && app.bills.isEmpty)
          const HistoryLoadingNote()
        else if (recent.isEmpty)
          EmptyState('🧾', tr('बिल सापडले नाही · No bill found'))
        else
          CardList([
            for (final b in recent)
              InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BillScreen(billId: b.id))),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          CircleAvatar(
                              backgroundColor: c.surface2,
                              child: const Text('🧾')),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                Wrap(
                                    spacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                          '#${b.billNumber}${b.isRevised ? ' R${b.revision}' : ''}',
                                          style: baloo(
                                              size: 15,
                                              weight: FontWeight.w800,
                                              color: c.ink)),
                                      if (b.status == BillStatus.voided)
                                        Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                                color: c.critical
                                                    .withValues(alpha: 0.14),
                                                borderRadius:
                                                    BorderRadius.circular(999)),
                                            child: Text(
                                                b.wasReplaced
                                                    ? tr('दुरुस्त · Edited')
                                                    : tr('रद्द · Void'),
                                                style: TextStyle(
                                                    color: c.critical,
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w700)))
                                      else
                                        const FinalPill(),
                                    ]),
                                Text(
                                    '${b.customerName.isEmpty ? '' : '${b.customerName} · '}${dateTimeShort(b.at)} · ${b.payments.map((p) => payModeLabel(p.mode)).join(' + ')}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        TextStyle(fontSize: 12, color: c.ink2)),
                              ])),
                          const SizedBox(width: 8),
                          Text(money(b.total),
                              style: baloo(
                                  size: 16,
                                  weight: FontWeight.w800,
                                  color: c.ink)),
                        ]),
                        // Correction actions on their own full-width row —
                        // big enough to tap on a small phone.
                        if (b.status != BillStatus.voided) ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            _action(context, tr('✏️ दुरुस्त · Edit'), c.brand,
                                () => _edit(context, app, b),
                                key: ValueKey('bills-edit-${b.id}')),
                            const SizedBox(width: 8),
                            _action(
                                context,
                                tr('↩️ परतावा · Return'),
                                c.serious,
                                () => _openPartialReturn(context, app, b)),
                            const SizedBox(width: 8),
                            _action(
                                context,
                                tr('❌ रद्द · Void'),
                                c.critical,
                                () => _confirmVoid(
                                    context, app, b.id, b.billNumber)),
                          ]),
                        ],
                      ]),
                ),
              ),
          ]),
      ]),
    );
  }

  Widget _action(
          BuildContext context, String label, Color color, VoidCallback onTap,
          {Key? key}) =>
      Expanded(
        child: Material(
          key: key,
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Container(
              height: 42,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color, fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      );

  Future<void> _edit(BuildContext context, AppState app, Bill b) async {
    final why = app.whyBillNotEditable(b);
    if (why != null) {
      showToast(context, why);
      return;
    }
    // A new bill in progress is kept as a draft — never mixed into the
    // correction of a finalized bill.
    if (app.editingBillId != b.id &&
        (!await keepCurrentBill(context) || !context.mounted)) {
      return;
    }
    app.beginEditBill(b.id);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SalesEntryScreen()));
  }

  /// Partial sales return (spec §13) — each bill line, with a qty stepper
  /// capped at what that line originally sold minus whatever's already been
  /// returned (see [AppState.returnedSoFar]/[AppState.returnSaleLine]).
  /// Credits back to the exact batch the line was sold from.
  void _openPartialReturn(BuildContext context, AppState app, Bill bill) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 14, 16, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                L('बिल #${bill.billNumber} · आंशिक परतावा',
                    'Bill #${bill.billNumber} · Partial return'),
                style: baloo(
                    size: 17, weight: FontWeight.w700, color: context.c.ink)),
            const SizedBox(height: 12),
            for (final item in bill.items) _returnLineRow(ctx, app, bill, item),
          ],
        ),
      ),
    );
  }

  Widget _returnLineRow(
      BuildContext context, AppState app, Bill bill, BillItem item) {
    final c = context.c;
    final p = app.productOf(item.productId);
    final already = app.returnedSoFar(bill, item);
    final maxReturnable = item.qty - already;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
              Text(
                  p?.nameMr.isNotEmpty == true
                      ? p!.nameMr
                      : (p?.name ?? item.productId),
                  style:
                      baloo(size: 13.5, weight: FontWeight.w700, color: c.ink)),
              Text(
                  item.saleType == SaleType.bag
                      ? L('${item.qty.round()} गोणी विकल्या · आधी परत ${already.round()}',
                          '${item.qty.round()} bags sold · already returned ${already.round()}')
                      : L('${kg(item.qty)} सुटे विकले · आधी परत ${kg(already)}',
                          '${kg(item.qty)} loose sold · already returned ${kg(already)}'),
                  style: TextStyle(fontSize: 11, color: c.ink2)),
            ])),
        if (maxReturnable <= 0)
          Text(tr('पूर्ण परत · Fully returned'),
              style: TextStyle(fontSize: 11, color: c.muted))
        else
          FilledButton.tonal(
            onPressed: () =>
                _promptReturnQty(context, app, bill, item, maxReturnable),
            child: Text(tr('परत करा · Return')),
          ),
      ]),
    );
  }

  Future<void> _promptReturnQty(BuildContext context, AppState app, Bill bill,
      BillItem item, double maxReturnable) async {
    final qtyCtrl = TextEditingController(
        text: maxReturnable
            .toStringAsFixed(item.saleType == SaleType.bag ? 0 : 1));
    final qty = await showDialog<double>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(item.saleType == SaleType.bag
            ? tr('गोणी परतावा · Return bags')
            : tr('सुटे परतावा · Return loose kg')),
        content: TextField(
          controller: qtyCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              helperText: tr(
                  'कमाल · Max ${maxReturnable.toStringAsFixed(item.saleType == SaleType.bag ? 0 : 1)}')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('रद्द')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialog, double.tryParse(qtyCtrl.text)),
              child: Text(tr('जतन करा · Save'))),
        ],
      ),
    );
    if (qty == null || qty <= 0) return;
    final error = await app.returnSaleLine(bill, item, qty);
    if (!context.mounted) return;
    if (error != null) {
      showToast(context, error);
    } else {
      Navigator.of(context).pop(); // close the bottom sheet
      showToast(context, tr('परतावा नोंदवला · Return recorded'));
    }
  }

  void _confirmVoid(BuildContext context, AppState app, String id, int number) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.c.surface,
        title: Text(L('बिल #$number रद्द करायचे?', 'Void bill #$number?'),
            style:
                baloo(size: 16, weight: FontWeight.w700, color: context.c.ink)),
        content: Text(tr('साठा परत जमा होईल · Stock will be restored.'),
            style: TextStyle(color: context.c.ink2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(L('नाही', 'No'))),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: context.c.critical),
              onPressed: () async {
                final error = await app.voidBill(id);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (context.mounted) {
                  showToast(context, error ?? tr('बिल रद्द झाले · Voided'));
                }
              },
              child: Text(L('रद्द करा', 'Void'))),
        ],
      ),
    );
  }
}
