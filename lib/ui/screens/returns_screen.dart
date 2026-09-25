import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bill.dart';
import '../../models/enums.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

class ReturnsScreen extends StatelessWidget {
  const ReturnsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final bills = [...app.bills]..sort((a, b) => b.at.compareTo(a.at));
    final recent = bills.take(15).toList();

    return PendScaffold(
      titleMr: 'परतावा / रद्द',
      titleEn: 'Returns & void',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            'बिल रद्द केल्यास साठा परत जमा होतो · Voiding a bill restores its stock. Bills are kept (marked void), never deleted.',
            style: TextStyle(color: c.ink2, fontSize: 13)),
        const SizedBox(height: 14),
        if (app.historyLoading && bills.isEmpty)
          const HistoryLoadingNote()
        else
          CardList([
            for (final b in recent)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  CircleAvatar(
                      backgroundColor: c.surface2, child: const Text('🧾')),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Row(children: [
                          Text('#${b.billNumber}',
                              style: baloo(
                                  size: 14,
                                  weight: FontWeight.w700,
                                  color: c.ink)),
                          if (b.status == BillStatus.voided) ...[
                            const SizedBox(width: 6),
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                    color: c.critical.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999)),
                                child: Text('रद्द',
                                    style: TextStyle(
                                        color: c.critical,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700))),
                          ],
                        ]),
                        Text(
                            '${dateTimeShort(b.at)} · ${b.items.length} items · ${b.payments.map((p) => p.mode.name).join('+')}',
                            style: TextStyle(fontSize: 11.5, color: c.ink2)),
                      ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(money(b.total),
                        style: baloo(
                            size: 14, weight: FontWeight.w800, color: c.ink)),
                    if (b.status != BillStatus.voided) ...[
                      const SizedBox(height: 5),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        GestureDetector(
                          onTap: () => _openPartialReturn(context, app, b),
                          child: Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                  color: c.serious.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text('आंशिक परतावा · Return',
                                  style: TextStyle(
                                      color: c.serious,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700))),
                        ),
                        GestureDetector(
                          onTap: () =>
                              _confirmVoid(context, app, b.id, b.billNumber),
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                  color: c.critical.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text('रद्द Void',
                                  style: TextStyle(
                                      color: c.critical,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700))),
                        ),
                      ]),
                    ],
                  ]),
                ]),
              ),
          ]),
      ]),
    );
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
            Text('बिल #${bill.billNumber} · आंशिक परतावा',
                style: baloo(
                    size: 17, weight: FontWeight.w700, color: context.c.ink)),
            Text('Partial return',
                style: TextStyle(fontSize: 12, color: context.c.muted)),
            const SizedBox(height: 12),
            for (final item in bill.items)
              _returnLineRow(ctx, app, bill, item),
          ],
        ),
      ),
    );
  }

  Widget _returnLineRow(BuildContext context, AppState app, Bill bill, BillItem item) {
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
              Text(p?.nameMr.isNotEmpty == true ? p!.nameMr : (p?.name ?? item.productId),
                  style: baloo(size: 13.5, weight: FontWeight.w700, color: c.ink)),
              Text(
                  item.saleType == SaleType.bag
                      ? '${item.qty.round()} गोणी विकले · already returned ${already.round()}'
                      : '${kg(item.qty)} सुटे विकले · already returned ${kg(already)}',
                  style: TextStyle(fontSize: 11, color: c.ink2)),
            ])),
        if (maxReturnable <= 0)
          Text('पूर्ण परत · Fully returned',
              style: TextStyle(fontSize: 11, color: c.muted))
        else
          FilledButton.tonal(
            onPressed: () => _promptReturnQty(context, app, bill, item, maxReturnable),
            child: const Text('परत करा · Return'),
          ),
      ]),
    );
  }

  Future<void> _promptReturnQty(BuildContext context, AppState app, Bill bill,
      BillItem item, double maxReturnable) async {
    final qtyCtrl = TextEditingController(text: maxReturnable.toStringAsFixed(
        item.saleType == SaleType.bag ? 0 : 1));
    final qty = await showDialog<double>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(item.saleType == SaleType.bag
            ? 'गोणी परतावा · Return bags'
            : 'सुटे परतावा · Return loose kg'),
        content: TextField(
          controller: qtyCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              helperText: 'कमाल · Max ${maxReturnable.toStringAsFixed(
                  item.saleType == SaleType.bag ? 0 : 1)}'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog), child: const Text('रद्द')),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, double.tryParse(qtyCtrl.text)),
              child: const Text('जतन करा · Save')),
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
      showToast(context, 'परतावा नोंदवला · Return recorded');
    }
  }

  void _confirmVoid(BuildContext context, AppState app, String id, int number) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.c.surface,
        title: Text('बिल #$number रद्द करायचे?',
            style:
                baloo(size: 16, weight: FontWeight.w700, color: context.c.ink)),
        content: Text('साठा परत जमा होईल. Stock will be restored.',
            style: TextStyle(color: context.c.ink2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('नाही')),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: context.c.critical),
              onPressed: () async {
                await app.voidBill(id);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (context.mounted) {
                  showToast(context, 'बिल रद्द झाले · Voided');
                }
              },
              child: const Text('रद्द करा')),
        ],
      ),
    );
  }
}
