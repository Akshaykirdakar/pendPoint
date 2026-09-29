import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/brand.dart';
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../utils/theme.dart';
import '../../utils/lang.dart';

/// "＋ नवीन ब्रँड जोडा" — a one-field form opened from the Brand picker.
/// Returns the created brand (already saved), or null when cancelled.
Future<Brand?> showBrandForm(BuildContext context, AppState app,
    {String initialName = ''}) {
  final name = TextEditingController(text: initialName);
  final nameMr = TextEditingController();
  String? error;
  var busy = false;
  return showDialog<Brand>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      Future<void> save() async {
        setSt(() => busy = true);
        final res = await app.createBrand(name: name.text, nameMr: nameMr.text);
        if (!ctx.mounted) return;
        if (res.ok) {
          Navigator.pop(ctx, res.value);
        } else {
          setSt(() {
            busy = false;
            error = tr(res.error!);
          });
        }
      }

      return AlertDialog(
        backgroundColor: ctx.c.surface,
        title: Text(L('नवीन ब्रँड जोडा', 'Add New Brand'),
            style: baloo(size: 18, weight: FontWeight.w700, color: ctx.c.ink)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const ValueKey('brand-form-name'),
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                  labelText: L('ब्रँडचे नाव *', 'Brand name *')),
              onSubmitted: (_) => busy ? null : save(),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('brand-form-name-mr'),
              controller: nameMr,
              decoration: InputDecoration(
                  labelText:
                      L('मराठी नाव (ऐच्छिक)', 'Marathi name (optional)')),
            ),
            if (error != null) _FormError(error!),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(L('रद्द', 'Cancel'))),
          FilledButton(
              key: const ValueKey('brand-form-save'),
              onPressed: busy ? null : save,
              child: Text(L('ब्रँड जतन करा', 'Save Brand'))),
        ],
      );
    }),
  );
}

/// "＋ नवीन उत्पादन जोडा" — the minimum product master fields, opened from
/// the Product picker. [brandId] pre-selects the brand (still changeable);
/// a brand is always required so no product is ever created without one.
Future<Product?> showProductForm(BuildContext context, AppState app,
    {String? brandId, String initialName = ''}) {
  String? brand =
      brandId ?? (app.brands.length == 1 ? app.brands.first.id : null);
  final name = TextEditingController(text: initialName);
  final nameMr = TextEditingController();
  final weight = TextEditingController(text: '50');
  final bagPrice = TextEditingController();
  final kgPrice = TextEditingController();
  final cost = TextEditingController();
  String? error;
  var busy = false;
  final numOnly = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

  return showDialog<Product>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      Future<void> save() async {
        setSt(() => busy = true);
        final res = await app.createProduct(
          brandId: brand,
          name: name.text,
          nameMr: nameMr.text,
          bagWeightKg: int.tryParse(weight.text.trim()) ?? 0,
          fullBagPrice: double.tryParse(bagPrice.text.trim()) ?? 0,
          perKgPrice: double.tryParse(kgPrice.text.trim()),
          costPrice: double.tryParse(cost.text.trim()) ?? 0,
        );
        if (!ctx.mounted) return;
        if (res.ok) {
          Navigator.pop(ctx, res.value);
        } else {
          setSt(() {
            busy = false;
            error = tr(res.error!);
          });
        }
      }

      Widget field(String key, TextEditingController c, String label,
              {bool number = false, String? prefix}) =>
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              key: ValueKey(key),
              controller: c,
              keyboardType: number
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              inputFormatters: number ? numOnly : null,
              decoration: InputDecoration(labelText: label, prefixText: prefix),
            ),
          );

      return AlertDialog(
        backgroundColor: ctx.c.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(L('नवीन उत्पादन जोडा', 'Add New Product'),
            style: baloo(size: 18, weight: FontWeight.w700, color: ctx.c.ink)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DropdownButtonFormField<String>(
                key: const ValueKey('product-form-brand'),
                isExpanded: true,
                initialValue: brand,
                decoration: InputDecoration(labelText: L('ब्रँड *', 'Brand *')),
                items: [
                  for (final b in app.brands)
                    if (b.active || b.id == brand)
                      DropdownMenuItem(value: b.id, child: Text(b.name)),
                ],
                onChanged: (v) => setSt(() => brand = v),
              ),
            ),
            field('product-form-name', name,
                L('उत्पादनाचे नाव *', 'Product name *')),
            field('product-form-name-mr', nameMr,
                L('मराठी नाव (ऐच्छिक)', 'Marathi name (optional)')),
            field('product-form-weight', weight,
                L('गोणीचे वजन (किलो) *', 'Bag weight (kg) *'),
                number: true),
            field('product-form-bag-price', bagPrice,
                L('विक्री भाव / गोणी *', 'Selling price / bag *'),
                number: true, prefix: '₹'),
            field(
                'product-form-kg-price',
                kgPrice,
                L('विक्री भाव / किलो (ऐच्छिक)',
                    'Selling price / kg (optional)'),
                number: true,
                prefix: '₹'),
            field(
                'product-form-cost',
                cost,
                L('खरेदी भाव / गोणी (ऐच्छिक)',
                    'Purchase rate / bag (optional)'),
                number: true,
                prefix: '₹'),
            if (error != null) _FormError(error!),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(L('रद्द', 'Cancel'))),
          FilledButton(
              key: const ValueKey('product-form-save'),
              onPressed: busy ? null : save,
              child: Text(L('उत्पादन जतन करा', 'Save Product'))),
        ],
      );
    }),
  );
}

class _FormError extends StatelessWidget {
  final String text;
  const _FormError(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline_rounded,
              size: 18, color: context.c.critical),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                key: const ValueKey('master-form-error'),
                style: TextStyle(
                    color: context.c.critical, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}
