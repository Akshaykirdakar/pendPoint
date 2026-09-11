import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final logs = [...app.logs]..sort((a, b) => b.at.compareTo(a.at));

    String label(StockLogType t) => switch (t) {
          StockLogType.purchase => 'खरेदी Purchase',
          StockLogType.sale => 'विक्री Sale',
          StockLogType.bagOpened => 'गोणी उघडली Bag opened',
          StockLogType.adjustment => 'समायोजन Adjust',
          StockLogType.saleVoid => 'रद्द Void',
          StockLogType.returned => 'परतावा Return',
        };
    Color color(StockLogType t) => switch (t) {
          StockLogType.purchase => c.good,
          StockLogType.sale => c.s1,
          StockLogType.bagOpened => c.accent,
          StockLogType.adjustment => c.muted,
          StockLogType.saleVoid => c.critical,
          StockLogType.returned => c.serious,
        };

    return PendScaffold(
      titleMr: 'साठा इतिहास',
      titleEn: 'Stock history',
      body: (app.historyLoading && logs.isEmpty)
          ? const HistoryLoadingNote()
          : logs.isEmpty
              ? const EmptyState('🕓', 'कोणतीही नोंद नाही · No history')
              : CardList([
              for (final l in logs)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: color(l.type).withValues(alpha: 0.15),
                            shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child:
                            Icon(Icons.circle, size: 12, color: color(l.type))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Text(
                              '${label(l.type)} · ${app.productOf(l.productId)?.nameMr ?? ''}',
                              style: baloo(
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: c.ink)),
                          Text(
                              '${dateTimeShort(l.at)}${' · बॅच ${l.batchNo}'}${' · ${l.note}'}',
                              style: TextStyle(fontSize: 11.5, color: c.ink2)),
                        ])),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (l.bagsDelta != 0)
                            Text('${l.bagsDelta > 0 ? '+' : ''}${l.bagsDelta}b',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: c.ink)),
                          if (l.looseKgDelta != 0)
                            Text(
                                '${l.looseKgDelta > 0 ? '+' : ''}${l.looseKgDelta.toStringAsFixed(0)}kg',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: c.ink)),
                        ]),
                  ]),
                ),
            ]),
    );
  }
}
