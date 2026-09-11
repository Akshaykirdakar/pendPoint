import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

class ProductEditScreen extends StatefulWidget {
  final String? productId;
  final String? brandId;
  const ProductEditScreen({this.productId, this.brandId, super.key});
  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  late String _brandId;
  final _nameMr = TextEditingController();
  final _nameEn = TextEditingController();
  final _bagWt = TextEditingController(text: '50');
  final _thr = TextEditingController();
  final _bagPrice = TextEditingController();
  final _kgPrice = TextEditingController();
  final _cost = TextEditingController();
  final _floor = TextEditingController();

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final p =
        widget.productId != null ? app.productOf(widget.productId!) : null;
    _brandId = p?.brandId ?? widget.brandId ?? app.brands.first.id;
    _thr.text = '${app.settings.lowDefaultBags}';
    if (p != null) {
      _nameMr.text = p.nameMr;
      _nameEn.text = p.name;
      _bagWt.text = '${p.bagWeightKg}';
      _thr.text = '${p.lowStockThresholdBags}';
      _bagPrice.text = p.fullBagPrice.toStringAsFixed(0);
      _kgPrice.text = p.perKgPrice.toStringAsFixed(0);
      _cost.text = p.costPrice.toStringAsFixed(0);
      _floor.text = p.minPriceFloor.toStringAsFixed(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final editing = widget.productId != null;
    return PendScaffold(
      titleMr: editing ? 'उत्पादन संपादन' : 'नवीन उत्पादन',
      titleEn: editing ? 'Edit product' : 'New product',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label('ब्रँड · Brand'),
        DropdownButtonFormField<String>(
            initialValue: _brandId,
            items: [
              for (final b in app.brands)
                DropdownMenuItem(value: b.id, child: Text(b.name))
            ],
            onChanged: (v) => setState(() => _brandId = v ?? _brandId)),
        const SizedBox(height: 12),
        _f('नाव (मराठी) · Name', _nameMr),
        _f('Name (English)', _nameEn),
        Row(children: [
          Expanded(child: _f('गोणी वजन kg · Bag wt', _bagWt, num: true)),
          const SizedBox(width: 11),
          Expanded(child: _f('निम्न मर्यादा गोणी · Low@bags', _thr, num: true))
        ]),
        Row(children: [
          Expanded(
              child: _f('गोणी भाव · Bag price', _bagPrice,
                  num: true, prefix: '₹')),
          const SizedBox(width: 11),
          Expanded(
              child:
                  _f('प्रति किलो · Per kg', _kgPrice, num: true, prefix: '₹'))
        ]),
        Row(children: [
          Expanded(
              child: _f('खरेदी भाव · Cost', _cost, num: true, prefix: '₹')),
          const SizedBox(width: 11),
          Expanded(
              child: _f('किमान भाव · Floor', _floor, num: true, prefix: '₹'))
        ]),
        const SizedBox(height: 6),
        BigButton.brand('जतन करा · Save', onTap: () => _save(context, app)),
        if (editing) ...[
          const SizedBox(height: 10),
          BigButton.danger('🗑 काढून टाका · Delete',
              onTap: () => _delete(context, app)),
        ],
      ]),
    );
  }

  Future<void> _save(BuildContext context, AppState app) async {
    if (_nameMr.text.trim().isEmpty && _nameEn.text.trim().isEmpty) {
      showToast(context, 'नाव टाका · Enter a name');
      return;
    }
    await app.saveProduct(
      id: widget.productId,
      brandId: _brandId,
      nameMr: _nameMr.text.trim().isEmpty
          ? _nameEn.text.trim()
          : _nameMr.text.trim(),
      name: _nameEn.text.trim().isEmpty
          ? _nameMr.text.trim()
          : _nameEn.text.trim(),
      bagWeightKg: int.tryParse(_bagWt.text) ?? 50,
      fullBagPrice: double.tryParse(_bagPrice.text) ?? 0,
      perKgPrice: double.tryParse(_kgPrice.text) ?? 0,
      costPrice: double.tryParse(_cost.text) ?? 0,
      minPriceFloor: double.tryParse(_floor.text) ?? 0,
      lowThreshold: int.tryParse(_thr.text),
    );
    if (context.mounted) {
      showToast(context, 'उत्पादन जतन · Product saved');
      Navigator.pop(context);
    }
  }

  void _delete(BuildContext context, AppState app) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.c.surface,
        title: const Text('Delete product?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: context.c.critical),
              onPressed: () async {
                await app.deleteProduct(widget.productId!);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('काढा')),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 5),
      child: Text(t,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.c.ink2)));
  Widget _f(String label, TextEditingController ctrl,
          {bool num = false, String? prefix}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(label),
          TextField(
              controller: ctrl,
              keyboardType: num ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(prefixText: prefix)),
        ]),
      );
}
