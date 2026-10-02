import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../models/enums.dart';
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../state/cart_line.dart';
import '../../utils/formatters.dart';
import '../../utils/lang.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/payment_editor.dart';
import '../widgets/pend_scaffold.dart';
import '../widgets/pickers.dart';
import '../widgets/rate_editor.dart';
import '../widgets/search_picker.dart';
import 'bill_screen.dart';
import 'draft_bills_screen.dart';

/// 🧾 New Sale Bill — the counter's one-screen sale, top to bottom:
///
///   Customer → Cash / UPI / Credit → Product → Qty → Rate → Amount →
///   ＋ Add Item → items → Total → ✅ Finalize (or 📝 Draft)
///
/// The item being entered is separate from the items already on the bill;
/// "＋ Add Item" (or Enter on the rate) puts it on the bill and clears the
/// entry for the next product. An item filled in but not yet added is
/// added automatically on Finalize / Draft. The rate comes from the product
/// and may be changed for THIS bill only (floor + Owner PIN rules apply);
/// the product's own price never changes. Typing an amount instead works
/// out the rate (amount ÷ qty).
///
/// Leaving with unsaved changes asks Save Draft / Discard / Continue. Also
/// used to correct a saved bill ([AppState.beginEditBill]), with a banner.
class SalesEntryScreen extends StatefulWidget {
  const SalesEntryScreen({super.key});
  @override
  State<SalesEntryScreen> createState() => _SalesEntryScreenState();
}

class _SalesEntryScreenState extends State<SalesEntryScreen> {
  String? _brandFilter;

  // ---- the item being entered (not yet on the bill) ----
  String? _pid;
  SaleType _unit = SaleType.bag;
  double _catalogRate = 0;
  double? _approvedRate; // a bill rate already approved (line being re-edited)
  String? _entryError;
  final _qtyCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _qtyFocus = FocusNode();
  final _rateFocus = FocusNode();
  final _dueCtrl = TextEditingController();
  final _dueFocus = FocusNode();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_qtyCtrl, _rateCtrl, _amountCtrl]) {
      c.dispose();
    }
    _qtyFocus.dispose();
    _rateFocus.dispose();
    _dueCtrl.dispose();
    _dueFocus.dispose();
    super.dispose();
  }

  static String _num(double v) => v % 1 == 0
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '');

  double get _qty => double.tryParse(_qtyCtrl.text) ?? 0;
  double get _rate => double.tryParse(_rateCtrl.text) ?? 0;
  bool get _isBag => _unit == SaleType.bag;

  /// One short word in Marathi or English mode, both in "both" mode.
  static String one(String mr, String en) => switch (appLang) {
        AppLang.mr => mr,
        AppLang.en => en,
        AppLang.both => '$mr · $en',
      };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final editing = app.editingBillId == null
        ? null
        : app.bills.where((b) => b.id == app.editingBillId).firstOrNull;
    final draftLabel = app.currentDraftLabel;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (editing != null) {
          final discard = await _confirmDiscardEdit(context);
          if (discard == true && context.mounted) {
            app.cancelEditBill();
            Navigator.of(context).pop();
          }
          return;
        }
        if (await _leaveBill(context, app) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: PendScaffold(
        titleMr: editing != null
            ? 'बिल दुरुस्त #${editing.billNumber}'
            : draftLabel != null
                ? 'ड्राफ्ट #$draftLabel'
                : 'नवीन विक्री बिल',
        titleEn: editing != null
            ? 'Edit bill'
            : draftLabel != null
                ? 'Draft #$draftLabel'
                : 'New Sale Bill',
        bottomBar: _bottomBar(context, app, editing != null),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (editing != null) ...[
            _editBanner(context, app, editing.billNumber),
            const SizedBox(height: 12),
          ],
          if (editing == null && draftLabel != null) ...[
            _draftBanner(context, draftLabel),
            const SizedBox(height: 12),
          ],
          _customerSection(context, app),
          SectionHeader(tr('पेमेंट · Payment')),
          _paymentSection(context, app),
          SectionHeader(tr('वस्तू जोडा · Add item')),
          _entryCard(context, app),
          SectionHeader('${tr('बिलातील वस्तू · Items')} (${app.cart.length})'),
          if (app.cart.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(tr('अजून वस्तू नाही · No items yet'),
                  style: TextStyle(color: c.muted)),
            )
          else
            for (var i = 0; i < app.cart.length; i++) ...[
              _lineRow(context, app, i),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 6),
          _totalsCard(context, app),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- customer

  Widget _customerSection(BuildContext context, AppState app) {
    final c = context.c;
    final party =
        app.cartCustomerId == null ? null : app.partyOf(app.cartCustomerId!);
    final due = party?.customer?.outstanding ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PickerField(
        key: const ValueKey('sales-party'),
        label: 'ग्राहक · Customer',
        icon: Icons.person_search_rounded,
        value: party?.name,
        placeholder: tr('🔍 ग्राहक शोधा · Search customer'),
        onClear: () => app.setCartCustomer(null),
        onTap: () async {
          final p = await pickParty(context, app, purchase: false);
          if (p != null) app.setCartCustomer(p.id);
        },
      ),
      const SizedBox(height: 6),
      if (party != null)
        Text(
            [
              if (party.code.isNotEmpty) '${L('कोड', 'Code')}: ${party.code}',
              if (party.mobile.isNotEmpty) party.mobile,
            ].join(' · '),
            key: const ValueKey('sale-customer-info'),
            style: TextStyle(
                fontSize: 12.5, color: c.ink2, fontWeight: FontWeight.w700)),
      if (party != null && due > 0 && app.editingBillId == null) ...[
        const SizedBox(height: 8),
        _dueCard(context, app, due),
      ],
      // Walk-in (no customer) — the default for a cash sale; tap to drop
      // a chosen customer. A wrapping label, so it fits any font size.
      Align(
        alignment: Alignment.centerLeft,
        child: Material(
          key: const ValueKey('sale-walkin'),
          color: party == null ? c.brand.withValues(alpha: 0.14) : c.surface,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => app.setCartCustomer(null),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: party == null ? c.brand : c.line, width: 1.2)),
              child: Text(
                  '${party == null ? '✓ ' : ''}${tr('🚶 रोख ग्राहक · Walk-in customer')}',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: party == null ? c.ink : c.ink2)),
            ),
          ),
        ),
      ),
    ]);
  }

  /// "⚠️ मागील बाकी ₹2,380" — and, if the customer is paying it now,
  /// "➕ add previous due to this bill" with the amount being paid.
  Widget _dueCard(BuildContext context, AppState app, double due) {
    final c = context.c;
    final on = app.cartDueCollect > 0;
    if (!_dueFocus.hasFocus) {
      final shown = double.tryParse(_dueCtrl.text);
      if (shown != app.cartDueCollect) {
        _dueCtrl.text = on ? _num(app.cartDueCollect) : '';
      }
    }
    final creditOnly = on && !app.isSplitPayment && app.saleMode == PayMode.credit;
    return Container(
      key: const ValueKey('sale-prev-due'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
          color: c.serious.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.serious.withValues(alpha: 0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(tr('⚠️ मागील बाकी · Previous due'),
                style: TextStyle(fontWeight: FontWeight.w800, color: c.ink)),
          ),
          Text(money(due),
              key: const ValueKey('sale-prev-due-amount'),
              style: baloo(size: 18, weight: FontWeight.w800, color: c.serious)),
        ]),
        Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            key: const ValueKey('sale-add-due'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: on,
            onChanged: (v) => app.setDueCollect(v == true ? due : 0),
            title: Text(
                tr('➕ मागील बाकी बिलात जोडा · Add previous due to this bill'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
                tr('ग्राहक आता भरत असेल तर · When the customer is paying it now'),
                style: TextStyle(fontSize: 12, color: c.ink2)),
          ),
        ),
        if (on) ...[
          TextField(
            key: const ValueKey('sale-due-amount'),
            controller: _dueCtrl,
            focusNode: _dueFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
                labelText: tr('आता जमा · Paying now'),
                helperText:
                    '${L('कमाल', 'Max')} ${money(due)} · ${L('उर्वरित बाकी', 'Still due')} ${money(due - app.cartDueCollect)}',
                prefixText: '₹',
                isDense: true),
            onChanged: (v) {
              final typed = double.tryParse(v) ?? 0;
              app.setDueCollect(typed);
              // Capped at what is owed — show the capped amount at once.
              if (typed > due) {
                final t = _num(app.cartDueCollect);
                _dueCtrl.value = TextEditingValue(
                    text: t, selection: TextSelection.collapsed(offset: t.length));
              }
            },
          ),
          if (creditOnly)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  tr('⛔ मागील बाकी जमा करण्यासाठी रोख / UPI निवडा · Choose Cash or UPI to collect the previous due'),
                  key: const ValueKey('sale-due-needs-cash'),
                  style: TextStyle(
                      color: c.critical, fontWeight: FontWeight.w800)),
            ),
        ],
      ]),
    );
  }

  // ----------------------------------------------------------------- payment

  Widget _paymentSection(BuildContext context, AppState app) {
    final c = context.c;
    if (app.isSplitPayment) {
      return Container(
        decoration: cardDecoration(context),
        padding: const EdgeInsets.all(12),
        child: const PaymentSplitEditor(),
      );
    }
    final mode = app.saleMode;
    Widget button(PayMode m, String emoji, String mr, String en) {
      final on = mode == m;
      return Expanded(
        child: Material(
          key: ValueKey('sale-pay-${m.name}'),
          color: on ? c.brand : c.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => app.setSaleMode(m),
            child: Container(
              constraints: const BoxConstraints(minHeight: 58),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: on ? c.brand : c.line, width: on ? 2 : 1.2)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$emoji ${appLang == AppLang.en ? en : mr}',
                    textAlign: TextAlign.center,
                    style: baloo(
                        size: 16,
                        weight: FontWeight.w800,
                        color: on ? c.brandInk : c.ink)),
                if (appLang == AppLang.both && mr != en)
                  Text(en,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: on ? c.brandInk : c.ink2)),
              ]),
            ),
          ),
        ),
      );
    }

    final creditNoParty = mode == PayMode.credit && app.cartCustomerId == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        button(PayMode.cash, '💵', 'रोख', 'Cash'),
        const SizedBox(width: 8),
        button(PayMode.upi, '📱', 'UPI', 'UPI'),
        const SizedBox(width: 8),
        button(PayMode.credit, '📝', 'उधार', 'Credit'),
      ]),
      if (creditNoParty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(tr('⛔ उधारसाठी ग्राहक निवडा · Credit needs a customer'),
              key: const ValueKey('sale-credit-needs-customer'),
              style: TextStyle(color: c.critical, fontWeight: FontWeight.w800)),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
            key: const ValueKey('sale-split'),
            onPressed: app.addSplitPayment,
            child: Text(tr('＋ विभागून भरा · Split payment'))),
      ),
    ]);
  }

  // -------------------------------------------------------------- item entry

  Widget _entryCard(BuildContext context, AppState app) {
    final c = context.c;
    final p = _pid == null ? null : app.productOf(_pid!);
    final unitWord = _isBag ? one('गोणी', 'bag') : 'kg';
    final changed = p != null && _rate > 0 && _rate != _catalogRate;
    return Container(
      decoration: cardDecoration(context, color: c.surface2, radius: 14),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BrandField(
          key: const ValueKey('sales-brand-filter'),
          app: app,
          brandId: _brandFilter,
          onChanged: (id) => setState(() => _brandFilter = id),
        ),
        const SizedBox(height: 8),
        PickerField(
          key: const ValueKey('sales-next-product'),
          label: 'वस्तू · Product',
          icon: Icons.inventory_2_rounded,
          value: p == null ? null : '${p.nameMr} · ${p.name}',
          placeholder: tr('🔍 वस्तू शोधा · Search product'),
          onClear: p == null ? null : _clearEntry,
          onTap: () => _pickProduct(app),
        ),
        if (p != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Text(
                  '${L('साठा', 'Stock')}: ${qtyLabel(_isBag, app.sellableQty(p.id, _unit))} $unitWord',
                  style: TextStyle(fontSize: 12.5, color: c.ink2)),
            ),
            // Shrinks to fit a large font size rather than overflow.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: SegmentedButton<SaleType>(
                  key: const ValueKey('sale-entry-unit'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  segments: [
                    ButtonSegment(
                        value: SaleType.bag,
                        label: Text(appLang == AppLang.en ? 'Bag' : 'गोणी')),
                    const ButtonSegment(value: SaleType.kg, label: Text('kg')),
                  ],
                  selected: {_unit},
                  onSelectionChanged: (s) => _setUnit(app, s.first),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextField(
                key: const ValueKey('sale-entry-qty'),
                controller: _qtyCtrl,
                focusNode: _qtyFocus,
                keyboardType: TextInputType.numberWithOptions(decimal: !_isBag),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(_isBag ? r'[0-9]' : r'[0-9.]')),
                ],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                    labelText: one('प्रमाण', 'Qty'),
                    suffixText: unitWord,
                    isDense: true),
                onChanged: (_) => _syncAmount(),
                onSubmitted: (_) => _rateFocus.requestFocus(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const ValueKey('sale-entry-rate'),
                controller: _rateCtrl,
                focusNode: _rateFocus,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                    labelText: one('विक्री दर', 'Rate'),
                    prefixText: '₹',
                    isDense: true),
                onChanged: (_) => _syncAmount(),
                onSubmitted: (_) => _addEntry(app),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const ValueKey('sale-entry-amount'),
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                    labelText: one('रक्कम', 'Amount'),
                    prefixText: '₹',
                    isDense: true),
                onChanged: _amountTyped,
                onSubmitted: (_) => _addEntry(app),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
              changed
                  ? '✎ ${L('फक्त या बिलासाठी दर', 'Rate for this bill only')} · ${L('मूळ दर', 'Product price')} ${money(_catalogRate)}/$unitWord'
                  : '${L('मूळ दर', 'Product price')} ${money(_catalogRate)}/$unitWord',
              key: const ValueKey('sale-entry-rate-note'),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: changed ? FontWeight.w800 : FontWeight.w500,
                  color: changed ? c.serious : c.ink2)),
        ],
        if (_entryError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_entryError!,
                key: const ValueKey('sale-entry-error'),
                style:
                    TextStyle(color: c.critical, fontWeight: FontWeight.w800)),
          ),
        const SizedBox(height: 10),
        BigButton.brand(tr('＋ पुढील वस्तू · Add Item'),
            key: const ValueKey('sale-add-item'),
            onTap: p == null ? null : () => _addEntry(app)),
      ]),
    );
  }

  Future<void> _pickProduct(AppState app) async {
    final p =
        await pickProduct(context, app, brandId: _brandFilter, forSale: true);
    if (p == null || !mounted) return;
    _selectProduct(app, p);
  }

  void _selectProduct(AppState app, Product p) {
    if (!app.hasSellableStock(p.id)) {
      showToast(context, AppState.outOfStockMessage);
      return;
    }
    // Full bags when there are any, else loose kg.
    final unit =
        app.sellableQty(p.id, SaleType.bag) >= 1 ? SaleType.bag : SaleType.kg;
    setState(() {
      _pid = p.id;
      _unit = unit;
      _catalogRate = p.catalogRate(unit == SaleType.bag);
      _approvedRate = null;
      _entryError = null;
      _qtyCtrl.text = '1';
      _rateCtrl.text = _num(_catalogRate);
      _recalc();
    });
    _focusQty();
  }

  void _focusQty() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _qtyFocus.requestFocus();
      _qtyCtrl.selection =
          TextSelection(baseOffset: 0, extentOffset: _qtyCtrl.text.length);
    });
  }

  void _setUnit(AppState app, SaleType unit) {
    final p = app.productOf(_pid!);
    if (p == null) return;
    setState(() {
      _unit = unit;
      _catalogRate = p.catalogRate(unit == SaleType.bag);
      _approvedRate = null;
      if (unit == SaleType.bag) _qtyCtrl.text = _num(_qty.ceilToDouble());
      _rateCtrl.text = _num(_catalogRate);
      _recalc();
    });
  }

  /// Qty × Rate = Amount.
  void _syncAmount() => setState(_recalc);

  void _recalc() {
    _entryError = null;
    _amountCtrl.text = _qty > 0 && _rate > 0 ? _num(_qty * _rate) : '';
  }

  /// Amount typed directly → rate = amount ÷ qty (for this bill only).
  void _amountTyped(String v) {
    final amount = double.tryParse(v);
    setState(() {
      _entryError = null;
      if (amount != null && _qty > 0) {
        _rateCtrl.text = _num((amount / _qty * 100).round() / 100);
      }
    });
  }

  void _clearEntry() => setState(() {
        _pid = null;
        _approvedRate = null;
        _entryError = null;
        _qtyCtrl.clear();
        _rateCtrl.clear();
        _amountCtrl.clear();
      });

  /// Puts the item being entered on the bill. False (with the reason shown)
  /// when it can't be added yet.
  Future<bool> _addEntry(AppState app) async {
    final pid = _pid;
    if (pid == null) return true; // nothing being entered
    void fail(String why) => setState(() => _entryError = why);
    final qty = _qty, rate = _rate;
    if (qty <= 0 || (_isBag && qty % 1 != 0)) {
      fail(tr('⛔ योग्य प्रमाण लिहा · Enter a valid quantity'));
      return false;
    }
    if (rate <= 0) {
      fail(tr('⛔ योग्य दर लिहा · Enter a valid rate'));
      return false;
    }
    final left = app.sellableQty(pid, _unit);
    if (qty > left + 1e-9) {
      fail(_isBag
          ? L('⛔ फक्त ${left.floor()} गोणी साठा आहे',
              '⛔ Only ${left.floor()} bags in stock')
          : L('⛔ फक्त ${kg(left)} साठा आहे', '⛔ Only ${kg(left)} in stock'));
      return false;
    }
    // A changed rate: price floor, and the Owner PIN above the discount gate.
    final line = CartLine(
        productId: pid,
        saleType: _unit,
        qty: qty,
        catalogRate: _catalogRate,
        rate: rate);
    final check = app.checkRate(line, rate, pinApproved: rate == _approvedRate);
    if (check == 'NEEDS_PIN') {
      final ok = await askOwnerPin(context, app, line, rate);
      if (!mounted) return false;
      if (!ok) {
        fail(tr('⛔ चुकीचा PIN किंवा रद्द · Wrong PIN / cancelled'));
        return false;
      }
    } else if (check != null) {
      fail('⛔ ${tr(check)}');
      return false;
    }
    final error = app.addToCart(pid, _unit, qty, rate: rate);
    if (error != null) {
      fail(tr(error));
      return false;
    }
    _clearEntry();
    return true;
  }

  /// Tapping an item on the bill moves it back into the entry to change it.
  void _editLine(AppState app, int i) {
    if (_pid != null) {
      showToast(context,
          tr('आधी चालू वस्तू जोडा · Add the item being entered first'));
      return;
    }
    final l = app.cart[i];
    app.removeLine(i);
    setState(() {
      _pid = l.productId;
      _unit = l.saleType;
      _catalogRate = l.catalogRate;
      _approvedRate = l.rate; // already approved when it was added
      _entryError = null;
      _qtyCtrl.text = _num(l.qty);
      _rateCtrl.text = _num(l.rate);
      _amountCtrl.text = _num(l.lineTotal);
    });
    _focusQty();
  }

  // ------------------------------------------------------------- bill lines

  Widget _lineRow(BuildContext context, AppState app, int i) {
    final c = context.c;
    final l = app.cart[i];
    final p = app.productOf(l.productId);
    if (p == null) return const SizedBox.shrink();
    final available = app.sellableQty(l.productId, l.saleType);
    final short = app.editingBillId == null && l.qty > available + 1e-9;
    final unit = l.isBag ? one('गोणी', 'bag') : 'kg';
    return Material(
      key: ValueKey('sales-row-$i'),
      color: c.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editLine(app, i),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: short ? c.critical : c.line, width: short ? 1.6 : 1)),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.nameMr.isEmpty ? p.name : '${p.nameMr} · ${p.name}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: baloo(
                            size: 14.5, weight: FontWeight.w700, color: c.ink)),
                    Text(
                        '${qtyLabel(l.isBag, l.qty)} ${l.isBag ? unit : ''} × ${money(l.rate)}',
                        key: ValueKey('sales-row-$i-qty-rate'),
                        style: TextStyle(fontSize: 13, color: c.ink2)),
                    if (l.isOverridden)
                      Text(
                          '✎ ${L('बिलासाठी बदललेला दर', 'Rate changed for this bill')} · ${L('मूळ दर', 'Product price')} ${money(l.catalogRate)}',
                          key: ValueKey('sales-row-$i-bill-rate'),
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: c.serious)),
                    if (short)
                      Text(tr('⚠️ विक्रीयोग्य साठा फक्त ${qtyLabel(l.isBag, available)} · Only ${qtyLabel(l.isBag, available)} sellable'),
                          style: TextStyle(
                              fontSize: 12,
                              color: c.critical,
                              fontWeight: FontWeight.w700)),
                  ]),
            ),
            const SizedBox(width: 6),
            Text(money(l.lineTotal),
                key: ValueKey('sales-row-$i-amount'),
                style:
                    baloo(size: 15.5, weight: FontWeight.w800, color: c.ink)),
            IconButton(
              key: ValueKey('sales-row-$i-remove'),
              tooltip: tr('वस्तू काढा · Remove item'),
              icon: Icon(Icons.delete_outline_rounded, color: c.critical),
              onPressed: () => app.removeLine(i),
            ),
          ]),
        ),
      ),
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
    return Container(
      decoration: cardDecoration(context),
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        line(tr('उप-बेरीज · Subtotal'),
            money(app.cartSubtotal + (discount > 0 ? discount : 0))),
        line(tr('सूट · Discount'),
            discount > 0 ? '–${money(discount)}' : money(0),
            color: discount > 0 ? c.serious : null),
        Divider(height: 20, color: c.line),
        if (app.cartDueCollect > 0) ...[
          line(tr('बिल रक्कम · Bill amount'), money(app.cartTotal)),
          line(tr('+ मागील बाकी · Previous due'), money(app.cartDueCollect),
              color: c.serious),
          Divider(height: 20, color: c.line),
          line(tr('एकूण देय · Total payable'), money(app.cartPayable),
              bold: true),
        ] else
          line(tr('एकूण · Total'), money(app.cartTotal), bold: true),
      ]),
    );
  }

  // -------------------------------------------------------------- bottom bar

  Widget _bottomBar(BuildContext context, AppState app, bool editing) {
    final c = context.c;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(
          flex: 3,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    '${app.cartDueCollect > 0 ? tr('एकूण देय · Total payable') : tr('एकूण · Total')}  🧾 ${app.cart.length}',
                    style: TextStyle(fontSize: 11.5, color: c.ink2)),
                Text(money(app.cartPayable),
                    key: const ValueKey('sales-grand-total'),
                    style: baloo(
                        size: 22, weight: FontWeight.w800, color: c.brand)),
              ]),
        ),
        if (!editing)
          Flexible(
            flex: 2,
            child: OutlinedButton(
              key: const ValueKey('sales-save-draft'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 10)),
              onPressed: _saving ? null : () => _saveDraft(context, app),
              child: Text(tr('💾 ड्राफ्ट · Draft'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      BigButton.primary(
          editing
              ? tr('✅ दुरुस्त बिल सेव्ह करा · Save corrected bill')
              : tr('✅ बिल पूर्ण करा · Finalize Bill'),
          key: const ValueKey('sales-finalize'),
          onTap: _saving ? null : () => _finalize(context, app)),
    ]);
  }

  /// Validates and saves the sale (the normal stock / payment / khata
  /// commit). Nothing is saved if any check fails.
  Future<void> _finalize(BuildContext context, AppState app) async {
    FocusScope.of(context).unfocus();
    if (!await _addEntry(app) || !context.mounted) return;
    if (app.cart.isEmpty) {
      showToast(
          context, tr('बिलात किमान एक वस्तू जोडा · Add at least one item'));
      return;
    }
    if (app.shortLines.isNotEmpty) {
      showToast(context, AppState.shortStockMessage);
      return;
    }
    if (!app.isSplitPayment &&
        app.saleMode == PayMode.credit &&
        app.cartCustomerId == null) {
      showToast(context, tr('उधारसाठी ग्राहक निवडा · Credit needs a customer'));
      return;
    }
    app.ensurePayments();
    setState(() => _saving = true);
    final res = await app.finalizeSale();
    if (!context.mounted) return;
    setState(() => _saving = false);
    if (!res.ok) {
      showToast(context, res.error ?? L('त्रुटी', 'Error'));
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => BillScreen(billId: res.bill!.id, justSaved: true)),
      (route) => route.isFirst,
    );
  }

  // ------------------------------------------------------------------ drafts

  Widget _editBanner(BuildContext context, AppState app, int number) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: c.warning.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.warning.withValues(alpha: 0.4))),
      child: Row(children: [
        const Text('✏️ '),
        Expanded(
          child: Text(
              tr(
                  'बिल #$number दुरुस्त करत आहात. सेव्ह केल्यावर जुन्या बिलाचा साठा परत येईल व नवीन बिल लागू होईल.\n'
                  'Editing bill #$number. On save the old stock is restored and the corrected bill applied.'),
              style: TextStyle(
                  fontSize: 12, color: c.ink, fontWeight: FontWeight.w600)),
        ),
        TextButton(
            onPressed: () {
              app.cancelEditBill();
              Navigator.of(context).pop();
            },
            child: Text(tr('रद्द · Cancel'))),
      ]),
    );
  }

  /// "📝 ड्राफ्ट #D1024 — not finished yet; changes save automatically."
  Widget _draftBanner(BuildContext context, String label) {
    final c = context.c;
    return Container(
      key: const ValueKey('sales-draft-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: c.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.warning.withValues(alpha: 0.45))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const DraftPill(),
              Text('#$label',
                  style:
                      baloo(size: 15, weight: FontWeight.w800, color: c.ink)),
            ]),
        const SizedBox(height: 6),
        Text(tr('हे बिल अजून पूर्ण झालेले नाही. बदल आपोआप सेव्ह होतात · This bill is not finished yet. Changes save automatically.'),
            style: TextStyle(
                fontSize: 12, color: c.ink, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  static String _savedText(DraftResult r) => L(
      '✅ ड्राफ्ट सेव्ह झाला · #${r.draft!.label}',
      '✅ Draft saved · #${r.draft!.label}');

  /// 📝 Draft: keeps the bill (an item being entered is added first) and
  /// offers Continue / New Sale Bill / Draft Bills.
  Future<void> _saveDraft(BuildContext context, AppState app) async {
    FocusScope.of(context).unfocus();
    if (!await _addEntry(app) || !context.mounted) return;
    final r = await app.saveDraft();
    if (!context.mounted) return;
    if (!r.ok) {
      showToast(context, r.error!);
      return;
    }
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_savedText(r), key: const ValueKey('draft-saved-title')),
        content: Text(tr(
            'हे बिल अजून पूर्ण झालेले नाही — ड्राफ्ट बिलेमध्ये सुरक्षित आहे · Not finished yet — kept safe in Draft Bills.')),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
              key: const ValueKey('draft-saved-continue'),
              onPressed: () => Navigator.pop(ctx, 'continue'),
              child: Text(tr('↩ ड्राफ्ट सुरू ठेवा · Continue Draft'))),
          TextButton(
              key: const ValueKey('draft-saved-list'),
              onPressed: () => Navigator.pop(ctx, 'list'),
              child: Text(tr('📝 ड्राफ्ट बिले · Draft Bills'))),
          FilledButton(
              key: const ValueKey('draft-saved-new'),
              onPressed: () => Navigator.pop(ctx, 'new'),
              child: Text(tr('🧾 नवीन विक्री बिल · New Sale Bill'))),
        ],
      ),
    );
    if (!context.mounted) return;
    switch (next) {
      case 'new':
        await openNewBill(context, replace: true);
      case 'list':
        app.closeBill();
        await Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => const DraftBillsScreen()));
    }
  }

  /// Back from a (non-edit) bill: nothing to lose → leave; a draft with
  /// changes → save it and leave; a new bill with changes → ask.
  Future<bool> _leaveBill(BuildContext context, AppState app) async {
    final pendingItem = _pid != null;
    if (!app.hasUnsavedBill && !pendingItem) {
      app.closeBill();
      return true;
    }
    if (app.currentDraftId != null && !pendingItem) {
      final r = await app.saveDraft();
      if (!context.mounted) return false;
      if (r.ok) {
        showToast(context, _savedText(r));
        app.closeBill();
        return true;
      }
      showToast(context, r.error!);
    }
    final choice = await showDialog<_Leave>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            Text(tr('ड्राफ्ट सेव्ह करायचा आहे? · Save this bill as a draft?')),
        content: Text(tr(
            'हे बिल अजून पूर्ण झालेले नाही · This bill is not finished yet.')),
        actions: [
          TextButton(
              key: const ValueKey('leave-stay'),
              onPressed: () => Navigator.pop(ctx, _Leave.stay),
              child: Text(tr('↩ परत जा · Continue Editing'))),
          TextButton(
              key: const ValueKey('leave-discard'),
              style: TextButton.styleFrom(foregroundColor: ctx.c.critical),
              onPressed: () => Navigator.pop(ctx, _Leave.discard),
              child: Text(tr('🗑 टाका · Discard'))),
          FilledButton(
              key: const ValueKey('leave-save'),
              onPressed: () => Navigator.pop(ctx, _Leave.save),
              child: Text(tr('💾 सेव्ह करा · Save Draft'))),
        ],
      ),
    );
    if (!context.mounted) return false;
    switch (choice) {
      case _Leave.save:
        if (!await _addEntry(app) || !context.mounted) return false;
        final r = await app.saveDraft();
        if (!context.mounted) return false;
        if (!r.ok) {
          showToast(context, r.error!);
          return false;
        }
        showToast(context, _savedText(r));
        app.closeBill();
        return true;
      case _Leave.discard:
        app.closeBill();
        return true;
      case _Leave.stay:
      case null:
        return false;
    }
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

enum _Leave { save, discard, stay }
