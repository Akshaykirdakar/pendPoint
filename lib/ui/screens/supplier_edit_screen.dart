import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../../utils/lang.dart';

/// Supplier Master create/edit (spec §2) — same conventions as
/// [ProductEditScreen]: optional id = new vs edit, `_label`/`_f` field
/// helpers, busy-gated save. Shows purchase history + a soft-delete notice
/// when the supplier is already referenced by a batch/purchase.
class SupplierEditScreen extends StatefulWidget {
  final String? supplierId;
  const SupplierEditScreen({this.supplierId, super.key});
  @override
  State<SupplierEditScreen> createState() => _SupplierEditScreenState();
}

class _SupplierEditScreenState extends State<SupplierEditScreen> {
  final name = TextEditingController(),
      mobile = TextEditingController(),
      altMobile = TextEditingController(),
      address = TextEditingController(),
      gstin = TextEditingController(),
      email = TextEditingController(),
      opening = TextEditingController(text: '0'),
      notes = TextEditingController();
  bool active = true, busy = false;

  @override
  void initState() {
    super.initState();
    final a = context.read<AppState>();
    final s = widget.supplierId == null ? null : a.supplierOf(widget.supplierId!);
    if (s != null) {
      name.text = s.name;
      mobile.text = s.mobile;
      altMobile.text = s.altMobile;
      address.text = s.address;
      gstin.text = s.gstin;
      email.text = s.email;
      opening.text = '${s.openingBalance}';
      notes.text = s.notes;
      active = s.active;
    }
  }

  @override
  void dispose() {
    for (final c in [name, mobile, altMobile, address, gstin, email, opening, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppState>();
    final edit = widget.supplierId != null;
    final c = context.c;
    return PendScaffold(
      titleMr: edit ? 'पुरवठादार संपादन' : 'नवीन पुरवठादार',
      titleEn: edit ? 'Edit supplier' : 'New supplier',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (edit) _purchaseHistory(a, widget.supplierId!),
        _f(tr('पुरवठादार नाव · Supplier name *'), name),
        Row(children: [
          Expanded(child: _f(tr('मोबाईल · Mobile'), mobile)),
          const SizedBox(width: 10),
          Expanded(child: _f(tr('पर्यायी मोबाईल · Alt. mobile'), altMobile)),
        ]),
        _f(tr('पत्ता · Address'), address),
        Row(children: [
          Expanded(child: _f(L('GSTIN (ऐच्छिक)', 'GSTIN (optional)'), gstin)),
          const SizedBox(width: 10),
          Expanded(child: _f(tr('ईमेल · Email'), email)),
        ]),
        _f(tr('सुरुवातीची शिल्लक · Opening balance'), opening, num: true, prefix: '₹'),
        _f(tr('टिपा · Notes'), notes),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('सक्रिय · Active')),
          value: active,
          onChanged: busy ? null : (v) => setState(() => active = v),
        ),
        const SizedBox(height: 8),
        BigButton.brand(busy ? 'Saving...' : tr('जतन करा · Save'),
            onTap: busy ? null : _save),
        if (edit) ...[
          const SizedBox(height: 10),
          BigButton.danger(
              a.supplierHasHistory(widget.supplierId!)
                  ? tr('🚫 निष्क्रिय करा · Deactivate')
                  : '🗑 ${L('हटवा', 'Delete')}',
              onTap: busy ? null : _delete),
          const SizedBox(height: 6),
          Text(
              a.supplierHasHistory(widget.supplierId!)
                  ? tr('हा पुरवठादार खरेदी/बॅचमध्ये वापरला गेला आहे — तो हटवला जाणार नाही, फक्त निष्क्रिय होईल.\n'
                      'This supplier has purchase/batch history — it will be deactivated, not deleted.')
                  : '',
              style: TextStyle(fontSize: 11, color: c.muted)),
        ],
      ]),
    );
  }

  Widget _purchaseHistory(AppState a, String supplierId) {
    final c = context.c;
    final theirBatches = a.batches.where((b) => b.supplierId == supplierId).toList()
      ..sort((x, y) => y.createdAt.compareTo(x.createdAt));
    if (theirBatches.isEmpty) return const SizedBox.shrink();
    final totalBags = theirBatches.fold(0, (s, b) => s + b.bagsReceived);
    final totalCost =
        theirBatches.fold(0.0, (s, b) => s + b.unitCost * b.bagsReceived);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: cardDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('खरेदी इतिहास · Purchase history'),
            style: baloo(size: 13.5, weight: FontWeight.w700, color: c.ink)),
        const SizedBox(height: 4),
        Text('${L('${theirBatches.length} बॅच', '${theirBatches.length} batches')} · 🛍️ $totalBags · ${money(totalCost)}',
            style: TextStyle(fontSize: 12, color: c.ink2)),
      ]),
    );
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      showToast(context, tr('नाव टाका · Enter supplier name'));
      return;
    }
    setState(() => busy = true);
    try {
      await context.read<AppState>().saveSupplier(
            id: widget.supplierId,
            name: name.text.trim(),
            mobile: mobile.text.trim(),
            altMobile: altMobile.text.trim(),
            address: address.text.trim(),
            gstin: gstin.text.trim(),
            email: email.text.trim(),
            openingBalance: double.tryParse(opening.text) ?? 0,
            active: active,
            notes: notes.text.trim(),
          );
      if (mounted) {
        showToast(context, tr('पुरवठादार जतन · Supplier saved'));
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        showToast(context, tr('जतन करता आले नाही · Unable to save supplier'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _delete() async {
    final a = context.read<AppState>();
    final hasHistory = a.supplierHasHistory(widget.supplierId!);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: Text(hasHistory ? 'Deactivate supplier?' : 'Delete supplier?'),
        content: Text(hasHistory
            ? 'This supplier has purchase/batch history and will be deactivated, not deleted.'
            : 'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(x, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(x, true),
              child: Text(hasHistory ? L('निष्क्रिय करा', 'Deactivate') : L('हटवा', 'Delete'))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => busy = true);
    try {
      await a.deleteSupplier(widget.supplierId!);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        showToast(context, tr('अयशस्वी · Action failed'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _f(String label, TextEditingController c,
          {bool num = false, String? prefix}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.c.ink2)),
          const SizedBox(height: 5),
          TextField(
              controller: c,
              enabled: !busy,
              keyboardType: num
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(prefixText: prefix)),
        ]),
      );
}
