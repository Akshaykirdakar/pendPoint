import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/batch.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

/// Branch-to-branch stock transfer (spec §14). Selects a source batch (with
/// its available quantity, branch and expiry) and a destination branch;
/// [AppState.transferStock] preserves the batch's number/expiry/cost/
/// supplier identity at the destination — see that method's doc comment.
class StockTransferScreen extends StatefulWidget {
  const StockTransferScreen({super.key});
  @override
  State<StockTransferScreen> createState() => _StockTransferScreenState();
}

class _StockTransferScreenState extends State<StockTransferScreen> {
  String? _productId;
  String? _batchId;
  String? _destBranchId;
  final _bags = TextEditingController();
  final _looseKg = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _bags.dispose();
    _looseKg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final batch = _batchId == null ? null : app.batchOf(_batchId!);
    final sourceBranchBatches = app.batches
        .where((b) =>
            (_productId == null || b.productId == _productId) &&
            b.bagsAvailable + b.looseKgAvailable > 0)
        .toList()
      ..sort((a, b) => a.expiry == null
          ? 1
          : (b.expiry == null ? -1 : a.expiry!.compareTo(b.expiry!)));

    return PendScaffold(
      titleMr: 'शाखा हस्तांतरण',
      titleEn: 'Stock transfer',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('एका शाखेतून दुसऱ्या शाखेत साठा हस्तांतरित करा — बॅच ओळख कायम राहते.\n'
            'Move stock between branches — batch identity is preserved.',
            style: TextStyle(color: c.ink2, fontSize: 13)),
        const SizedBox(height: 14),
        _label('उत्पादन · Product (filter, optional)'),
        DropdownButtonFormField<String?>(
          initialValue: _productId,
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: null, child: Text('सर्व · All')),
            for (final p in app.products)
              DropdownMenuItem(value: p.id, child: Text(p.nameMr)),
          ],
          onChanged: (v) => setState(() {
            _productId = v;
            _batchId = null;
          }),
        ),
        const SizedBox(height: 12),
        _label('स्रोत बॅच · Source batch *'),
        DropdownButtonFormField<String>(
          initialValue: _batchId,
          isExpanded: true,
          items: [
            for (final b in sourceBranchBatches)
              DropdownMenuItem(
                  value: b.id,
                  child: Text(
                      '${app.productOf(b.productId)?.nameMr ?? b.productId} · ${b.batchNo} · '
                      '${app.branchOf(b.branchId)?.nameMr ?? b.branchId} · '
                      '${b.bagsAvailable} bags + ${kg(b.looseKgAvailable)}',
                      overflow: TextOverflow.ellipsis)),
          ],
          hint: const Text('निवडा · Select'),
          onChanged: (v) => setState(() => _batchId = v),
        ),
        if (batch != null) ...[
          const SizedBox(height: 6),
          Text(
              'उपलब्ध · Available: ${batch.bagsAvailable} bags + ${kg(batch.looseKgAvailable)}'
              '${batch.expiry != null ? ' · Expiry ${dayFull(batch.expiry!)}' : ''}',
              style: TextStyle(fontSize: 11.5, color: c.muted)),
        ],
        const SizedBox(height: 12),
        _label('लक्ष्य शाखा · Destination branch *'),
        DropdownButtonFormField<String>(
          initialValue: _destBranchId,
          items: [
            for (final b in app.branches.where((b) => b.id != batch?.branchId))
              DropdownMenuItem(value: b.id, child: Text('${b.nameMr} · ${b.name}')),
          ],
          hint: const Text('निवडा · Select'),
          onChanged: (v) => setState(() => _destBranchId = v),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _field('गोणी · Bags', _bags, number: true)),
          const SizedBox(width: 11),
          Expanded(child: _field('सुटे (kg) · Loose kg', _looseKg, number: true)),
        ]),
        const SizedBox(height: 8),
        BigButton.brand(_busy ? 'हस्तांतरित करत आहे... · Transferring...' : '🔁 हस्तांतरण करा · Transfer',
            onTap: _busy ? null : () => _submit(app, batch)),
      ]),
    );
  }

  Future<void> _submit(AppState app, Batch? batch) async {
    if (batch == null) {
      showToast(context, 'स्रोत बॅच निवडा · Pick a source batch');
      return;
    }
    if (_destBranchId == null) {
      showToast(context, 'लक्ष्य शाखा निवडा · Pick a destination branch');
      return;
    }
    final bags = int.tryParse(_bags.text) ?? 0;
    final looseKg = double.tryParse(_looseKg.text) ?? 0;
    if (bags <= 0 && looseKg <= 0) {
      showToast(context, 'योग्य प्रमाण टाका · Enter a valid quantity');
      return;
    }
    setState(() => _busy = true);
    try {
      final error =
          await app.transferStock(batch.id, _destBranchId!, bags: bags, looseKg: looseKg);
      if (!mounted) return;
      if (error != null) {
        showToast(context, error);
      } else {
        showToast(context, 'हस्तांतरण पूर्ण · Transfer complete');
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _label(String t) => Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 5),
      child: Text(t,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.c.ink2)));

  Widget _field(String label, TextEditingController ctrl, {bool number = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(label),
          TextField(
              controller: ctrl,
              keyboardType: number
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text),
        ]),
      );
}
