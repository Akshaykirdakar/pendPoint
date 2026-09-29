import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../../utils/lang.dart';

/// Stock In — rebuilt per the reviewed branch/batch/expiry architecture
/// (spec §1/§21). Selection order: Product (shop-wide) → Supplier
/// (mandatory) → Batch No. → Quantity → Cost → Expiry → Add Stock.
class StockInScreen extends StatefulWidget {
  final String? productId;
  const StockInScreen({this.productId, super.key});
  @override
  State<StockInScreen> createState() => _StockInScreenState();
}

enum _Unit { bags, loose }

class _StockInScreenState extends State<StockInScreen> {
  String? _branchId;
  String? _pid;
  String? _supplierId;
  _Unit _unit = _Unit.bags;
  final _qty = TextEditingController(text: '10');
  final _cost = TextEditingController();
  final _batch = TextEditingController();
  DateTime? _expiry;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _branchId = app.activeBranchId ?? app.branches.where((b) => b.active).firstOrNull?.id;
    _pid = widget.productId;
  }

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    _batch.dispose();
    super.dispose();
  }

  // Product availability is shop-wide in the single-branch app.
  List<Product> _productsForBranch(AppState app) => app.products;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;

    if (app.branches.isEmpty) {
      return PendScaffold(
        titleMr: 'साठा भरा',
        titleEn: 'Stock in',
        body: EmptyState('🏬',
            tr('दुकान सेट झाले नाही · Shop is not set up yet.')),
      );
    }

    final products = _productsForBranch(app);
    // The previously-selected product may no longer belong to this branch
    // (branch changed, or the product was reassigned elsewhere).
    if (_pid != null && !products.any((p) => p.id == _pid)) _pid = null;
    final product = _pid == null ? null : app.productOf(_pid!);

    return PendScaffold(
      titleMr: 'साठा भरा',
      titleEn: 'Stock in',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('नवीन खरेदी नोंदवा · Record a purchase against a real batch.'),
            style: TextStyle(color: c.ink2, fontSize: 13)),
        const SizedBox(height: 14),
        _label(tr('उत्पादन · Product *')),
        DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _pid,
              items: [
                for (final p in products)
                  DropdownMenuItem(
                      value: p.id,
                      child: Text('${p.nameMr} · ${p.name}',
                          overflow: TextOverflow.ellipsis)),
              ],
              hint: Text(products.isEmpty
                  ? tr('उत्पादने नाहीत · No products yet')
                  : tr('निवडा · Select')),
              onChanged: (v) => setState(() => _pid = v),
        ),
        const SizedBox(height: 12),
        _label(tr('पुरवठादार · Supplier *')),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: app.suppliers.any((s) => s.id == _supplierId) ? _supplierId : null,
          items: [
            for (final s in app.suppliers.where((s) => s.active))
              DropdownMenuItem(value: s.id, child: Text(s.name)),
          ],
          hint: Text(tr('निवडा · Select')),
          onChanged: (v) => setState(() => _supplierId = v),
        ),
        if (app.suppliers.where((s) => s.active).isEmpty) ...[
          const SizedBox(height: 4),
          Text(tr('कोणतेही पुरवठादार नाहीत · No suppliers yet — add one under More → Suppliers.'),
              style: TextStyle(fontSize: 11, color: c.muted)),
        ],
        const SizedBox(height: 12),
        _field(
            tr('बॅच क्र. · Batch no.${product?.batchTrackingEnabled ?? true ? ' *' : ' (optional)'}'),
            _batch),
        Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                _label(tr('प्रकार · Unit')),
                SegmentedButton<_Unit>(
                  segments: [
                    ButtonSegment(value: _Unit.bags, label: Text(tr('गोणी · Bags'))),
                    ButtonSegment(value: _Unit.loose, label: Text(tr('सुटे · Loose'))),
                  ],
                  selected: {_unit},
                  onSelectionChanged: (s) => setState(() => _unit = s.first),
                ),
              ])),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _field(
                  _unit == _Unit.bags ? tr('गोणी संख्या · Bags qty') : 'सुटे वजन (kg) · Loose kg',
                  _qty,
                  number: true)),
          const SizedBox(width: 11),
          Expanded(
              child: _field(tr('खरेदी भाव/गोणी · Cost/bag'), _cost, number: true, prefix: '₹')),
        ]),
        _dateField(context,
            required: product?.expiryTrackingEnabled ?? true),
        const SizedBox(height: 8),
        BigButton.brand(_busy ? tr('जोडत आहे... · Adding...') : tr('📦 साठा जोडा · Add stock'),
            onTap: _busy ? null : () => _submit(app, product)),
      ]),
    );
  }

  Future<void> _submit(AppState app, Product? product) async {
    if (_branchId == null) {
      showToast(context, tr('शाखा निवडा · Pick a branch'));
      return;
    }
    if (_pid == null || product == null) {
      showToast(context, tr('उत्पादन निवडा · Pick a product'));
      return;
    }
    if (_supplierId == null) {
      showToast(context, tr('पुरवठादार निवडा · Pick a supplier'));
      return;
    }
    final qty = double.tryParse(_qty.text) ?? 0;
    if (qty <= 0) {
      showToast(context, tr('योग्य प्रमाण टाका · Enter a valid quantity'));
      return;
    }
    if (product.batchTrackingEnabled && _batch.text.trim().isEmpty) {
      showToast(context, tr('बॅच क्र. टाका · Enter a batch number'));
      return;
    }
    if (product.expiryTrackingEnabled && _expiry == null) {
      showToast(context, tr('एक्सपायरी निवडा · Pick an expiry date'));
      return;
    }
    final cost = _cost.text.trim().isEmpty ? null : double.tryParse(_cost.text);
    if (_cost.text.trim().isNotEmpty && cost == null) {
      showToast(context, tr('योग्य किंमत टाका · Enter a valid cost'));
      return;
    }

    setState(() => _busy = true);
    try {
      await app.stockIn(
        branchId: _branchId!,
        productId: _pid!,
        supplierId: _supplierId!,
        batchNo: _batch.text.trim().isEmpty ? null : _batch.text.trim(),
        expiry: _expiry,
        cost: cost,
        bags: _unit == _Unit.bags ? qty.round() : 0,
        looseKg: _unit == _Unit.loose ? qty : 0,
      );
      if (mounted) {
        showToast(context, tr('साठा जोडला · Stock added'));
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        showToast(context, tr('साठा जोडता आला नाही · Could not add stock'));
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

  Widget _field(String label, TextEditingController ctrl,
          {bool number = false, String? prefix}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(label),
          TextField(
              controller: ctrl,
              keyboardType: number
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(prefixText: prefix)),
        ]),
      );

  Widget _dateField(BuildContext context, {required bool required}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(tr('एक्सपायरी · Expiry${required ? ' *' : ' (optional)'}')),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                  initialDate: DateTime.now().add(const Duration(days: 90)));
              if (d != null) setState(() => _expiry = d);
            },
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                  color: context.c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.c.line, width: 1.5)),
              child: Text(_expiry == null ? L('निवडा', 'Select') : dayShort(_expiry!),
                  style: TextStyle(
                      color: _expiry == null ? context.c.muted : context.c.ink,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      );
}
