import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/batch.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../../utils/lang.dart';

/// Batch & Expiry Report (spec §10–§12/§15/§16-K) — one reusable screen
/// covering Batch-wise Stock, Expiry/Near-Expiry/Expired, and every
/// Supplier-/Product-wise stock breakdown, instead of eight
/// near-identical single-purpose report screens. Reads live [AppState.batches]
/// directly (this is current inventory state, not a date-ranged transaction
/// report, so it doesn't go through [ReportFilter]/`buildReport`).
class BatchReportScreen extends StatefulWidget {
  const BatchReportScreen({super.key});
  @override
  State<BatchReportScreen> createState() => _BatchReportScreenState();
}

enum _ExpiryStatus { all, active, nearExpiry, expired }
enum _SortBy { expiry, daysLeft, qty, product, supplier }

class _BatchReportScreenState extends State<BatchReportScreen> {
  String? _productId;
  String? _supplierId;
  _ExpiryStatus _status = _ExpiryStatus.all;
  _SortBy _sort = _SortBy.expiry;
  static const _nearExpiryDays = 30; // matches spec §10 default threshold

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    final rows = app.batches.where((b) {
      if (_productId != null && b.productId != _productId) return false;
      if (_supplierId != null && b.supplierId != _supplierId) return false;
      final qty = b.availableKg(app.productOf(b.productId)?.bagWeightKg ?? 1);
      switch (_status) {
        case _ExpiryStatus.all:
          break;
        case _ExpiryStatus.active:
          if (b.isExpired || qty <= 0) return false;
          break;
        case _ExpiryStatus.nearExpiry:
          final d = b.daysRemaining();
          if (d == null || d < 0 || d > _nearExpiryDays || qty <= 0) return false;
          break;
        case _ExpiryStatus.expired:
          if (!b.isExpired) return false;
          break;
      }
      return true;
    }).toList();

    rows.sort((a, b) {
      switch (_sort) {
        case _SortBy.expiry:
          if (a.expiry == null && b.expiry == null) return 0;
          if (a.expiry == null) return 1;
          if (b.expiry == null) return -1;
          return a.expiry!.compareTo(b.expiry!);
        case _SortBy.daysLeft:
          final da = a.daysRemaining() ?? 999999;
          final db = b.daysRemaining() ?? 999999;
          return da.compareTo(db);
        case _SortBy.qty:
          final pa = app.productOf(a.productId)?.bagWeightKg ?? 1;
          final pb = app.productOf(b.productId)?.bagWeightKg ?? 1;
          return b.availableKg(pb).compareTo(a.availableKg(pa));
        case _SortBy.product:
          return (app.productOf(a.productId)?.nameMr ?? '')
              .compareTo(app.productOf(b.productId)?.nameMr ?? '');
        case _SortBy.supplier:
          return (app.supplierOf(a.supplierId ?? '')?.name ?? '')
              .compareTo(app.supplierOf(b.supplierId ?? '')?.name ?? '');
      }
    });

    return PendScaffold(
      titleMr: 'बॅच व एक्सपायरी अहवाल',
      titleEn: 'Batch & Expiry Report',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _filters(context, app),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          EmptyState('📭', tr('कोणतीही बॅच सापडली नाही · No batches found'))
        else
          CardList([
            for (final b in rows) _batchRow(context, app, b),
          ]),
      ]),
    );
  }

  Widget _filters(BuildContext context, AppState app) {
    return Container(
      decoration: cardDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButtonFormField<String?>(
            initialValue: _supplierId,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('पुरवठादार · Supplier')),
            items: [
              DropdownMenuItem(value: null, child: Text(tr('सर्व · All'))),
              for (final s in app.suppliers)
                DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _supplierId = v),
          ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          initialValue: _productId,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('उत्पाद · Product')),
          items: [
            DropdownMenuItem(value: null, child: Text(tr('सर्व · All'))),
            for (final p in app.products)
              DropdownMenuItem(value: p.id, child: Text(p.nameMr, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _productId = v),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in _ExpiryStatus.values)
            ChoiceChip(
              label: Text(switch (s) {
                _ExpiryStatus.all => tr('सर्व · All'),
                _ExpiryStatus.active => tr('सक्रिय · Active'),
                _ExpiryStatus.nearExpiry => tr('नजीक एक्सपायरी · Near Expiry'),
                _ExpiryStatus.expired => tr('एक्सपायर · Expired'),
              }),
              selected: _status == s,
              onSelected: (_) => setState(() => _status = s),
            ),
        ]),
        const SizedBox(height: 10),
        DropdownButtonFormField<_SortBy>(
          isExpanded: true,
          initialValue: _sort,
          decoration: InputDecoration(labelText: tr('क्रमवारी · Sort by')),
          items: [
            DropdownMenuItem(value: _SortBy.expiry, child: Text(tr('एक्सपायरी · Expiry date'))),
            DropdownMenuItem(value: _SortBy.daysLeft, child: Text(tr('दिवस बाकी · Days left'))),
            DropdownMenuItem(value: _SortBy.qty, child: Text(tr('प्रमाण · Quantity'))),
            DropdownMenuItem(value: _SortBy.product, child: Text(tr('उत्पाद · Product'))),
            DropdownMenuItem(value: _SortBy.supplier, child: Text(tr('पुरवठादार · Supplier'))),
          ],
          onChanged: (v) => setState(() => _sort = v ?? _sort),
        ),
      ]),
    );
  }

  Widget _batchRow(BuildContext context, AppState app, Batch b) {
    final c = context.c;
    final p = app.productOf(b.productId);
    final supplier = b.supplierId == null ? null : app.supplierOf(b.supplierId!);
    final days = b.daysRemaining();
    final qty = b.availableKg(p?.bagWeightKg ?? 1);

    late Color statusColor;
    late String statusLabel;
    if (b.isExpired) {
      statusColor = c.critical;
      statusLabel = tr('एक्सपायर · Expired');
    } else if (days != null && days <= _nearExpiryDays && qty > 0) {
      statusColor = c.warning;
      statusLabel = tr('$days दिवस बाकी · $days days left');
    } else {
      statusColor = c.good;
      statusLabel = tr('सक्रिय · Active');
    }

    return Padding(
      padding: const EdgeInsets.all(13),
      child: Row(children: [
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
              Text(p?.nameMr.isNotEmpty == true ? p!.nameMr : (p?.name ?? b.productId),
                  style: baloo(size: 14, weight: FontWeight.w700, color: c.ink)),
              Text('${b.batchNo}'
                  '${supplier != null ? ' · ${supplier.name}' : ''}',
                  style: TextStyle(fontSize: 11.5, color: c.ink2)),
              Text('🛍️ ${b.bagsAvailable} · ${kg(b.looseKgAvailable)}',
                  style: TextStyle(fontSize: 11.5, color: c.muted)),
            ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (b.expiry != null)
            Text(dayFull(b.expiry!),
                style: baloo(size: 12.5, weight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999)),
            child: Text(statusLabel,
                style: TextStyle(
                    color: statusColor, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ),
        ]),
      ]),
    );
  }
}
