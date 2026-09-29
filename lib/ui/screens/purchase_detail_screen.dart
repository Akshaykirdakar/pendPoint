import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/purchase.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../widgets/tiles.dart';
import 'purchase_entry_screen.dart';
import '../../utils/lang.dart';

/// Opens [p] in Purchase Entry for correction (saved as a new revision).
void openPurchaseEdit(BuildContext context, AppState app, Purchase p) {
  final why = app.whyPurchaseLocked(p);
  if (why != null) {
    showToast(context, why);
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PurchaseEntryScreen(editPurchaseId: p.id)));
}

/// Confirms, then voids [p] (its bags come back out of stock).
Future<void> confirmVoidPurchase(
    BuildContext context, AppState app, Purchase p) async {
  final why = app.whyPurchaseLocked(p);
  if (why != null) {
    showToast(context, why);
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.c.surface,
      title: Text(L('खरेदी #${p.purchaseNumber} रद्द करायची?', 'Void purchase #${p.purchaseNumber}?'),
          style: baloo(size: 17, weight: FontWeight.w700, color: ctx.c.ink)),
      content: Text(
          tr('${p.totalBags} गोणी साठ्यातून कमी होतील. खरेदी रेकॉर्ड "रद्द" म्हणून राहील.\n'
              'Void purchase #${p.purchaseNumber}? ${p.totalBags} bags will be removed from stock. The record is kept, marked void.'),
          style: TextStyle(color: ctx.c.ink2)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('नाही · No'))),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.c.critical),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('रद्द करा · Void'))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final error = await app.voidPurchase(p.id);
  if (!context.mounted) return;
  showToast(context, error ?? tr('खरेदी रद्द झाली · Purchase voided'));
}

/// Full-screen view of the supplier-bill photo saved with [p] (pinch to
/// zoom). If the file can't be read, says so instead of a broken image.
void _showBillPhoto(BuildContext context, AppState app, Purchase p) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: ctx.c.surface,
      insetPadding: const EdgeInsets.all(12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
          child: Row(children: [
            Expanded(
              child: Text('📷 ${L('बिल फोटो', 'Bill Photo')} · #${p.purchaseNumber}',
                  style:
                      baloo(size: 16, weight: FontWeight.w700, color: ctx.c.ink)),
            ),
            IconButton(
                tooltip: L('बंद करा', 'Close'),
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        Flexible(
          child: FutureBuilder<Uint8List?>(
            future: app.purchaseBillPhoto(p),
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator());
              }
              if (snap.data == null) {
                return Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(L('फोटो उघडता आला नाही', 'Could not open the photo'),
                      key: const ValueKey('purchase-photo-missing'),
                      style: TextStyle(color: ctx.c.ink2)),
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Image.memory(snap.data!,
                      key: const ValueKey('purchase-photo-image'),
                      fit: BoxFit.contain),
                ),
              );
            },
          ),
        ),
      ]),
    ),
  );
}

/// One purchase bill: lines (purchase rate, with the selling price shown
/// separately for reference), totals, and visible Edit / Void actions.
class PurchaseDetailScreen extends StatelessWidget {
  final String purchaseId;
  const PurchaseDetailScreen({required this.purchaseId, super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final p = app.purchaseOf(purchaseId);
    if (p == null) {
      return PendScaffold(
          titleMr: 'खरेदी',
          titleEn: 'Purchase',
          body: EmptyState('🔍', tr('खरेदी सापडली नाही · Purchase not found')));
    }
    final locked = app.whyPurchaseLocked(p);
    final replacement = p.replacedByPurchaseId == null
        ? null
        : app.purchaseOf(p.replacedByPurchaseId!);

    Widget kv(String k, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(k, style: TextStyle(color: c.ink2))),
            Text(v,
                style: bold
                    ? baloo(size: 18, weight: FontWeight.w800, color: c.brand)
                    : TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
          ]),
        );

    return PendScaffold(
      titleMr: 'खरेदी #${p.purchaseNumber}',
      titleEn: p.revision > 0 ? 'Purchase · Rev ${p.revision}' : 'Purchase',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            Row(children: [
              Expanded(
                  child: Text(p.supplierName,
                      style: baloo(
                          size: 16, weight: FontWeight.w700, color: c.ink))),
              PurchaseStatusPill(p.status,
                  replaced: p.replacedByPurchaseId != null),
            ]),
            const SizedBox(height: 6),
            if (p.supplierBillNo.isNotEmpty)
              kv(tr('पुरवठादार बिल · Supplier bill'), p.supplierBillNo),
            kv(tr('दिनांक · Date'), dayFull(p.purchaseDate)),
            kv(tr('गोणी · Bags'), '${p.totalBags}'),
          ]),
        ),
        // Only when a photo was saved — never a broken image placeholder.
        if (p.hasBillPhoto) ...[
          const SizedBox(height: 10),
          BigButton.ghost('📷 ${L('बिल फोटो पहा', 'View Bill Photo')}',
              key: const ValueKey('purchase-view-photo'),
              onTap: () => _showBillPhoto(context, app, p)),
        ],
        if (replacement != null) ...[
          const SizedBox(height: 10),
          BigButton.ghost(
              tr('➡️ दुरुस्त खरेदी पहा · Open corrected version (Rev ${replacement.revision})'),
              onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                      builder: (_) =>
                          PurchaseDetailScreen(purchaseId: replacement.id)))),
        ],
        SectionHeader(tr('उत्पादने · Products')),
        CardList([
          for (final it in p.items)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            app.productOf(it.productId)?.nameMr ?? it.productId,
                            style: baloo(
                                size: 14,
                                weight: FontWeight.w700,
                                color: c.ink)),
                        Text(
                            '${app.brandOf(it.brandId)?.name ?? ''} · ${L('बॅच', 'Batch')} ${it.batchNo}'
                            '${it.expiry == null ? '' : ' · ${L('मुदत', 'exp')} ${dayFull(it.expiry!)}'}',
                            style: TextStyle(fontSize: 11.5, color: c.ink2)),
                        Text(
                            '🛍️ ${it.bags} × ${L('खरेदी', 'cost')} ${money(it.rate)}'
                            '${it.sellingRateAtPurchase > 0 ? ' · ${L('विक्री', 'sell')} ${money(it.sellingRateAtPurchase)}' : ''}',
                            style: TextStyle(fontSize: 11.5, color: c.muted)),
                      ]),
                ),
                Text(money(it.amount),
                    style:
                        baloo(size: 15, weight: FontWeight.w800, color: c.ink)),
              ]),
            ),
        ]),
        const SizedBox(height: 12),
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            kv(tr('उप-बेरीज · Subtotal'), money(p.subtotal)),
            kv(tr('+ इतर खर्च · Other charges'), money(p.otherCharges)),
            Divider(color: c.line),
            kv(tr('= एकूण · Grand total'), money(p.total), bold: true),
          ]),
        ),
        const SizedBox(height: 14),
        if (p.status != BillStatus.voided) ...[
          TileGrid(columns: 2, gap: 10, [
            BigTile(
                key: const ValueKey('purchase-edit'),
                icon: Icons.edit_rounded,
                mr: 'खरेदी दुरुस्त',
                en: 'Edit',
                color: c.s1,
                onTap: locked != null
                    ? null
                    : () => openPurchaseEdit(context, app, p)),
            BigTile(
                key: const ValueKey('purchase-void'),
                icon: Icons.cancel_rounded,
                mr: 'रद्द करा',
                en: 'Void',
                color: c.critical,
                onTap: locked != null
                    ? null
                    : () => confirmVoidPurchase(context, app, p)),
          ]),
          if (locked != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr(locked),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: c.muted)),
            ),
        ],
      ]),
    );
  }
}
