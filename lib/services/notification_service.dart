import '../models/platform.dart';
import '../models/store.dart';

/// One message for one store's owner.
class OutgoingMessage {
  final Store store;
  final String type;
  final String title;
  final String message;
  const OutgoingMessage(
      {required this.store,
      required this.type,
      required this.title,
      required this.message});
}

/// A WhatsApp / SMS gateway. NONE is configured in this app: a real one
/// (e.g. WhatsApp Cloud API, an Indian DLT-registered SMS gateway) must run
/// on a backend that holds its API secret — never in the Flutter app.
/// Implement this (calling that backend) and pass it to the channel.
abstract class MessagingProvider {
  String get name;
  Future<void> send({required String to, required String text});
}

/// One delivery channel. [send] returns a [ChannelStatus] value.
abstract class NotificationChannelService {
  String get channel;

  /// Whether a provider is set up so messages can actually be delivered.
  bool get configured;
  Future<String> send(OutgoingMessage m);
}

/// In-app: always available — the notification document IS the delivery
/// (written by the caller in one batch); this only reports the status.
class InAppNotificationService implements NotificationChannelService {
  @override
  String get channel => Channels.inApp;
  @override
  bool get configured => true;
  @override
  Future<String> send(OutgoingMessage m) async => ChannelStatus.delivered;
}

/// WhatsApp to the store owner. Without a [provider] nothing is sent and
/// the status says so ([ChannelStatus.providerRequired]).
class WhatsAppNotificationService implements NotificationChannelService {
  final MessagingProvider? provider;
  const WhatsAppNotificationService([this.provider]);
  @override
  String get channel => Channels.whatsApp;
  @override
  bool get configured => provider != null;
  @override
  Future<String> send(OutgoingMessage m) async {
    final to = m.store.whatsAppTarget;
    if (to == null) return ChannelStatus.noContact;
    final p = provider;
    if (p == null) return ChannelStatus.providerRequired;
    try {
      await p.send(to: to, text: '${m.title}\n${m.message}');
      return ChannelStatus.delivered;
    } catch (_) {
      return ChannelStatus.failed;
    }
  }
}

/// SMS to the store owner — same contract as WhatsApp.
class SmsNotificationService implements NotificationChannelService {
  final MessagingProvider? provider;
  const SmsNotificationService([this.provider]);
  @override
  String get channel => Channels.sms;
  @override
  bool get configured => provider != null;
  @override
  Future<String> send(OutgoingMessage m) async {
    final to = m.store.smsTarget;
    if (to == null) return ChannelStatus.noContact;
    final p = provider;
    if (p == null) return ChannelStatus.providerRequired;
    try {
      await p.send(to: to, text: m.message);
      return ChannelStatus.delivered;
    } catch (_) {
      return ChannelStatus.failed;
    }
  }
}

/// Sends one message over the chosen channels and reports each channel's
/// status. Adding a provider later = constructing the channel with it; the
/// rest of the app does not change.
class NotificationService {
  final Map<String, NotificationChannelService> channels;
  NotificationService({
    NotificationChannelService? inApp,
    NotificationChannelService? whatsApp,
    NotificationChannelService? sms,
  }) : channels = {
          Channels.inApp: inApp ?? InAppNotificationService(),
          Channels.whatsApp: whatsApp ?? const WhatsAppNotificationService(),
          Channels.sms: sms ?? const SmsNotificationService(),
        };

  bool configured(String channel) => channels[channel]?.configured ?? false;

  Future<Map<String, String>> deliver(OutgoingMessage m,
      {required Iterable<String> selected,
      required GlobalSettings settings,
      DateTime? scheduledFor}) async {
    final out = <String, String>{};
    for (final c in selected) {
      if (!settings.channelEnabled(c)) {
        out[c] = ChannelStatus.disabled;
        continue;
      }
      if (c == Channels.inApp && scheduledFor != null) {
        out[c] = ChannelStatus.scheduled;
        continue;
      }
      if (c != Channels.inApp && scheduledFor != null) {
        // No backend scheduler exists for WhatsApp/SMS — not pretended.
        out[c] = configured(c)
            ? ChannelStatus.failed
            : ChannelStatus.providerRequired;
        continue;
      }
      out[c] = await (channels[c]?.send(m) ?? Future.value(ChannelStatus.failed));
    }
    return out;
  }
}
