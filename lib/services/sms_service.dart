import 'package:url_launcher/url_launcher.dart';

import 'whatsapp_service.dart';

/// "💬 SMS" for a saved bill: opens the phone's Messages app with the bill
/// text pre-filled for the customer's number. The shopkeeper presses Send —
/// nothing is sent in the background.
class SmsService {
  const SmsService._();

  /// sms: link for [mobile] (Indian numbers get +91) with [message] as the
  /// body; null when [mobile] doesn't look like a phone number.
  static Uri? smsUri(String mobile, String message) {
    final phone = WhatsAppService.phoneForWhatsApp(mobile);
    if (phone == null) return null;
    // Encoded by hand: a '+' for spaces (form encoding) shows literally in
    // some SMS apps.
    return Uri.parse('sms:+$phone?body=${Uri.encodeComponent(message)}');
  }

  /// Opens the SMS composer. False when there's no usable number or no app
  /// could handle the link.
  static Future<bool> open(
      {required String mobile, required String message}) async {
    final uri = smsUri(mobile, message);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
