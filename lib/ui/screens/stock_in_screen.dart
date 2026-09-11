import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

class StockInScreen extends StatefulWidget {
  final String? productId;
  const StockInScreen({this.productId, super.key});
  @override
  State<StockInScreen> createState() => _StockInScreenState();
}

class _StockInScreenState extends State<StockInScreen> {
  late String _pid;
  final _bags = TextEditingController(text: '10');
  final _cost = TextEditingController();
  final _batch = TextEditingController();
  final _supplier = TextEditingController();
  DateTime? _expiry;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _pid = widget.productId ?? app.products.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return PendScaffold(
      titleMr: 'साठा भरा',
      titleEn: 'Stock in',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            'नवीन खरेदी नोंदवा · Record a purchase. Batch & expiry are optional but recommended for feed.',
            style: TextStyle(color: context.c.ink2, fontSize: 13)),
        const SizedBox(height: 14),
        _label('उत्पादन · Product'),
        DropdownButtonFormField<String>(
          initialValue: _pid,
          items: [
            for (final p in app.products)
              DropdownMenuItem(
                  value: p.id,
                  child: Text('${p.nameMr} · ${p.name}',
                      overflow: TextOverflow.ellipsis))
          ],
          onChanged: (v) => setState(() => _pid = v ?? _pid),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _field('गोणी · Bags in', _bags, number: true)),
          const SizedBox(width: 11),
          Expanded(
              child: _field('खरेदी भाव/गोणी · Cost/bag', _cost,
                  number: true, prefix: '₹')),
        ]),
        Row(children: [
          Expanded(child: _field('बॅच क्र. · Batch no.', _batch)),
          const SizedBox(width: 11),
          Expanded(child: _dateField(context)),
        ]),
        _field('पुरवठादार · Supplier', _supplier),
        const SizedBox(height: 8),
        BigButton.brand('📦 साठा जोडा · Add to stock', onTap: () async {
          final bags = int.tryParse(_bags.text) ?? 0;
          if (bags <= 0) {
            showToast(context, 'गोणी संख्या टाका · Enter bags');
            return;
          }
          await app.stockIn(_pid, bags,
              cost: double.tryParse(_cost.text),
              batch: _batch.text.isEmpty ? null : _batch.text,
              expiry: _expiry,
              supplier: _supplier.text.isEmpty ? null : _supplier.text);
          if (context.mounted) {
            showToast(context, '$bags गोणी जोडल्या · Stock added');
            Navigator.pop(context);
          }
        }),
      ]),
    );
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
              keyboardType: number ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(prefixText: prefix)),
        ]),
      );

  Widget _dateField(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('एक्सपायरी · Expiry'),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 1000)),
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
              child: Text(_expiry == null ? 'निवडा' : dayShort(_expiry!),
                  style: TextStyle(
                      color: _expiry == null ? context.c.muted : context.c.ink,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      );
}
