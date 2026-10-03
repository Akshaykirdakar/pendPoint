/// Platform (Super Admin) layer: global settings, plans, store payments,
/// notifications and announcements. Everything here is either GLOBAL
/// (super admin) or tagged with the store it belongs to — see the rules in
/// firestore.rules and docs/PLATFORM.md.
library;

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
String? _iso(DateTime? d) => d?.toIso8601String();
double _num(Object? v) => v is num ? v.toDouble() : 0;
List<int> _ints(Object? v, List<int> fallback) =>
    v is List ? [for (final x in v) if (x is num) x.toInt()] : fallback;

/// Notification channels.
abstract final class Channels {
  static const inApp = 'inApp';
  static const whatsApp = 'whatsApp';
  static const sms = 'sms';
  static const all = [inApp, whatsApp, sms];
}

/// What happened to a message on one channel. Only [delivered] means it
/// reached the recipient's app; WhatsApp/SMS without a configured provider
/// are recorded as [providerRequired] — never as sent.
abstract final class ChannelStatus {
  static const delivered = 'delivered'; // in-app: stored for the recipient
  static const scheduled = 'scheduled'; // in-app: shows from visibleFrom
  static const providerRequired = 'provider_required';
  static const disabled = 'disabled'; // switched off in General Settings
  static const noContact = 'no_contact'; // owner has no number / chose none
  static const failed = 'failed';
}

/// Who a notification is for.
abstract final class Audience {
  /// The super admin (platform events). Never readable by store users.
  static const superAdmin = 'super_admin';

  /// The store's admin/owner only.
  static const storeAdmin = 'admin';

  /// Every user of the store.
  static const storeAll = 'all';
}

/// Notification types (also the template keys where one exists).
abstract final class NoticeType {
  // sent by the super admin
  static const paymentReminder = 'payment_reminder';
  static const renewalReminder = 'renewal_reminder';
  static const planExpiry = 'plan_expiry';
  static const planExpired = 'plan_expired';
  static const paymentConfirmation = 'payment_confirmation';
  static const offer = 'offer';
  static const announcement = 'announcement';
  static const maintenance = 'maintenance';
  static const custom = 'custom';
  // automatic (events)
  static const storeCreated = 'store_created';
  static const storeUpdated = 'store_updated';
  static const storeActivated = 'store_activated';
  static const storeDeactivated = 'store_deactivated';
  static const storePlanChanged = 'store_plan_changed';
  static const paymentReceived = 'payment_received';
  static const paymentPending = 'payment_pending';
  static const paymentFailed = 'payment_failed';
  static const planRenewed = 'plan_renewed';
  static const staffAdded = 'staff_added';
  static const staffDisabled = 'staff_disabled';
  static const staffActivated = 'staff_activated';
  static const staffChanged = 'staff_changed';
  static const security = 'security';
  static const system = 'system';

  /// Types the super admin picks from on "Send notification".
  static const sendable = [
    paymentReminder,
    renewalReminder,
    planExpiry,
    paymentConfirmation,
    offer,
    announcement,
    maintenance,
    custom,
  ];

  /// Store-wide (every user) rather than owner-only.
  static bool forWholeStore(String type) =>
      type == announcement || type == maintenance || type == storeActivated ||
      type == storeDeactivated;

  static String icon(String type) => switch (type) {
        paymentReminder || paymentPending => '💳',
        paymentReceived || paymentConfirmation || planRenewed => '✅',
        paymentFailed => '❌',
        renewalReminder || planExpiry => '⏰',
        planExpired => '⛔',
        offer => '🎁',
        announcement => '📢',
        maintenance => '🛠️',
        storeCreated => '🏪',
        storeUpdated || storePlanChanged => '✏️',
        storeActivated => '🟢',
        storeDeactivated => '🔴',
        staffAdded || staffActivated || staffChanged => '👤',
        staffDisabled => '🚫',
        security => '🔐',
        _ => '🔔',
      };
}

/// Plan status. trial/active/suspended are set by the super admin;
/// expiring/expired follow from the expiry date ([Store]-side helper).
abstract final class PlanStatus {
  static const none = 'none'; // no plan recorded (e.g. the original store)
  static const trial = 'trial';
  static const active = 'active';
  static const expiring = 'expiring';
  static const expired = 'expired';
  static const suspended = 'suspended';
  static const settable = [trial, active, suspended];
}

abstract final class PaymentStatus {
  static const pending = 'pending';
  static const paid = 'paid';
  static const failed = 'failed';
  static const refunded = 'refunded';
  static const all = [pending, paid, failed, refunded];
}

/// Default message templates — only used until the super admin saves
/// General Settings; after that the stored templates are used.
/// Placeholders: {storeName} {storeCode} {amount} {dueDate} {expiryDate}
/// {days} {appName} {supportPhone}.
const defaultTemplates = <String, String>{
  NoticeType.paymentReminder:
      'Your {appName} subscription payment of {amount} is due on {dueDate}. Please renew your plan to continue using the service.',
  NoticeType.renewalReminder:
      'Your {appName} plan for {storeName} will expire on {expiryDate}. Please renew your subscription.',
  NoticeType.planExpiry:
      'Your {appName} plan expires in {days} days. Please renew to avoid service interruption.',
  NoticeType.planExpired:
      'Your {appName} plan has expired. Please contact support ({supportPhone}) to renew your subscription.',
  NoticeType.paymentConfirmation:
      'Thank you! We received your payment of {amount} for {storeName}. Your plan is valid until {expiryDate}.',
  NoticeType.offer:
      'We have a new offer available for your {appName} store. Contact us for details.',
  NoticeType.announcement: 'News from {appName}.',
  NoticeType.maintenance:
      '{appName} will be under scheduled maintenance. We are sorry for the inconvenience.',
};

/// Fills {placeholders} in [template] (unknown ones are left as they are).
String renderTemplate(String template, Map<String, String> values) =>
    template.replaceAllMapped(RegExp(r'\{(\w+)\}'),
        (m) => values[m.group(1)] ?? m.group(0)!);

/// global_settings/general (every signed-in user reads) +
/// global_settings/admin (super admin only: switches, plan rules,
/// templates, non-secret provider settings). Provider API secrets are NEVER
/// stored here — they belong in the backend's secret manager.
class GlobalSettings {
  // ---- application (general) ----
  String appName;
  String logoUrl;
  String appVersion;
  String supportPhone;
  String supportEmail;
  String supportWhatsApp;
  String companyName;
  String address;
  String website;
  String defaultLanguage; // both | mr | en

  // ---- notifications (admin) ----
  bool inAppEnabled;
  bool whatsAppEnabled;
  bool smsEnabled;
  bool paymentReminders;
  bool renewalReminders;
  bool expiryReminders;
  bool promotions;
  bool maintenanceNotices;

  // ---- plans (admin) ----
  int trialDays;
  int planDays;
  int graceDays;
  List<int> remindBeforeDays;
  List<int> remindAfterDays;

  // ---- messaging (admin) ----
  Map<String, String> templates;

  // ---- providers (admin, non-secret) ----
  String whatsAppProvider;
  String whatsAppSender;
  String smsProvider;
  String smsSender;

  GlobalSettings({
    this.appName = 'PendPoint',
    this.logoUrl = '',
    this.appVersion = '',
    this.supportPhone = '',
    this.supportEmail = '',
    this.supportWhatsApp = '',
    this.companyName = '',
    this.address = '',
    this.website = '',
    this.defaultLanguage = 'both',
    this.inAppEnabled = true,
    this.whatsAppEnabled = false,
    this.smsEnabled = false,
    this.paymentReminders = true,
    this.renewalReminders = true,
    this.expiryReminders = true,
    this.promotions = true,
    this.maintenanceNotices = true,
    this.trialDays = 14,
    this.planDays = 365,
    this.graceDays = 7,
    List<int>? remindBeforeDays,
    List<int>? remindAfterDays,
    Map<String, String>? templates,
    this.whatsAppProvider = '',
    this.whatsAppSender = '',
    this.smsProvider = '',
    this.smsSender = '',
  })  : remindBeforeDays = remindBeforeDays ?? [7, 3, 1],
        remindAfterDays = remindAfterDays ?? [1, 7],
        templates = {...defaultTemplates, ...?templates};

  String template(String type) =>
      templates[type] ?? defaultTemplates[type] ?? '';

  /// Whether the super admin switched [type] off in General Settings.
  bool allows(String type) => switch (type) {
        NoticeType.paymentReminder => paymentReminders,
        NoticeType.renewalReminder => renewalReminders,
        NoticeType.planExpiry || NoticeType.planExpired => expiryReminders,
        NoticeType.offer => promotions,
        NoticeType.maintenance => maintenanceNotices,
        _ => true,
      };

  bool channelEnabled(String channel) => switch (channel) {
        Channels.inApp => inAppEnabled,
        Channels.whatsApp => whatsAppEnabled,
        Channels.sms => smsEnabled,
        _ => false,
      };

  Map<String, dynamic> generalMap() => {
        'appName': appName,
        'logoUrl': logoUrl,
        'appVersion': appVersion,
        'supportPhone': supportPhone,
        'supportEmail': supportEmail,
        'supportWhatsApp': supportWhatsApp,
        'companyName': companyName,
        'address': address,
        'website': website,
        'defaultLanguage': defaultLanguage,
      };

  Map<String, dynamic> adminMap() => {
        'inAppEnabled': inAppEnabled,
        'whatsAppEnabled': whatsAppEnabled,
        'smsEnabled': smsEnabled,
        'paymentReminders': paymentReminders,
        'renewalReminders': renewalReminders,
        'expiryReminders': expiryReminders,
        'promotions': promotions,
        'maintenanceNotices': maintenanceNotices,
        'trialDays': trialDays,
        'planDays': planDays,
        'graceDays': graceDays,
        'remindBeforeDays': remindBeforeDays,
        'remindAfterDays': remindAfterDays,
        'templates': templates,
        'whatsAppProvider': whatsAppProvider,
        'whatsAppSender': whatsAppSender,
        'smsProvider': smsProvider,
        'smsSender': smsSender,
      };

  factory GlobalSettings.fromMaps(
      Map<String, dynamic>? g, Map<String, dynamic>? a) {
    g ??= const {};
    a ??= const {};
    String s(Map m, String k, String d) => (m[k] as String?) ?? d;
    bool b(String k, bool d) => (a![k] as bool?) ?? d;
    int i(String k, int d) => (a![k] as num?)?.toInt() ?? d;
    final t = a['templates'];
    return GlobalSettings(
      appName: s(g, 'appName', 'PendPoint'),
      logoUrl: s(g, 'logoUrl', ''),
      appVersion: s(g, 'appVersion', ''),
      supportPhone: s(g, 'supportPhone', ''),
      supportEmail: s(g, 'supportEmail', ''),
      supportWhatsApp: s(g, 'supportWhatsApp', ''),
      companyName: s(g, 'companyName', ''),
      address: s(g, 'address', ''),
      website: s(g, 'website', ''),
      defaultLanguage: s(g, 'defaultLanguage', 'both'),
      inAppEnabled: b('inAppEnabled', true),
      whatsAppEnabled: b('whatsAppEnabled', false),
      smsEnabled: b('smsEnabled', false),
      paymentReminders: b('paymentReminders', true),
      renewalReminders: b('renewalReminders', true),
      expiryReminders: b('expiryReminders', true),
      promotions: b('promotions', true),
      maintenanceNotices: b('maintenanceNotices', true),
      trialDays: i('trialDays', 14),
      planDays: i('planDays', 365),
      graceDays: i('graceDays', 7),
      remindBeforeDays: _ints(a['remindBeforeDays'], [7, 3, 1]),
      remindAfterDays: _ints(a['remindAfterDays'], [1, 7]),
      templates: t is Map
          ? {for (final e in t.entries) '${e.key}': '${e.value}'}
          : null,
      whatsAppProvider: s(a, 'whatsAppProvider', ''),
      whatsAppSender: s(a, 'whatsAppSender', ''),
      smsProvider: s(a, 'smsProvider', ''),
      smsSender: s(a, 'smsSender', ''),
    );
  }
}

/// plans/{planId} — a subscription plan the super admin offers.
class Plan {
  final String id;
  final String name;
  final int durationDays;
  final double price;
  final bool active;
  final String description;
  const Plan({
    required this.id,
    required this.name,
    required this.durationDays,
    required this.price,
    this.active = true,
    this.description = '',
  });
  Map<String, dynamic> toMap() => {
        'name': name,
        'durationDays': durationDays,
        'price': price,
        'active': active,
        'description': description,
      };
  factory Plan.fromMap(String id, Map<String, dynamic> m) => Plan(
        id: id,
        name: (m['name'] ?? id) as String,
        durationDays: (m['durationDays'] as num?)?.toInt() ?? 365,
        price: _num(m['price']),
        active: (m['active'] as bool?) ?? true,
        description: (m['description'] ?? '') as String,
      );
}

/// stores/{storeId}/payments/{paymentId} — a subscription payment of one
/// store (recorded by hand; no payment gateway).
class StorePayment {
  final String id;
  final double amount;
  final String currency;
  final DateTime paymentDate;
  final String method;
  final String transactionId;
  final String? planId;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final String status;
  final String recordedBy;
  final String notes;
  final DateTime createdAt;
  const StorePayment({
    required this.id,
    required this.amount,
    this.currency = 'INR',
    required this.paymentDate,
    this.method = '',
    this.transactionId = '',
    this.planId,
    this.periodStart,
    this.periodEnd,
    this.status = PaymentStatus.paid,
    required this.recordedBy,
    this.notes = '',
    required this.createdAt,
  });
  Map<String, dynamic> toMap() => {
        'amount': amount,
        'currency': currency,
        'paymentDate': _iso(paymentDate),
        'paymentMethod': method,
        'transactionId': transactionId,
        'planId': planId,
        'periodStart': _iso(periodStart),
        'periodEnd': _iso(periodEnd),
        'status': status,
        'recordedBy': recordedBy,
        'notes': notes,
        'createdAt': _iso(createdAt),
      };
  factory StorePayment.fromMap(String id, Map<String, dynamic> m) =>
      StorePayment(
        id: id,
        amount: _num(m['amount']),
        currency: (m['currency'] ?? 'INR') as String,
        paymentDate: _date(m['paymentDate']) ?? DateTime.now(),
        method: (m['paymentMethod'] ?? '') as String,
        transactionId: (m['transactionId'] ?? '') as String,
        planId: m['planId'] as String?,
        periodStart: _date(m['periodStart']),
        periodEnd: _date(m['periodEnd']),
        status: (m['status'] ?? PaymentStatus.paid) as String,
        recordedBy: (m['recordedBy'] ?? '') as String,
        notes: (m['notes'] ?? '') as String,
        createdAt: _date(m['createdAt']) ?? DateTime.now(),
      );
}

/// notifications/{id} — one in-app notification for the super admin
/// ([Audience.superAdmin]) or for one store ([Audience.storeAdmin] /
/// [Audience.storeAll]). [storeId] is the store it is about / for. Read
/// state is per user ([readBy]: uid → time).
class AppNotification {
  final String id;
  final String? storeId;
  final String audience;
  final String type;
  final String title;
  final String message;
  final String priority; // low | normal | high | urgent
  final String? entityType;
  final String? entityId;
  final List<String> channels;
  final Map<String, String> channelStatus;
  final String senderUid;
  final String status; // sent | scheduled
  final DateTime createdAt;
  final DateTime visibleFrom;
  final DateTime? expiresAt;
  final Map<String, String> readBy;
  final String? batchId;
  final String? link;
  final String? imageUrl;

  const AppNotification({
    required this.id,
    this.storeId,
    required this.audience,
    required this.type,
    required this.title,
    required this.message,
    this.priority = 'normal',
    this.entityType,
    this.entityId,
    this.channels = const [Channels.inApp],
    this.channelStatus = const {},
    required this.senderUid,
    this.status = 'sent',
    required this.createdAt,
    required this.visibleFrom,
    this.expiresAt,
    this.readBy = const {},
    this.batchId,
    this.link,
    this.imageUrl,
  });

  bool isReadBy(String uid) => readBy.containsKey(uid);
  bool visibleAt(DateTime now) =>
      !visibleFrom.isAfter(now) && (expiresAt == null || expiresAt!.isAfter(now));

  Map<String, dynamic> toMap() => {
        'storeId': storeId,
        'recipientRole': audience,
        'type': type,
        'title': title,
        'message': message,
        'priority': priority,
        'entityType': entityType,
        'entityId': entityId,
        'channels': channels,
        'channelStatus': channelStatus,
        'senderUid': senderUid,
        'status': status,
        'createdAt': _iso(createdAt),
        'visibleFrom': _iso(visibleFrom),
        'expiresAt': _iso(expiresAt),
        'readBy': readBy,
        'batchId': batchId,
        'link': link,
        'imageUrl': imageUrl,
      };

  factory AppNotification.fromMap(String id, Map<String, dynamic> m) {
    final created = _date(m['createdAt']) ?? DateTime.now();
    Map<String, String> strMap(Object? v) => v is Map
        ? {for (final e in v.entries) '${e.key}': '${e.value}'}
        : const {};
    return AppNotification(
      id: id,
      storeId: m['storeId'] as String?,
      audience: (m['recipientRole'] ?? Audience.superAdmin) as String,
      type: (m['type'] ?? NoticeType.system) as String,
      title: (m['title'] ?? '') as String,
      message: (m['message'] ?? '') as String,
      priority: (m['priority'] ?? 'normal') as String,
      entityType: m['entityType'] as String?,
      entityId: m['entityId'] as String?,
      channels: [for (final c in (m['channels'] as List? ?? const [])) '$c'],
      channelStatus: strMap(m['channelStatus']),
      senderUid: (m['senderUid'] ?? '') as String,
      status: (m['status'] ?? 'sent') as String,
      createdAt: created,
      visibleFrom: _date(m['visibleFrom']) ?? created,
      expiresAt: _date(m['expiresAt']),
      readBy: strMap(m['readBy']),
      batchId: m['batchId'] as String?,
      link: m['link'] as String?,
      imageUrl: m['imageUrl'] as String?,
    );
  }
}

/// platformAnnouncements/{id} — a feature/offer/maintenance announcement.
/// (Not `announcements`: that collection in this Firebase project belongs
/// to another application.) Delivered to the targeted stores as in-app
/// notifications when published.
class Announcement {
  final String id;
  final String title;
  final String message;
  final String? imageUrl;
  final String? link;
  final String priority;
  final String target; // all | active | selected | plan
  final List<String> storeIds;
  final String? planId;
  final List<String> channels;
  final DateTime startAt;
  final DateTime? expiresAt;
  final String createdBy;
  final DateTime createdAt;
  final int deliveredTo;

  const Announcement({
    required this.id,
    required this.title,
    required this.message,
    this.imageUrl,
    this.link,
    this.priority = 'normal',
    this.target = 'all',
    this.storeIds = const [],
    this.planId,
    this.channels = const [Channels.inApp],
    required this.startAt,
    this.expiresAt,
    required this.createdBy,
    required this.createdAt,
    this.deliveredTo = 0,
  });

  Map<String, dynamic> toMap() => {
        'title': title,
        'message': message,
        'imageUrl': imageUrl,
        'link': link,
        'priority': priority,
        'target': target,
        'storeIds': storeIds,
        'planId': planId,
        'channels': channels,
        'startAt': _iso(startAt),
        'expiresAt': _iso(expiresAt),
        'createdBy': createdBy,
        'createdAt': _iso(createdAt),
        'deliveredTo': deliveredTo,
      };

  factory Announcement.fromMap(String id, Map<String, dynamic> m) =>
      Announcement(
        id: id,
        title: (m['title'] ?? '') as String,
        message: (m['message'] ?? '') as String,
        imageUrl: m['imageUrl'] as String?,
        link: m['link'] as String?,
        priority: (m['priority'] ?? 'normal') as String,
        target: (m['target'] ?? 'all') as String,
        storeIds: [for (final s in (m['storeIds'] as List? ?? const [])) '$s'],
        planId: m['planId'] as String?,
        channels: [for (final c in (m['channels'] as List? ?? const [])) '$c'],
        startAt: _date(m['startAt']) ?? DateTime.now(),
        expiresAt: _date(m['expiresAt']),
        createdBy: (m['createdBy'] ?? '') as String,
        createdAt: _date(m['createdAt']) ?? DateTime.now(),
        deliveredTo: (m['deliveredTo'] as num?)?.toInt() ?? 0,
      );
}
