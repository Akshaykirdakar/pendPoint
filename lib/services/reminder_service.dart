import 'package:url_launcher/url_launcher.dart';

import '../models/app_settings.dart';
import '../utils/formatters.dart';
import '../utils/lang.dart';
import 'sms_service.dart';
import 'whatsapp_service.dart';

/// How a payment reminder is sent.
enum ReminderChannel { whatsApp, sms }

/// "🔔 उधार आठवण" — a polite reminder of a customer's credit due, opened
/// in WhatsApp or the SMS app with the text ready. The shopkeeper presses
/// Send for each one; nothing is sent in the background.
class ReminderService {
  const ReminderService._();

  /// Opens a link (replaced in tests to record what would open).
  static Future<bool> Function(Uri uri) launch = (uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  };

  /// The reminder text in the shop's language setting (मराठी, English or
  /// both — [lang] defaults to the app's current setting).
  static String message({
    required String shopName,
    required String customerName,
    required double due,
    AppLang? lang,
  }) {
    final mr = 'नमस्कार $customerName,\n'
        '$shopName येथे आपली उधार बाकी ${money(due)} आहे. '
        'कृपया लवकरात लवकर भरणा करावा.\n'
        'धन्यवाद 🙏';
    final en = 'Dear $customerName,\n'
        'Your pending balance at $shopName is ${money(due)}. '
        'Kindly pay at your earliest convenience.\n'
        'Thank you 🙏';
    return switch (lang ?? appLang) {
      AppLang.mr => mr,
      AppLang.en => en,
      AppLang.both => '$mr\n\n$en',
    };
  }

  /// Whether [mobile] can receive a reminder at all.
  static bool hasValidMobile(String mobile) =>
      WhatsAppService.phoneForWhatsApp(mobile) != null;

  /// The link that opens [channel] for [mobile] with [message] filled in;
  /// null without a usable number.
  static Uri? uri(ReminderChannel channel, String mobile, String message) {
    if (!hasValidMobile(mobile)) return null;
    return switch (channel) {
      ReminderChannel.whatsApp => WhatsAppService.whatsAppUri(mobile, message),
      ReminderChannel.sms => SmsService.smsUri(mobile, message),
    };
  }

  /// Opens the reminder. False when there is no number or nothing could
  /// open the link.
  static Future<bool> open(
      ReminderChannel channel, String mobile, String message) async {
    final u = uri(channel, mobile, message);
    if (u == null) return false;
    return launch(u);
  }
}
