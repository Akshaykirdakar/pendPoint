import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;

import '../../models/bill.dart';
import '../../models/enums.dart';
import '../../services/thermal_printer_service.dart';
import '../../services/sms_service.dart';
import '../../services/whatsapp_service.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../widgets/tiles.dart';
import 'draft_bills_screen.dart';
import 'sales_entry_screen.dart';
import '../../utils/lang.dart';

class BillScreen extends StatefulWidget {
  final String billId;

  /// Opened straight after saving — shows the "Bill saved" confirmation.
  final bool justSaved;
  const BillScreen({required this.billId, this.justSaved = false, super.key});

  @override
  State<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends State<BillScreen> {
  final GlobalKey _receiptKey = GlobalKey();
  bool _printing = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final bill = app.bills.where((b) => b.id == widget.billId).firstOrNull;
    if (bill == null) {
      return PendScaffold(
          titleMr: 'बिल',
          titleEn: 'Bill',
          body: EmptyState('🔍', tr('बिल सापडले नाही · Bill not found')));
    }
    final voided = bill.status == BillStatus.voided;
    final replacement = bill.replacedByBillId == null
        ? null
        : app.bills.where((b) => b.id == bill.replacedByBillId).firstOrNull;
    final party = bill.customerId == null ? null : app.partyOf(bill.customerId!);
    final mobile = party?.mobile ?? '';
    final hasWhatsAppNumber = WhatsAppService.phoneForWhatsApp(mobile) != null;
    final editBlock = app.whyBillNotEditable(bill);
    final voidBlock = app.whyBillLocked(bill);

    TextStyle mono = const TextStyle(fontFamily: 'monospace', fontSize: 12.5);
    Widget li(String l, String r, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(children: [
            Expanded(
                child: Text(l,
                    style: mono.copyWith(
                        fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
                        color: c.ink))),
            Text(r,
                style: mono.copyWith(
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
                    color: c.ink)),
          ]),
        );
    Widget dashes() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text('- ' * 20,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(color: c.muted, fontSize: 10)));
    Widget fact(String k, String v, {bool big = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(
                width: 118,
                child: Text(k, style: TextStyle(color: c.ink2, fontSize: 13))),
            Expanded(
                child: Text(v,
                    textAlign: TextAlign.right,
                    style: big
                        ? baloo(size: 20, weight: FontWeight.w800, color: c.brand)
                        : TextStyle(
                            fontWeight: FontWeight.w800, color: c.ink))),
          ]),
        );

    final (icon, color, headline, sub) = switch ((voided, replacement != null)) {
      (true, true) => (
          Icons.edit_note_rounded,
          c.muted,
          tr('बिल #${bill.billNumber} दुरुस्त केले · Bill #${bill.billNumber} corrected'),
          tr('नवीन आवृत्ती ${replacement!.revision} · Replaced by revision ${replacement.revision}')
        ),
      (true, false) => (
          Icons.close,
          c.critical,
          tr('बिल #${bill.billNumber} रद्द · Bill #${bill.billNumber} void'),
          tr('❌ रद्द केले · VOID')
        ),
      _ => (
          Icons.check,
          c.good,
          widget.justSaved
              ? tr('बिल सेव्ह झाले · Bill saved successfully')
              : tr('बिल #${bill.billNumber} · Bill #${bill.billNumber}'),
          bill.isRevised
              ? '${tr('दुरुस्त बिल · Corrected bill')} · ${money(bill.total)}'
              : money(bill.total)
        ),
    };

    return PendScaffold(
      titleMr: L('बिल #${bill.billNumber}', 'Bill #${bill.billNumber}'),
      titleEn: bill.isRevised ? 'Bill · Rev ${bill.revision}' : 'Bill',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Column(children: [
            Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 32)),
            const SizedBox(height: 10),
            Text(headline,
                key: const ValueKey('bill-headline'),
                textAlign: TextAlign.center,
                style: baloo(size: 20, weight: FontWeight.w800, color: c.ink)),
            Text(sub,
                textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
          ]),
        ),
        const SizedBox(height: 14),
        // Key facts first — what the counter needs to read back to the party.
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            fact(tr('बिल क्र. · Bill no.'),
                '#${bill.billNumber}${bill.isRevised ? ' (Rev ${bill.revision})' : ''}'),
            fact(tr('पार्टी · Party'),
                bill.customerName.isEmpty ? tr('रोख ग्राहक · Walk-in') : bill.customerName),
            fact(tr('दिनांक · Date'), dateTimeShort(bill.at)),
            fact(tr('एकूण · Total'), money(bill.total), big: true),
            if (bill.dueCollected > 0) ...[
              fact(tr('+ मागील बाकी जमा · Old due paid'),
                  money(bill.dueCollected)),
              fact(tr('एकूण घेतले · Received now'),
                  money(bill.total - bill.creditAmount + bill.dueCollected)),
            ],
          ]),
        ),
        if (replacement != null) ...[
          const SizedBox(height: 10),
          BigButton.brand(tr('➡️ दुरुस्त बिल उघडा · Open corrected bill'),
              onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                      builder: (_) => BillScreen(billId: replacement.id)))),
        ],
        if (widget.justSaved && !voided) ...[
          const SizedBox(height: 12),
          // Next customer: always a completely fresh bill.
          const NewSaleBillButton(
              key: ValueKey('bill-new-sale'), replace: true),
        ],
        const SizedBox(height: 12),
        TileGrid(columns: 2, gap: 10, [
          BigTile(
              key: const ValueKey('bill-print'),
              icon: Icons.print_rounded,
              mr: _printing ? 'छापत आहे…' : 'छापा',
              en: 'Print',
              color: c.ink2,
              onTap: _printing ? null : () => _print(context, app)),
          BigTile(
              key: const ValueKey('bill-whatsapp'),
              icon: Icons.chat_rounded,
              mr: 'WhatsApp',
              en: 'Send',
              color: const Color(0xFF25D366), // WhatsApp green
              onTap: () => _sendWhatsApp(context, app, bill, mobile)),
          BigTile(
              key: const ValueKey('bill-sms'),
              icon: Icons.sms_rounded,
              mr: 'SMS',
              en: 'Message',
              color: c.brand,
              onTap: () => _sendSms(context, app, bill, mobile)),
          BigTile(
              key: const ValueKey('bill-share'),
              icon: Icons.share_rounded,
              mr: 'शेअर',
              en: 'Share',
              color: c.s1,
              onTap: () => SharePlus.instance
                  .share(ShareParams(text: _message(app, bill)))),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
              hasWhatsAppNumber
                  ? L('${party!.name} (${party.mobile}) साठी WhatsApp मध्ये बिल तयार होईल — "पाठवा" दाबा',
                      'Opens WhatsApp for ${party.name} (${party.mobile}) with the bill ready — tap Send')
                  : L('पार्टीचा मोबाइल नाही — WhatsApp मध्ये चॅट निवडा',
                      'No party mobile — pick the chat in WhatsApp'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: c.muted)),
        ),
        // No secure hosted bill page exists yet, so there is no link to
        // send — the button stays off rather than share a fake one.
        const SizedBox(height: 6),
        OutlinedButton.icon(
          key: const ValueKey('bill-link'),
          onPressed: null,
          icon: const Icon(Icons.link_rounded),
          label: Text(tr('🔗 बिल लिंक — लवकरच उपलब्ध · Bill Link — not available yet')),
        ),
        if (!voided) ...[
          SectionHeader(tr('दुरुस्ती · Corrections')),
          TileGrid(columns: 2, gap: 10, [
            BigTile(
                key: const ValueKey('bill-edit'),
                icon: Icons.edit_rounded,
                mr: 'बिल दुरुस्त',
                en: 'Edit bill',
                color: c.s1,
                onTap: editBlock != null
                    ? null
                    : () => _startEdit(context, app, bill.id)),
            BigTile(
                key: const ValueKey('bill-void'),
                icon: Icons.cancel_rounded,
                mr: 'बिल रद्द',
                en: 'Void bill',
                color: c.critical,
                onTap: voidBlock != null
                    ? null
                    : () => _confirmVoid(context, app, bill.id, bill.billNumber)),
          ]),
          if (editBlock != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr(editBlock),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: c.muted)),
            ),
        ],
        SectionHeader(tr('बिल पहा · View bill')),
        RepaintBoundary(
          key: _receiptKey,
          child: Container(
            decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.line, style: BorderStyle.solid)),
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                      child: Text(app.settings.shop,
                          style: baloo(
                              size: 14,
                              weight: FontWeight.w700,
                              color: c.ink))),
                  Center(
                      child: Text(
                          '${L('बिल', 'Bill')} #${bill.billNumber}${bill.isRevised ? ' R${bill.revision}' : ''} · ${dateTimeShort(bill.at)}',
                          style: mono.copyWith(color: c.ink2))),
                  if (bill.customerName.isNotEmpty)
                    Center(
                        child: Text('${L('ग्राहक', 'Customer')}: ${bill.customerName}',
                            style: mono.copyWith(color: c.ink2))),
                  dashes(),
                  for (final it in bill.items) ...[
                    li('${app.productOf(it.productId)?.nameMr ?? ''} ${it.saleType == SaleType.bag ? '${it.qty.round()} × ${L('गोणी', 'bag')}' : '${kg(it.qty)} ${L('सुटे', 'loose')}'}',
                        money(it.lineTotal)),
                    if (app.brandOf(app.productOf(it.productId)?.brandId ?? '') != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                            app.brandOf(app.productOf(it.productId)!.brandId)!.nameMr,
                            style: mono.copyWith(fontSize: 10.5, color: c.muted)),
                      ),
                  ],
                  dashes(),
                  // bill.subtotal is already after line discounts; show the
                  // catalogue-rate subtotal so Subtotal − Discount = Total.
                  li(L('उप-बेरीज', 'Subtotal'), money(bill.subtotal + bill.discountTotal)),
                  if (bill.discountTotal > 0)
                    li(L('सूट', 'Discount'), '–${money(bill.discountTotal)}'),
                  li(L('एकूण', 'TOTAL'), money(bill.total), bold: true),
                  dashes(),
                  for (final p in bill.payments)
                    li(payModeLabel(p.mode), money(p.amount)),
                  if (bill.creditAmount > 0) ...[
                    dashes(),
                    li(tr('भरले · Paid'), money(bill.total - bill.creditAmount)),
                    li(tr('बाकी · Outstanding'), money(bill.creditAmount), bold: true),
                  ],
                  // The customer's khata: old due, what was paid towards it
                  // with this bill, and the balance after this bill.
                  if (bill.previousDue > 0) ...[
                    dashes(),
                    li(tr('मागील बाकी · Previous due'), money(bill.previousDue)),
                    if (bill.dueCollected > 0)
                      li(tr('मागील बाकी जमा · Old due paid'),
                          '–${money(bill.dueCollected)}'),
                    if (bill.creditAmount > 0)
                      li(tr('+ या बिलाचे उधार · This bill on credit'),
                          money(bill.creditAmount)),
                    li(tr('एकूण बाकी · Balance now'), money(bill.balanceAfter),
                        bold: true),
                  ],
                  const SizedBox(height: 8),
                  Center(
                      child: Text(tr('धन्यवाद! · Thank you 🙏'),
                          style: mono.copyWith(color: c.muted))),
                ]),
          ),
        ),
        const SizedBox(height: 8),
        Text(
            tr('🖨️ बिल प्रतिमा म्हणून छापले जाते — मराठी नावे थर्मल प्रिंटरवर बरोबर येतात · Printed as an image so Devanagari renders on the thermal printer.'),
            style: TextStyle(fontSize: 11.5, color: c.muted)),
        const SizedBox(height: 14),
        BigButton.ghost(tr('मुख्य पानावर · Done'),
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst)),
      ]),
    );
  }

  String _message(AppState app, Bill bill) => WhatsAppService.billMessage(
        shopName: app.settings.shop,
        bill: bill,
        productLabel: (id) {
          final p = app.productOf(id);
          if (p == null) return id;
          final b = app.brandOf(p.brandId);
          return '${p.nameMr} ${p.name}${b == null ? '' : ' (${b.name})'}';
        },
      );

  Future<void> _sendWhatsApp(
      BuildContext context, AppState app, Bill bill, String mobile) async {
    final opened = await WhatsAppService.open(
        mobile: mobile.isEmpty ? null : mobile, message: _message(app, bill));
    if (!opened && context.mounted) {
      showToast(context,
          'WhatsApp उघडता आले नाही · Could not open WhatsApp — use Share instead');
    }
  }

  /// Opens the phone's SMS app with the bill text for the customer — the
  /// shopkeeper presses Send. Says so when there's no mobile number.
  Future<void> _sendSms(
      BuildContext context, AppState app, Bill bill, String mobile) async {
    if (SmsService.smsUri(mobile, '') == null) {
      showToast(context,
          tr('ग्राहकाचा मोबाइल नंबर उपलब्ध नाही · Customer mobile number is not available.'));
      return;
    }
    final opened =
        await SmsService.open(mobile: mobile, message: _message(app, bill));
    if (!opened && context.mounted) {
      showToast(context,
          tr('SMS उघडता आले नाही · Could not open SMS — use Share instead'));
    }
  }

  /// Loads the bill into the sales grid for correction.
  Future<void> _startEdit(BuildContext context, AppState app, String id) async {
    // A new bill in progress is kept as a draft — never mixed into the
    // correction of a finalized bill (that is the revision workflow).
    if (app.editingBillId != id &&
        (!await keepCurrentBill(context) || !context.mounted)) {
      return;
    }
    final error = app.beginEditBill(id);
    if (!context.mounted) return;
    if (error != null) {
      showToast(context, error);
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SalesEntryScreen()));
  }

  Future<void> _print(BuildContext context, AppState app) async {
    final address = app.settings.printerAddress;
    if (address == null) {
      showToast(context,
          tr('सेटिंग्जमध्ये प्रिंटर जोडा · Pair a printer in Settings first'));
      return;
    }
    setState(() => _printing = true);
    try {
      final bytes = await _captureReceipt();
      if (bytes == null) {
        if (context.mounted) {
          showToast(context,
              tr('बिलाची प्रतिमा तयार करता आली नाही · Could not render receipt'));
        }
        return;
      }
      final connected = await ThermalPrinterService.instance
          .ensureConnected(address, app.settings.printerName);
      if (!connected) {
        if (context.mounted) {
          showToast(context,
              tr('प्रिंटरशी जोडता आले नाही · Could not connect to printer'));
        }
        return;
      }
      final sent = await ThermalPrinterService.instance.printImage(bytes);
      if (context.mounted) {
        showToast(
            context,
            sent
                ? tr('बिल प्रिंटरला पाठवले · Sent to printer')
                : tr('छपाई अयशस्वी · Print failed'));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  /// Renders the receipt card (wrapped in [_receiptKey]'s RepaintBoundary) to
  /// a PNG bitmap — sent to the thermal printer as an image so Devanagari
  /// prints correctly (ESC/POS text commands can't render it).
  Future<Uint8List?> _captureReceipt() async {
    final boundary = _receiptKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  void _confirmVoid(BuildContext context, AppState app, String id, int number) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.c.surface,
        title: Text(L('बिल रद्द करायचे?', 'Void this bill?'),
            style:
                baloo(size: 17, weight: FontWeight.w700, color: context.c.ink)),
        content: Text(
            tr('बिल #$number रद्द केल्यास साठा परत जमा होईल.\nVoid bill #$number? Stock will be restored.'),
            style: TextStyle(color: context.c.ink2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(L('नाही', 'No'))),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: context.c.critical),
              onPressed: () async {
                final error = await app.voidBill(id);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  showToast(context, error ?? tr('बिल रद्द झाले · Bill voided'));
                }
              },
              child: Text(L('रद्द करा', 'Void'))),
        ],
      ),
    );
  }
}
