import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/party.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'purchase_detail_screen.dart';
import 'purchase_entry_screen.dart';
import '../../utils/lang.dart';

/// All purchase bills, newest first — searchable by purchase no., party
/// (code/name/mobile) or supplier bill no., each with visible
/// View / Edit / Void actions.
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
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
    final q = _search.text.trim().toLowerCase();
    final list = app.purchases.where((p) {
      if (q.isEmpty) return true;
      final party = app.partyOf(p.supplierId);
      return '${p.purchaseNumber}' == q.replaceAll('#', '') ||
          p.supplierBillNo.toLowerCase().contains(q) ||
          p.supplierName.toLowerCase().contains(q) ||
          (party != null && partyMatchRank(party, q) != null);
    }).toList()
      ..sort((a, b) {
        final byNo = b.purchaseNumber.compareTo(a.purchaseNumber);
        return byNo != 0 ? byNo : b.revision.compareTo(a.revision);
      });

    return PendScaffold(
      titleMr: 'खरेदी यादी',
      titleEn: 'Purchases',
      actions: [
        BarAction(tr('＋ खरेदी · New'),
            icon: Icons.add_rounded,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PurchaseEntryScreen()))),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              hintText: tr('क्र., पार्टी किंवा बिल क्र. · No., party or bill no.')),
        ),
        const SizedBox(height: 12),
        if (app.historyLoading && app.purchases.isEmpty)
          const HistoryLoadingNote()
        else if (list.isEmpty)
          EmptyState('📦', tr('अजून खरेदी नाही · No purchases yet'))
        else
          for (final p in list) ...[
            Container(
              decoration: cardDecoration(context, radius: 14),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              PurchaseDetailScreen(purchaseId: p.id))),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(children: [
                                  Text(
                                      '#${p.purchaseNumber}${p.revision > 0 ? ' · Rev ${p.revision}' : ''}',
                                      style: baloo(
                                          size: 14,
                                          weight: FontWeight.w800,
                                          color: c.ink)),
                                  const SizedBox(width: 8),
                                  PurchaseStatusPill(p.status,
                                      replaced: p.replacedByPurchaseId != null),
                                ]),
                                Text(p.supplierName,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: c.ink2)),
                                Text(
                                    '${dayFull(p.purchaseDate)} · 🛍️ ${p.totalBags} · ${L('${p.items.length} ओळी', '${p.items.length} lines')}'
                                    '${p.supplierBillNo.isEmpty ? '' : ' · ${L('बिल', 'bill')} ${p.supplierBillNo}'}',
                                    style: TextStyle(
                                        fontSize: 11.5, color: c.muted)),
                              ]),
                        ),
                        Text(money(p.total),
                            style: baloo(
                                size: 15,
                                weight: FontWeight.w800,
                                color: c.ink)),
                      ]),
                    ),
                    if (p.status == BillStatus.finalized) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        _chip(context, tr('✏️ दुरुस्त · Edit'), c.brand,
                            () => openPurchaseEdit(context, app, p)),
                        const SizedBox(width: 8),
                        _chip(context, tr('रद्द · Void'), c.critical,
                            () => confirmVoidPurchase(context, app, p)),
                      ]),
                    ],
                  ]),
            ),
            const SizedBox(height: 10),
          ],
      ]),
    );
  }

  Widget _chip(BuildContext context, String label, Color color,
          VoidCallback onTap) =>
      Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ),
      );
}
