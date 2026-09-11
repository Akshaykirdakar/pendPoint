import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../services/thermal_printer_service.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

class BillScreen extends StatefulWidget {
  final String billId;
  const BillScreen({required this.billId, super.key});

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
    final bill = app.bills.firstWhere((b) => b.id == widget.billId);
    final voided = bill.status == BillStatus.voided;

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

    return PendScaffold(
      titleMr: 'बिल तयार',
      titleEn: 'Bill ready',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Column(children: [
            Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                    color:
                        (voided ? c.critical : c.good).withValues(alpha: 0.16),
                    shape: BoxShape.circle),
                child: Icon(voided ? Icons.close : Icons.check,
                    color: voided ? c.critical : c.good, size: 32)),
            const SizedBox(height: 10),
            Text('बिल #${bill.billNumber} ${voided ? 'रद्द' : 'तयार'}',
                style: baloo(size: 19, weight: FontWeight.w800, color: c.ink)),
            Text(
                voided
                    ? '❌ रद्द केले · VOID'
                    : 'Sale complete · ${money(bill.total)}',
                style: TextStyle(color: c.muted)),
          ]),
        ),
        const SizedBox(height: 16),
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
                          'बिल #${bill.billNumber} · ${dateTimeShort(bill.at)}',
                          style: mono.copyWith(color: c.ink2))),
                  if (bill.customerName.isNotEmpty)
                    Center(
                        child: Text('ग्राहक: ${bill.customerName}',
                            style: mono.copyWith(color: c.ink2))),
                  dashes(),
                  for (final it in bill.items)
                    li('${app.productOf(it.productId)?.nameMr ?? ''} ${it.saleType == SaleType.bag ? '${it.qty.round()}×गोणी' : kg(it.qty)}',
                        money(it.lineTotal)),
                  dashes(),
                  li('उप-बेरीज', money(bill.subtotal)),
                  if (bill.discountTotal > 0)
                    li('सूट', '–${money(bill.discountTotal)}'),
                  li('एकूण TOTAL', money(bill.total), bold: true),
                  dashes(),
                  for (final p in bill.payments)
                    li(p.mode.name.toUpperCase(), money(p.amount)),
                  const SizedBox(height: 8),
                  Center(
                      child: Text('धन्यवाद! · Thank you 🙏',
                          style: mono.copyWith(color: c.muted))),
                ]),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
              color: c.warning.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.warning.withValues(alpha: 0.4))),
          padding: const EdgeInsets.all(11),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🖨️ '),
            Expanded(
                child: Text(
                    'बिल प्रतिमा म्हणून छापले जाते — त्यामुळे मराठी नावे थर्मल प्रिंटरवर बरोबर येतात.\nPrinted as an image so Devanagari renders on the thermal printer.',
                    style: TextStyle(
                        fontSize: 12,
                        color: c.ink,
                        fontWeight: FontWeight.w600))),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: BigButton.brand(
                  _printing ? 'छापत आहे... · Printing…' : '🖨️ छापा · Print',
                  onTap: _printing ? null : () => _print(context, app))),
          const SizedBox(width: 11),
          Expanded(
              child: BigButton.ghost('📲 WhatsApp',
                  onTap: () =>
                      showToast(context, 'WhatsApp वर पाठवले · Shared'))),
        ]),
        const SizedBox(height: 10),
        if (!voided)
          BigButton.danger('बिल रद्द करा · Void bill',
              onTap: () =>
                  _confirmVoid(context, app, bill.id, bill.billNumber)),
        const SizedBox(height: 10),
        BigButton.ghost('मुख्य पानावर · Done',
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst)),
      ]),
    );
  }

  Future<void> _print(BuildContext context, AppState app) async {
    final address = app.settings.printerAddress;
    if (address == null) {
      showToast(context,
          'सेटिंग्जमध्ये प्रिंटर जोडा · Pair a printer in Settings first');
      return;
    }
    setState(() => _printing = true);
    try {
      final bytes = await _captureReceipt();
      if (bytes == null) {
        if (context.mounted) {
          showToast(context,
              'बिलाची प्रतिमा तयार करता आली नाही · Could not render receipt');
        }
        return;
      }
      final connected = await ThermalPrinterService.instance
          .ensureConnected(address, app.settings.printerName);
      if (!connected) {
        if (context.mounted) {
          showToast(context,
              'प्रिंटरशी जोडता आले नाही · Could not connect to printer');
        }
        return;
      }
      final sent = await ThermalPrinterService.instance.printImage(bytes);
      if (context.mounted) {
        showToast(
            context,
            sent
                ? 'बिल प्रिंटरला पाठवले · Sent to printer'
                : 'छपाई अयशस्वी · Print failed');
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
        title: Text('बिल रद्द करायचे?',
            style:
                baloo(size: 17, weight: FontWeight.w700, color: context.c.ink)),
        content: Text(
            'बिल #$number रद्द केल्यास साठा परत जमा होईल.\nVoid bill #$number? Stock will be restored.',
            style: TextStyle(color: context.c.ink2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('नाही')),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: context.c.critical),
              onPressed: () async {
                await app.voidBill(id);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('रद्द करा')),
        ],
      ),
    );
  }
}
