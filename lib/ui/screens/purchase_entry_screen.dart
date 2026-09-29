import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../state/app_state.dart';
import '../../state/purchase_draft.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../widgets/pickers.dart';
import '../widgets/search_picker.dart';
import 'purchase_detail_screen.dart';
import '../../utils/lang.dart';

/// One editable row of the purchase grid.
class _Row {
  String? productId;
  String? brandId; // optional filter for the product search
  final bags = TextEditingController();
  final rate = TextEditingController();
  final batch = TextEditingController();
  DateTime? expiry;
  final bagsFocus = FocusNode();
  final rateFocus = FocusNode();
  final batchFocus = FocusNode();

  bool get isBlank =>
      productId == null &&
      bags.text.trim().isEmpty &&
      rate.text.trim().isEmpty &&
      batch.text.trim().isEmpty;

  PurchaseLineInput toInput() => PurchaseLineInput(
        productId: productId,
        bags: int.tryParse(bags.text.trim()) ?? 0,
        rate: double.tryParse(rate.text.trim()) ?? 0,
        batchNo: batch.text.trim(),
        expiry: expiry,
      );

  void dispose() {
    bags.dispose();
    rate.dispose();
    batch.dispose();
    bagsFocus.dispose();
    rateFocus.dispose();
    batchFocus.dispose();
  }
}

/// Purchase Entry — one supplier bill with many products/bags. There is
/// always one empty row at the bottom; picking a product in it jumps
/// straight to Bags → Rate → (Batch/Expiry when the product tracks them) →
/// the next row's product search, so a whole bill can be keyed in without
/// hunting for an "Add" button. Running subtotal / other charges / grand
/// total sit right under the rows, with Save pinned at the bottom.
class PurchaseEntryScreen extends StatefulWidget {
  /// Correct an existing purchase (saved as a new revision).
  final String? editPurchaseId;

  /// Start with this product already on the first row.
  final String? productId;

  const PurchaseEntryScreen({this.editPurchaseId, this.productId, super.key});

  /// Test hook: replaces the camera/gallery picker (image_picker needs a
  /// real device). Returns the picked image bytes and file name.
  @visibleForTesting
  static Future<({Uint8List bytes, String name})?> Function(ImageSource)?
      debugPickPhoto;

  @override
  State<PurchaseEntryScreen> createState() => _PurchaseEntryScreenState();
}

class _PurchaseEntryScreenState extends State<PurchaseEntryScreen> {
  final List<_Row> _rows = [];
  final _billNo = TextEditingController();
  final _other = TextEditingController(text: '0');
  String? _supplierId;
  DateTime _date = DateTime.now();
  bool _busy = false;

  // Supplier-bill photo: a newly picked one, or the saved one (edit) unless
  // the user removed it.
  Uint8List? _photo;
  String _photoExt = 'jpg';
  bool _photoRemoved = false;
  Future<Uint8List?>? _savedPhoto; // loaded once for the preview

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final edit = widget.editPurchaseId == null
        ? null
        : app.purchaseOf(widget.editPurchaseId!);
    if (edit != null) {
      _supplierId = edit.supplierId;
      _billNo.text = edit.supplierBillNo;
      _date = edit.purchaseDate;
      _other.text = _num(edit.otherCharges);
      for (final it in edit.items) {
        final r = _Row()
          ..productId = it.productId
          ..brandId = it.brandId
          ..expiry = it.expiry;
        r.bags.text = '${it.bags}';
        r.rate.text = _num(it.rate);
        r.batch.text = it.batchNo;
        _rows.add(r);
      }
    } else if (widget.productId != null) {
      final p = app.productOf(widget.productId!);
      if (p != null) {
        final r = _Row()
          ..productId = p.id
          ..brandId = p.brandId;
        r.rate.text = _defaultRate(app, p);
        _rows.add(r);
      }
    }
    _ensureTrailingBlank();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _billNo.dispose();
    _other.dispose();
    super.dispose();
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// Last purchase rate paid for this product (latest batch cost), else the
  /// catalogue cost price. Never the selling price.
  String _defaultRate(AppState app, Product p) {
    final last = app.batches
        .where((b) => b.productId == p.id && b.unitCost > 0)
        .sorted((a, b) => b.updatedAt.compareTo(a.updatedAt))
        .firstOrNull;
    final v = last?.unitCost ?? p.costPrice;
    return v > 0 ? _num(v) : '';
  }

  void _ensureTrailingBlank() {
    if (_rows.isEmpty || !_rows.last.isBlank) _rows.add(_Row());
  }

  List<PurchaseLineInput> get _inputs => [for (final r in _rows) r.toInput()];

  double get _otherCharges => double.tryParse(_other.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final editing = widget.editPurchaseId == null
        ? null
        : app.purchaseOf(widget.editPurchaseId!);
    final supplier = _supplierId == null ? null : app.partyOf(_supplierId!);
    final totals = PurchaseTotals.of(_inputs, otherCharges: _otherCharges);

    return PendScaffold(
      titleMr: editing == null
          ? 'खरेदी नोंद'
          : 'खरेदी दुरुस्त #${editing.purchaseNumber}',
      titleEn: editing == null ? 'Purchase entry' : 'Edit purchase',
      bottomBar: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${tr('एकूण · Grand total')}  🛍️ ${totals.bags}',
                    style: TextStyle(fontSize: 11.5, color: c.ink2)),
                Text(money(totals.grandTotal),
                    key: const ValueKey('purchase-grand-total'),
                    style: baloo(
                        size: 21, weight: FontWeight.w800, color: c.brand)),
              ]),
        ),
        SizedBox(
          width: 170,
          child: BigButton.brand(_busy ? 'जतन...' : tr('💾 खरेदी सेव्ह · Save'),
              key: const ValueKey('purchase-save'),
              onTap: _busy ? null : () => _save(app)),
        ),
      ]),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PickerField(
          key: const ValueKey('purchase-party'),
          label: tr('खरेदी पार्टी · Purchase party *'),
          icon: Icons.local_shipping_rounded,
          value: supplier == null
              ? null
              : '${supplier.code.isEmpty ? '' : '${supplier.code} · '}${supplier.name}'
                  '${supplier.mobile.isEmpty ? '' : ' · ${supplier.mobile}'}',
          placeholder: tr('कोड / नाव / मोबाइल शोधा · Search code, name, mobile'),
          onTap: () async {
            final p = await pickParty(context, app, purchase: true);
            if (p != null) setState(() => _supplierId = p.id);
          },
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _billNo,
              decoration: InputDecoration(
                  labelText: tr('पुरवठादार बिल क्र. · Supplier bill no.')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final d = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    initialDate: _date);
                if (d != null) setState(() => _date = d);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                    labelText: tr('खरेदी दिनांक · Date'),
                    prefixIcon: Icon(Icons.event_rounded, size: 20)),
                child: Text(dayFull(_date),
                    style:
                        TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
              ),
            ),
          ),
        ]),
        SectionHeader(
            tr('उत्पादने · Products (${_rows.where((r) => !r.isBlank).length})')),
        if (_rows.every((r) => r.productId == null))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                '⚠️ ${L('खरेदीमध्ये किमान एक उत्पादन जोडा', 'Add at least one product to the purchase')}',
                key: const ValueKey('purchase-empty-hint'),
                style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
          ),
        for (var i = 0; i < _rows.length; i++) ...[
          _rowCard(context, app, i),
          const SizedBox(height: 10),
        ],
        _totalsCard(context, totals),
        const SizedBox(height: 12),
        _photoCard(context, app, editing?.hasBillPhoto == true ? editing : null),
      ]),
    );
  }

  Widget _rowCard(BuildContext context, AppState app, int i) {
    final c = context.c;
    final r = _rows[i];
    final p = r.productId == null ? null : app.productOf(r.productId!);
    final isNext = r.isBlank && i == _rows.length - 1;
    final line = r.toInput();

    return Container(
      decoration: cardDecoration(context,
          color: isNext ? c.surface2 : null, radius: 14),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(
              radius: 13,
              backgroundColor: c.brand.withValues(alpha: 0.14),
              child: Text(isNext ? '＋' : '${i + 1}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: c.brand))),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  isNext
                      ? tr('＋ आणखी उत्पादन · Add Another Product')
                      : tr('ओळ · Row ${i + 1}'),
                  style:
                      TextStyle(fontWeight: FontWeight.w700, color: c.ink2))),
          if (!isNext)
            IconButton(
              key: ValueKey('purchase-row-$i-remove'),
              tooltip: tr('ओळ काढा · Remove row'),
              icon: Icon(Icons.delete_outline_rounded, color: c.critical),
              onPressed: () => setState(() {
                _rows.removeAt(i).dispose();
                _ensureTrailingBlank();
              }),
            ),
        ]),
        const SizedBox(height: 6),
        // Brand and Product are two separate fields: the Brand narrows the
        // Product search ("All Brands" = no restriction); a product from
        // another brand is cleared when the brand changes.
        Padding(
          padding: const EdgeInsets.only(right: 6, bottom: 8),
          child: BrandField(
            key: ValueKey('purchase-row-$i-brand'),
            app: app,
            brandId: r.brandId,
            allowCreate: true,
            onChanged: (id) => setState(() {
              r.brandId = id;
              if (id != null && p != null && p.brandId != id) {
                r.productId = null;
              }
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: PickerField(
            key: ValueKey('purchase-row-$i-product'),
            label: tr('उत्पादन · Product'),
            value: p == null ? null : '${p.nameMr} · ${p.name}',
            placeholder: tr('उत्पादन शोधा · Search product'),
            onTap: () => _pickProductFor(app, r),
          ),
        ),
        if (p != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 6, 0),
            child: Text(
                '${app.brandOf(p.brandId)?.name ?? ''} · ${p.bagWeightKg}kg · '
                '${L('विक्री भाव', 'Selling')} ${money(p.fullBagPrice)} · '
                '${L('साठा', 'Stock')} 🛍️ ${app.stockOf(p.id).bags}',
                style: TextStyle(fontSize: 11.5, color: c.muted)),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(children: [
              Expanded(
                flex: 4,
                child: TextField(
                  key: ValueKey('purchase-row-$i-bags'),
                  controller: r.bags,
                  focusNode: r.bagsFocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: tr('गोणी · Bags')),
                  onChanged: (_) => setState(_ensureTrailingBlank),
                  onSubmitted: (_) => r.rateFocus.requestFocus(),
                ),
              ),
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('×')),
              Expanded(
                flex: 5,
                child: TextField(
                  key: ValueKey('purchase-row-$i-rate'),
                  controller: r.rate,
                  focusNode: r.rateFocus,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                      labelText: tr('खरेदी भाव · Purchase rate'), prefixText: '₹'),
                  onChanged: (_) => setState(_ensureTrailingBlank),
                  onSubmitted: (_) => _afterRate(app, r),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 78,
                child: Text(money(line.amount),
                    key: ValueKey('purchase-row-$i-amount'),
                    textAlign: TextAlign.right,
                    style:
                        baloo(size: 15, weight: FontWeight.w800, color: c.ink)),
              ),
            ]),
          ),
          if (p.batchTrackingEnabled ||
              p.expiryTrackingEnabled ||
              r.batch.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('purchase-row-$i-batch'),
                    controller: r.batch,
                    focusNode: r.batchFocus,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                        labelText:
                            tr('बॅच क्र. · Batch${p.batchTrackingEnabled ? ' *' : ''}')),
                    onChanged: (_) => setState(_ensureTrailingBlank),
                    onSubmitted: (_) => _afterBatch(app, r),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _pickExpiry(r),
                    child: InputDecorator(
                      decoration: InputDecoration(
                          labelText:
                              tr('एक्सपायरी · Expiry${p.expiryTrackingEnabled ? ' *' : ''}')),
                      child: Text(
                          r.expiry == null ? L('निवडा', 'Select') : dayFull(r.expiry!),
                          style: TextStyle(
                              color: r.expiry == null ? c.muted : c.ink,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ]),
    );
  }

  Widget _totalsCard(BuildContext context, PurchaseTotals t) {
    final c = context.c;
    Widget line(String l, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(
                child: Text(l,
                    style: TextStyle(
                        color: bold ? c.ink : c.ink2,
                        fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
            Text(v,
                style: bold
                    ? baloo(size: 19, weight: FontWeight.w800, color: c.brand)
                    : TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
          ]),
        );
    return Container(
      decoration: cardDecoration(context),
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        line('${tr('उप-बेरीज · Subtotal')}  🛍️ ${t.bags}', money(t.subtotal)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
              child: Text(tr('+ इतर खर्च · Other charges'),
                  style: TextStyle(color: c.ink2))),
          SizedBox(
            width: 120,
            child: TextField(
              key: const ValueKey('purchase-other-charges'),
              controller: _other,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  prefixText: '₹', isDense: true, hintText: '0'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
        Text(tr('वाहतूक, हमाली इ. नसल्यास 0 · Transport, loading etc. — 0 if none'),
            style: TextStyle(fontSize: 11, color: c.muted)),
        Divider(height: 20, color: c.line),
        line(tr('= एकूण · Grand total'), money(t.grandTotal), bold: true),
      ]),
    );
  }

  // ---- row flow: product → bags → rate → batch → expiry → next row ----
  Future<void> _pickProductFor(AppState app, _Row r) async {
    final p =
        await pickProduct(context, app, brandId: r.brandId, allowCreate: true);
    if (p == null || !mounted) return;
    setState(() {
      r.productId = p.id;
      r.brandId = p.brandId;
      if (r.rate.text.trim().isEmpty) r.rate.text = _defaultRate(app, p);
      _ensureTrailingBlank();
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => r.bagsFocus.requestFocus());
  }

  void _afterRate(AppState app, _Row r) {
    final p = r.productId == null ? null : app.productOf(r.productId!);
    if (p != null && p.batchTrackingEnabled && r.batch.text.trim().isEmpty) {
      r.batchFocus.requestFocus();
      return;
    }
    _afterBatch(app, r);
  }

  Future<void> _afterBatch(AppState app, _Row r) async {
    final p = r.productId == null ? null : app.productOf(r.productId!);
    if (p != null && p.expiryTrackingEnabled && r.expiry == null) {
      await _pickExpiry(r);
      if (!mounted) return;
    }
    _goToNextRow(app, r);
  }

  /// Opens the product search on the row after [r] (the empty row).
  void _goToNextRow(AppState app, _Row r) {
    FocusScope.of(context).unfocus();
    final i = _rows.indexOf(r);
    if (i < 0 || i + 1 >= _rows.length) return;
    final next = _rows[i + 1];
    if (next.isBlank) _pickProductFor(app, next);
  }

  Future<void> _pickExpiry(_Row r) async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: now.add(const Duration(days: 3650)),
        initialDate: r.expiry ?? now.add(const Duration(days: 90)));
    if (d != null && mounted) setState(() => r.expiry = d);
  }

  Future<void> _save(AppState app) async {
    setState(() => _busy = true);
    final res = await app.savePurchase(
      supplierId: _supplierId,
      supplierBillNo: _billNo.text,
      purchaseDate: _date,
      lines: _inputs,
      otherCharges: _otherCharges,
      editingPurchaseId: widget.editPurchaseId,
      photo: _photo != null
          ? BillPhotoChange.replace(_photo!, _photoExt)
          : _photoRemoved
              ? const BillPhotoChange.remove()
              : const BillPhotoChange.keep(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      showToast(context, res.error ?? tr('त्रुटी · Error'));
      return;
    }
    final p = res.purchase!;
    final next = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.c.surface,
        icon: Icon(Icons.check_circle_rounded, color: ctx.c.good, size: 44),
        title: Text(tr('खरेदी सेव्ह झाली\nPurchase saved'),
            textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _kv(ctx, tr('खरेदी क्र. · No.'),
              '#${p.purchaseNumber}${p.revision > 0 ? ' (Rev ${p.revision})' : ''}'),
          _kv(ctx, tr('पार्टी · Party'), p.supplierName),
          if (p.supplierBillNo.isNotEmpty)
            _kv(ctx, tr('बिल क्र. · Bill no.'), p.supplierBillNo),
          _kv(ctx, tr('दिनांक · Date'), dayFull(p.purchaseDate)),
          _kv(ctx, tr('गोणी · Bags'), '${p.totalBags}'),
          _kv(ctx, tr('एकूण · Total'), money(p.total)),
          const SizedBox(height: 6),
          Text(tr('साठा अद्ययावत झाला · Stock updated'),
              style: TextStyle(color: ctx.c.good, fontWeight: FontWeight.w700)),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'view'),
              child: Text(tr('पहा · View'))),
          if (widget.editPurchaseId == null)
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'new'),
                child: Text(tr('नवीन खरेदी · New'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'done'),
              child: Text(tr('झाले · Done'))),
        ],
      ),
    );
    if (!mounted) return;
    switch (next) {
      case 'view':
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => PurchaseDetailScreen(purchaseId: p.id)));
      case 'new':
        setState(() {
          for (final r in _rows) {
            r.dispose();
          }
          _rows.clear();
          _supplierId = null;
          _billNo.clear();
          _other.text = '0';
          _date = DateTime.now();
          _photo = null;
          _photoRemoved = false;
          _ensureTrailingBlank();
        });
      default:
        Navigator.of(context).pop();
    }
  }

  /// "📷 खरेदी बिल फोटो" — optional photo of the supplier's paper bill:
  /// camera or gallery, preview, replace, remove. [saved] is the purchase
  /// being edited when it already has a photo.
  Widget _photoCard(BuildContext context, AppState app, Purchase? saved) {
    final c = context.c;
    final showSaved = _photo == null && saved != null && !_photoRemoved;
    final has = _photo != null || showSaved;
    Widget preview() {
      if (_photo != null) return Image.memory(_photo!, fit: BoxFit.cover);
      return FutureBuilder<Uint8List?>(
        future: _savedPhoto ??= app.purchaseBillPhoto(saved!),
        builder: (_, snap) => snap.data == null
            ? Icon(Icons.receipt_long_rounded, color: c.muted, size: 34)
            : Image.memory(snap.data!, fit: BoxFit.cover),
      );
    }

    return Container(
      key: const ValueKey('purchase-photo-card'),
      decoration: cardDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('📷 ${L('खरेदी बिल फोटो', 'Purchase Bill Photo')}',
            style: baloo(size: 15, weight: FontWeight.w700, color: c.ink)),
        Text(L('ऐच्छिक — पुरवठादाराच्या बिलाचा फोटो संदर्भासाठी',
                'Optional — a photo of the supplier\'s bill, for reference'),
            style: TextStyle(fontSize: 11.5, color: c.muted)),
        const SizedBox(height: 10),
        if (has) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
                key: const ValueKey('purchase-photo-preview'),
                height: 160,
                child: preview()),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            key: const ValueKey('purchase-photo-camera'),
            onPressed: _busy ? null : () => _pickPhoto(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_rounded),
            label: Text(has ? L('नवीन फोटो काढा', 'Retake') : L('कॅमेरा', 'Camera')),
          ),
          OutlinedButton.icon(
            key: const ValueKey('purchase-photo-gallery'),
            onPressed: _busy ? null : () => _pickPhoto(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_rounded),
            label: Text(has
                ? L('दुसरा फोटो निवडा', 'Replace')
                : L('गॅलरी', 'Gallery')),
          ),
          if (has)
            TextButton.icon(
              key: const ValueKey('purchase-photo-remove'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _photo = null;
                        _photoRemoved = true;
                      }),
              icon: Icon(Icons.delete_outline_rounded, color: c.critical),
              label: Text(L('फोटो काढा', 'Remove'),
                  style: TextStyle(color: c.critical)),
            ),
        ]),
      ]),
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final hook = PurchaseEntryScreen.debugPickPhoto;
      Uint8List? bytes;
      String name = 'bill.jpg';
      if (hook != null) {
        final r = await hook(source);
        bytes = r?.bytes;
        name = r?.name ?? name;
      } else {
        final x = await ImagePicker()
            .pickImage(source: source, maxWidth: 1800, imageQuality: 80);
        if (x == null) return;
        bytes = await x.readAsBytes();
        name = x.name;
      }
      if (bytes == null || bytes.isEmpty || !mounted) return;
      setState(() {
        _photo = bytes;
        _photoExt = name.contains('.') ? name.split('.').last : 'jpg';
        _photoRemoved = false;
      });
    } catch (_) {
      if (mounted) {
        showToast(context,
            L('फोटो घेता आला नाही', 'Could not get the photo — try again'));
      }
    }
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
              child: Text(k,
                  style: TextStyle(color: context.c.ink2, fontSize: 13))),
          Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: context.c.ink))),
        ]),
      );
}

/// Status pill shared by purchase list/detail screens.
class PurchaseStatusPill extends StatelessWidget {
  final BillStatus status;
  final bool replaced;
  const PurchaseStatusPill(this.status, {this.replaced = false, super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final voided = status == BillStatus.voided;
    final color = voided ? (replaced ? c.muted : c.critical) : c.good;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999)),
      child: Text(
          voided
              ? (replaced ? tr('दुरुस्त · Edited') : tr('रद्द · Void'))
              : tr('सेव्ह · Saved'),
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
