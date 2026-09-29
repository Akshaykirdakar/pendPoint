import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../models/enums.dart';
import '../../state/app_state.dart';
import '../../state/cart_line.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../widgets/pickers.dart';
import '../widgets/rate_editor.dart';
import '../widgets/search_picker.dart';
import 'checkout_screen.dart';
import '../../utils/lang.dart';

/// Sales bill entry as rows — party at the top, one row per product, and an
/// always-present empty row at the bottom. Picking a product adds the row
/// and jumps to its quantity; pressing Next/Enter on the quantity opens the
/// product search for the following row. Works on the same cart as QR/
/// catalogue selling, so both routes end in the same Checkout.
///
/// Also used to correct a saved bill: [AppState.beginEditBill] loads it
/// into the cart first, and a banner shows which bill is being edited.
class SalesEntryScreen extends StatefulWidget {
  const SalesEntryScreen({super.key});
  @override
  State<SalesEntryScreen> createState() => _SalesEntryScreenState();
}

class _SalesEntryScreenState extends State<SalesEntryScreen> {
  // Keyed by line identity — a row keeps its field while others change.
  final Map<CartLine, TextEditingController> _qty = {};
  final Map<CartLine, FocusNode> _qtyFocus = {};
  String? _brandFilter;

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    for (final f in _qtyFocus.values) {
      f.dispose();
    }
    super.dispose();
  }

  String _fmtQty(CartLine l) => l.isBag
      ? '${l.qty.round()}'
      : l.qty.toString().replaceAll(RegExp(r'\.0$'), '');

  TextEditingController _ctrlFor(CartLine l) {
    final ctrl =
        _qty.putIfAbsent(l, () => TextEditingController(text: _fmtQty(l)));
    final focus = _focusFor(l);
    // Follow changes made elsewhere (cart screen steppers) when not typing.
    if (!focus.hasFocus && double.tryParse(ctrl.text) != l.qty) {
      ctrl.text = _fmtQty(l);
    }
    return ctrl;
  }

  FocusNode _focusFor(CartLine l) => _qtyFocus.putIfAbsent(l, FocusNode.new);

  void _forgetRemovedLines(AppState app) {
    final live = app.cart.toSet();
    for (final l in _qty.keys.where((l) => !live.contains(l)).toList()) {
      _qty.remove(l)!.dispose();
      _qtyFocus.remove(l)?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    _forgetRemovedLines(app);
    final editing = app.editingBillId == null
        ? null
        : app.bills.where((b) => b.id == app.editingBillId).firstOrNull;
    final party =
        app.cartCustomerId == null ? null : app.partyOf(app.cartCustomerId!);

    return PopScope(
      canPop: editing == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscardEdit(context);
        if (discard == true && context.mounted) {
          app.cancelEditBill();
          Navigator.of(context).pop();
        }
      },
      child: PendScaffold(
        titleMr:
            editing == null ? 'बिल नोंद' : 'बिल दुरुस्त #${editing.billNumber}',
        titleEn: editing == null ? 'Sales bill entry' : 'Edit bill',
        bottomBar: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${tr('एकूण · Grand total')}  🧾 ${app.cart.length}',
                      style: TextStyle(fontSize: 11.5, color: c.ink2)),
                  Text(money(app.cartTotal),
                      key: const ValueKey('sales-grand-total'),
                      style: baloo(
                          size: 21, weight: FontWeight.w800, color: c.brand)),
                ]),
          ),
          SizedBox(
            width: 170,
            child: BigButton.primary(tr('पुढे · Payment →'),
                key: const ValueKey('sales-next'),
                onTap: app.cart.isEmpty
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const CheckoutScreen()))),
          ),
        ]),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (editing != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: c.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.warning.withValues(alpha: 0.4))),
              child: Row(children: [
                const Text('✏️ '),
                Expanded(
                  child: Text(
                      'बिल #${editing.billNumber} दुरुस्त करत आहात. सेव्ह केल्यावर जुन्या बिलाचा साठा परत येईल व नवीन बिल लागू होईल.\n'
                      'Editing bill #${editing.billNumber}. On save the old stock is restored and the corrected bill applied.',
                      style: TextStyle(
                          fontSize: 12,
                          color: c.ink,
                          fontWeight: FontWeight.w600)),
                ),
                TextButton(
                    onPressed: () {
                      app.cancelEditBill();
                      Navigator.of(context).pop();
                    },
                    child: Text(tr('रद्द · Cancel'))),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          PickerField(
            key: const ValueKey('sales-party'),
            label: 'पार्टी (उधारसाठी आवश्यक) · Party (needed for credit)',
            icon: Icons.person_search_rounded,
            value: party == null
                ? null
                : '${party.code.isEmpty ? '' : '${party.code} · '}${party.name}'
                    '${party.mobile.isEmpty ? '' : ' · ${party.mobile}'}',
            placeholder: tr('कोड / नाव / मोबाइल शोधा · Search code, name, mobile'),
            onClear: () => app.setCartCustomer(null),
            onTap: () async {
              final p = await pickParty(context, app, purchase: false);
              if (p != null) app.setCartCustomer(p.id);
            },
          ),
          if (party != null && (party.customer?.outstanding ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                  tr('मागील बाकी · Previous due ${money(party.customer!.outstanding)}'),
                  style: TextStyle(
                      fontSize: 12,
                      color: c.serious,
                      fontWeight: FontWeight.w700)),
            ),
          SectionHeader(tr('उत्पादने · Products (${app.cart.length})')),
          for (var i = 0; i < app.cart.length; i++) ...[
            _lineCard(context, app, i),
            const SizedBox(height: 10),
          ],
          _nextRowCard(context, app),
          const SizedBox(height: 12),
          _totalsCard(context, app),
        ]),
      ),
    );
  }

  Widget _lineCard(BuildContext context, AppState app, int i) {
    final c = context.c;
    final l = app.cart[i];
    final p = app.productOf(l.productId);
    if (p == null) return const SizedBox.shrink();
    final next = app.nextSaleBatch(l.productId);
    final available = app.sellableQty(l.productId, l.saleType);
    final short = l.qty > available + 1e-9;

    return Container(
      key: ValueKey('sales-row-$i'),
      decoration: cardDecoration(context, radius: 14),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(
              radius: 13,
              backgroundColor: c.brand.withValues(alpha: 0.14),
              child: Text('${i + 1}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: c.brand))),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () async {
                final np = await pickProduct(context, app);
                if (np != null) app.replaceLineProduct(i, np.id);
              },
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${p.nameMr} · ${p.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: baloo(
                            size: 14.5, weight: FontWeight.w700, color: c.ink)),
                    Text(
                        '${app.brandOf(p.brandId)?.name ?? ''} · '
                        '${next == null ? L('बॅच नाही', 'no batch') : '${L('बॅच', 'Batch')} ${next.batchNo}${next.expiry == null ? '' : ' · ${L('मुदत', 'exp')} ${dayShort(next.expiry!)}'}'}',
                        style: TextStyle(fontSize: 11.5, color: c.ink2)),
                  ]),
            ),
          ),
          IconButton(
            key: ValueKey('sales-row-$i-remove'),
            tooltip: tr('ओळ काढा · Remove row'),
            icon: Icon(Icons.delete_outline_rounded, color: c.critical),
            onPressed: () => app.removeLine(i),
          ),
        ]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Row(children: [
            // One short word per segment (like the bottom tabs), shrunk to
            // fit if a large font size needs it — the field keeps its room.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SegmentedButton<SaleType>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  segments: [
                    ButtonSegment(
                        value: SaleType.bag,
                        label: Text(appLang == AppLang.en ? 'Bag' : 'गोणी')),
                    ButtonSegment(value: SaleType.kg, label: const Text('kg')),
                  ],
                  selected: {l.saleType},
                  onSelectionChanged: (s) => app.setLineSaleType(i, s.first),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: ValueKey('sales-row-$i-qty'),
                controller: _ctrlFor(l),
                focusNode: _focusFor(l),
                keyboardType:
                    TextInputType.numberWithOptions(decimal: !l.isBag),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(l.isBag ? r'[0-9]' : r'[0-9.]')),
                ],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                    labelText: l.isBag ? tr('गोणी · Bags') : tr('किलो · Kg'),
                    isDense: true),
                onChanged: (v) {
                  final q = double.tryParse(v);
                  if (q != null && q > 0) app.setLineQty(i, q);
                },
                onSubmitted: (_) => _openNextRowPicker(app),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: _rateQtyAmount(context, l, i),
        ),
        if (short)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                tr('⚠️ विक्रीयोग्य साठा फक्त ${qtyLabel(l.isBag, available)} · Only ${qtyLabel(l.isBag, available)} sellable'),
                style: TextStyle(
                    fontSize: 12,
                    color: c.critical,
                    fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }

  /// Selling rate × quantity = amount, as three labelled boxes. A rate
  /// changed on this bill is marked "for this bill" with the product's own
  /// price beside it — the product master price itself never changes.
  Widget _rateQtyAmount(BuildContext context, CartLine l, int i) {
    final c = context.c;
    final unit = l.isBag ? L('गोणी', 'bag') : 'kg';
    final changed = l.isOverridden;
    Widget box(String label, Widget value, {Key? key, VoidCallback? onTap}) {
      final body = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
            color: onTap == null ? null : c.surface2,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: onTap != null && changed ? c.accent : c.line,
                width: onTap != null && changed ? 1.6 : 1)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: c.ink2)),
              value,
            ]),
      );
      return Expanded(
        child: onTap == null
            ? body
            : InkWell(
                key: key,
                borderRadius: BorderRadius.circular(9),
                onTap: onTap,
                child: body),
      );
    }

    TextStyle big([Color? color]) =>
        TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color ?? c.ink);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        box(
            changed
                ? L('बिलासाठी दर ✎', 'Bill rate ✎')
                : L('विक्री दर ✎', 'Selling rate ✎'),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('${money(l.rate)}/$unit', style: big()),
            ),
            key: ValueKey('sales-row-$i-rate'),
            onTap: () => showEditRateSheet(context, context.read<AppState>(), i)),
        const SizedBox(width: 6),
        box(
            L('प्रमाण', 'Quantity'),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(qtyLabel(l.isBag, l.qty), style: big()),
            )),
        const SizedBox(width: 6),
        box(
            L('रक्कम', 'Amount'),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(money(l.lineTotal),
                  key: ValueKey('sales-row-$i-amount'), style: big(c.brand)),
            )),
      ]),
      if (changed)
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
              '✎ ${L('बिलासाठी बदललेला दर', 'Rate changed for this bill')}: '
              '${money(l.rate)}/$unit · ${L('मूळ दर', 'Product price')} ${money(l.catalogRate)}',
              key: ValueKey('sales-row-$i-bill-rate'),
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: c.ink2)),
        ),
    ]);
  }

  Widget _nextRowCard(BuildContext context, AppState app) {
    final c = context.c;
    return Container(
      decoration: cardDecoration(context, color: c.surface2, radius: 14),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(
              radius: 13,
              backgroundColor: c.brand.withValues(alpha: 0.14),
              child: Text('＋',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: c.brand))),
          const SizedBox(width: 8),
          Expanded(
              child: Text(tr('＋ आणखी उत्पादन · Add Another Product'),
                  style:
                      TextStyle(fontWeight: FontWeight.w700, color: c.ink2))),
        ]),
        const SizedBox(height: 8),
        BrandField(
          key: const ValueKey('sales-brand-filter'),
          app: app,
          brandId: _brandFilter,
          onChanged: (id) => setState(() => _brandFilter = id),
        ),
        const SizedBox(height: 8),
        PickerField(
          key: const ValueKey('sales-next-product'),
          label: tr('उत्पादन · Product'),
          value: null,
          placeholder: tr('उत्पादन शोधा · Search product'),
          onTap: () => _addProduct(app),
        ),
      ]),
    );
  }

  Widget _totalsCard(BuildContext context, AppState app) {
    final c = context.c;
    final discount = app.cartDiscount;
    Widget line(String l, String v, {bool bold = false, Color? color}) =>
        Padding(
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
                    : TextStyle(
                        fontWeight: FontWeight.w700, color: color ?? c.ink)),
          ]),
        );
    final bags =
        app.cart.where((l) => l.isBag).fold(0.0, (s, l) => s + l.qty).round();
    return Container(
      decoration: cardDecoration(context),
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        line('${tr('उप-बेरीज · Subtotal')}  🛍️ $bags',
            money(app.cartSubtotal + (discount > 0 ? discount : 0))),
        if (discount > 0)
          line(tr('− सूट · Discount'), '–${money(discount)}', color: c.serious),
        Divider(height: 20, color: c.line),
        line(tr('= एकूण · Grand total'), money(app.cartTotal), bold: true),
      ]),
    );
  }

  Future<void> _addProduct(AppState app) async {
    final p = await pickProduct(context, app, brandId: _brandFilter);
    if (p == null || !mounted) return;
    app.addToCart(p.id, SaleType.bag, 1);
    final line = app.cart.last;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctrl = _ctrlFor(line);
      ctrl.selection =
          TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
      _focusFor(line).requestFocus();
    });
  }

  void _openNextRowPicker(AppState app) {
    FocusScope.of(context).unfocus();
    _addProduct(app);
  }

  Future<bool?> _confirmDiscardEdit(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('दुरुस्ती रद्द करायची? · Discard edit?')),
          content: Text(
              tr('मूळ बिल बदलणार नाही · The original bill stays unchanged.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('नाही · No'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('हो · Discard'))),
          ],
        ),
      );
}
