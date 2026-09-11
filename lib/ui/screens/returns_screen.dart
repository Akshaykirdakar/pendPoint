import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
                  ],
                ]),
              ]),
            ),
        ]),
      ]),
    );
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
