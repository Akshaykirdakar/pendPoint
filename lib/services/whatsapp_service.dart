import 'package:url_launcher/url_launcher.dart';

import '../models/bill.dart';
import '../models/enums.dart';
import '../utils/formatters.dart';

/// "Send on WhatsApp" for a saved bill: builds a readable bill message and
/// opens WhatsApp (app or web) with it pre-filled for the party's number.
/// The user presses Send — there is no WhatsApp Business API integration,
/// so nothing is delivered automatically in the background.
class WhatsAppService {
  const WhatsAppService._();

  /// WhatsApp's international format (digits only, with country code) for
  /// an Indian mobile as typed at the counter — "98220 11223",
  /// "098220 11223", "+91 98220-11223" all become "919822011223". Returns
  /// null when it doesn't look like a phone number.
  static String? phoneForWhatsApp(String mobile) {
    final d = mobile.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 10) return '91$d';
    if (d.length == 11 && d.startsWith('0')) return '91${d.substring(1)}';
    if (d.length == 12 && d.startsWith('91')) return d;
    if (d.length > 12 && d.length <= 15) return d; // already international
    return null;
  }

  /// https://wa.me link with the message pre-filled; without a valid
  /// [mobile] WhatsApp asks which chat to send it to.
  static Uri whatsAppUri(String? mobile, String message) {
    final phone = mobile == null ? null : phoneForWhatsApp(mobile);
    return Uri.https(
        'wa.me', phone == null ? '/' : '/$phone', {'text': message});
  }

  /// The bill as a plain-text message. Lines that FEFO split across
  /// batches are merged back into one line per product/rate.
  static String billMessage({
    required String shopName,
    required Bill bill,
    required String Function(String productId) productLabel,
  }) {
    final lines =
        <({String productId, SaleType type, double rate, double qty})>[];
    for (final it in bill.items) {
      final i = lines.indexWhere((l) =>
          l.productId == it.productId &&
          l.type == it.saleType &&
          l.rate == it.rate);
      if (i >= 0) {
        final l = lines[i];
        lines[i] = (
          productId: l.productId,
          type: l.type,
          rate: l.rate,
          qty: l.qty + it.qty
        );
      } else {
        lines.add((
          productId: it.productId,
          type: it.saleType,
          rate: it.rate,
          qty: it.qty
        ));
      }
    }

    final b = StringBuffer()
      ..writeln('*$shopName*')
      ..writeln('बिल / Bill #${bill.billNumber}'
          '${bill.isRevised ? ' (सुधारित / Revised ${bill.revision})' : ''}')
      ..writeln('दिनांक / Date: ${dayFull(bill.at)} ${timeShort(bill.at)}');
    if (bill.customerName.isNotEmpty) {
      b.writeln('पार्टी / Party: ${bill.customerName}');
    }
    b.writeln('------------------------------');
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final qty =
          l.type == SaleType.bag ? '${l.qty.round()} गोणी bags' : kg(l.qty);
      b
        ..writeln('${i + 1}. ${productLabel(l.productId)}')
        ..writeln('   $qty × ${money(l.rate)} = ${money(l.rate * l.qty)}');
    }
    // bill.subtotal is already after line discounts; show the catalogue-
    // rate subtotal so Subtotal − Discount = Grand total.
    b
      ..writeln('------------------------------')
      ..writeln(
          'उप-बेरीज / Subtotal: ${money(bill.subtotal + bill.discountTotal)}');
    if (bill.discountTotal > 0) {
      b.writeln('सूट / Discount: -${money(bill.discountTotal)}');
    }
    b.writeln('*एकूण / Grand total: ${money(bill.total)}*');
    if (bill.creditAmount > 0) {
      b
        ..writeln('भरले / Paid: ${money(bill.total - bill.creditAmount)}')
        ..writeln('बाकी (उधार) / Due: ${money(bill.creditAmount)}');
    }
    b.write('धन्यवाद! / Thank you 🙏');
    return b.toString();
  }

  /// Opens WhatsApp with [message]. Returns false when no app/browser could
  /// handle the link.
  static Future<bool> open({String? mobile, required String message}) async {
    try {
      return await launchUrl(whatsAppUri(mobile, message),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
