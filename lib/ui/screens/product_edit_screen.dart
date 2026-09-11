import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../services/product_photo_service.dart';
import '../../state/app_state.dart';
import '../../utils/marathi_transliteration.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

class ProductEditScreen extends StatefulWidget {
  final String? productId, brandId;
  const ProductEditScreen({this.productId, this.brandId, super.key});
  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  late String _brand;
  final en = TextEditingController(),
      mr = TextEditingController(),
      wt = TextEditingController(text: '50'),
      threshold = TextEditingController(),
      bag = TextEditingController(),
      kg = TextEditingController(),
      cost = TextEditingController(),
      floor = TextEditingController();
  Timer? debounce;
  Uint8List? image;
  String? imageName, oldUrl;
  bool manualMr = false, remove = false, busy = false;
  @override
  void initState() {
    super.initState();
    final a = context.read<AppState>();
    final p = widget.productId == null ? null : a.productOf(widget.productId!);
    _brand = p?.brandId ?? widget.brandId ?? a.brands.first.id;
    threshold.text = '${a.settings.lowDefaultBags}';
    if (p != null) {
      en.text = p.name;
      mr.text = p.nameMr;
      wt.text = '${p.bagWeightKg}';
      threshold.text = '${p.lowStockThresholdBags}';
      bag.text = p.fullBagPrice.toString();
      kg.text = p.perKgPrice.toString();
      cost.text = p.costPrice.toString();
      floor.text = p.minPriceFloor.toString();
      oldUrl = p.photoUrl;
    }
    en.addListener(_autoMr);
    mr.addListener(() => manualMr = true);
  }

  void _autoMr() {
    if (manualMr) return;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 500), _generate);
  }

  void _generate() {
    if (en.text.trim().isNotEmpty) {
      mr.removeListener(() => manualMr = true);
      mr.text = transliterateMarathi(en.text.trim());
      manualMr = false;
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    for (final c in [en, mr, wt, threshold, bag, kg, cost, floor]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppState>(), edit = widget.productId != null;
    return PendScaffold(
        titleMr: edit ? 'उत्पादन संपादन' : 'नवीन उत्पादन',
        titleEn: edit ? 'Edit product' : 'New product',
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('ब्रँड · Brand'),
          DropdownButtonFormField<String>(
              initialValue: _brand,
              items: [
                for (final b in a.brands)
                  DropdownMenuItem(value: b.id, child: Text(b.name))
              ],
              onChanged:
                  busy ? null : (v) => setState(() => _brand = v ?? _brand)),
          const SizedBox(height: 12),
          _photo(),
          _f('Name (English)', en),
          Row(children: [
            Expanded(child: _label('मराठी नाव · Marathi Name')),
            TextButton(
                onPressed: busy ? null : _generate,
                child: const Text('Generate Marathi'))
          ]),
          _f('', mr),
          Row(children: [
            Expanded(child: _f('गोणी वजन · Bag wt', wt, num: true)),
            const SizedBox(width: 10),
            Expanded(child: _f('Low bags', threshold, num: true))
          ]),
          Row(children: [
            Expanded(child: _f('Bag price', bag, num: true, prefix: '₹')),
            const SizedBox(width: 10),
            Expanded(child: _f('Per kg', kg, num: true, prefix: '₹'))
          ]),
          Row(children: [
            Expanded(child: _f('Cost', cost, num: true, prefix: '₹')),
            const SizedBox(width: 10),
            Expanded(child: _f('Floor', floor, num: true, prefix: '₹'))
          ]),
          BigButton.brand(busy ? 'Saving...' : 'जतन करा · Save',
              onTap: busy ? null : () => _save(a)),
          if (edit) ...[
            const SizedBox(height: 10),
            BigButton.danger('🗑 Delete', onTap: busy ? null : () => _delete(a))
          ]
        ]));
  }

  Widget _photo() => Container(
      decoration: cardDecoration(context),
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        SizedBox(
            width: 70,
            height: 70,
            child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: image != null
                    ? Image.memory(image!, fit: BoxFit.cover)
                    : (oldUrl != null && !remove
                        ? Image.network(oldUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.image_not_supported_outlined))
                        : const Icon(Icons.image_outlined, size: 32)))),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Product photo'),
          Wrap(children: [
            TextButton(
                onPressed: busy ? null : _pick,
                child: Text(image == null && oldUrl == null
                    ? 'Add Photo'
                    : 'Change Photo')),
            if (image != null || oldUrl != null)
              TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                            image = null;
                            remove = true;
                          }),
                  child: const Text('Remove Photo'))
          ])
        ]))
      ]));
  Future<void> _pick() async {
    try {
      final x = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1600, imageQuality: 82);
      if (x == null) return;
      final data = await x.readAsBytes();
      if (data.isEmpty) throw StateError('Empty image');
      setState(() {
        image = data;
        imageName = x.name;
        remove = false;
      });
    } catch (_) {
      if (mounted) {
        showToast(
            context, 'फोटो निवडता आला नाही · Unable to select product photo');
      }
    }
  }

  Future<void> _save(AppState a) async {
    if (en.text.trim().isEmpty && mr.text.trim().isEmpty) {
      showToast(context, 'नाव टाका · Enter a name');
      return;
    }
    setState(() => busy = true);
    try {
      var p = await a.saveProduct(
          id: widget.productId,
          brandId: _brand,
          name: en.text.trim().isEmpty ? mr.text.trim() : en.text.trim(),
          nameMr: mr.text.trim().isEmpty ? en.text.trim() : mr.text.trim(),
          bagWeightKg: int.tryParse(wt.text) ?? 50,
          fullBagPrice: double.tryParse(bag.text) ?? 0,
          perKgPrice: double.tryParse(kg.text) ?? 0,
          costPrice: double.tryParse(cost.text) ?? 0,
          minPriceFloor: double.tryParse(floor.text) ?? 0,
          lowThreshold: int.tryParse(threshold.text));
      if (image != null) {
        final url = await ProductPhotoService().upload(
            productId: p.id,
            bytes: image!,
            extension: (imageName ?? 'image.jpg').split('.').last);
        p = await a.saveProduct(
            id: p.id,
            brandId: p.brandId,
            name: p.name,
            nameMr: p.nameMr,
            bagWeightKg: p.bagWeightKg,
            fullBagPrice: p.fullBagPrice,
            perKgPrice: p.perKgPrice,
            costPrice: p.costPrice,
            minPriceFloor: p.minPriceFloor,
            lowThreshold: p.lowStockThresholdBags,
            photoUrl: url);
        if (oldUrl != null) {
          try {
            await ProductPhotoService().deleteUrl(oldUrl);
          } catch (_) {}
        }
      } else if (remove && oldUrl != null) {
        await a.saveProduct(
            id: p.id,
            brandId: p.brandId,
            name: p.name,
            nameMr: p.nameMr,
            bagWeightKg: p.bagWeightKg,
            fullBagPrice: p.fullBagPrice,
            perKgPrice: p.perKgPrice,
            costPrice: p.costPrice,
            minPriceFloor: p.minPriceFloor,
            lowThreshold: p.lowStockThresholdBags,
            photoUrl: null);
        try {
          await ProductPhotoService().deleteUrl(oldUrl);
        } catch (_) {}
      }
      if (mounted) {
        showToast(context, 'उत्पादन जतन · Product saved');
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        showToast(
            context, 'उत्पादन जतन करता आले नाही · Unable to save product');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _delete(AppState a) => showDialog(
      context: context,
      builder: (x) =>
          AlertDialog(title: const Text('Delete product?'), actions: [
            TextButton(
                onPressed: () => Navigator.pop(x), child: const Text('Cancel')),
            FilledButton(
                onPressed: () async {
                  await a.deleteProduct(widget.productId!);
                  if (x.mounted) Navigator.pop(x);
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('Delete'))
          ]));
  Widget _label(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(s,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.c.ink2)));
  Widget _f(String s, TextEditingController c,
          {bool num = false, String? prefix}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (s.isNotEmpty) _label(s),
            TextField(
                controller: c,
                keyboardType: num
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
                decoration: InputDecoration(prefixText: prefix))
          ]));
}
