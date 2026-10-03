import 'dart:async';

import '../data/platform_repository.dart';
import '../data/repository.dart';
import '../models/app_settings.dart';
import '../models/platform.dart';
import '../models/staff.dart';
import '../models/store.dart';
import '../services/notification_service.dart';
import '../utils/formatters.dart';
import 'reminder_engine.dart';

/// Who gets a "send notification".
abstract final class RecipientGroup {
  static const all = 'all';
  static const active = 'active';
  static const expiring = 'expiring';
  static const expired = 'expired';
  static const selected = 'selected';
  static const owner = 'owner'; // one selected store's owner
}

/// What a send / reminder run did — per channel, honestly.
class SendReport {
  final int stores;
  final Map<String, Map<String, int>> byChannel; // channel → status → count
  const SendReport(this.stores, this.byChannel);
  int count(String channel, String status) => byChannel[channel]?[status] ?? 0;
  bool get anyProviderMissing => byChannel.values
      .any((m) => (m[ChannelStatus.providerRequired] ?? 0) > 0);
}

/// Super Admin platform logic (settings, store/staff change notifications,
/// field-level store audit, plans and payments, sending, reminders,
/// announcements) and every user's notification feed. All store data it
/// reads/writes is checked by firestore.rules as well.
class PlatformService {
  final Repository repo;
  final NotificationService channels;
  PlatformService(this.repo, {NotificationService? channels})
      : channels = channels ?? NotificationService();

  PlatformRepository get _p => repo.platform;
  StoreContext? get _ctx => repo.context;
  bool get _isSuperAdmin => _ctx?.isSuperAdmin ?? false;
  String get _uid => repo.currentUserId ?? _ctx?.uid ?? '';

  void _requireSuperAdmin() {
    if (!_isSuperAdmin) {
      throw const StoreContextException(
          'Only a super admin can manage the platform.');
    }
  }

  // ---- global settings ----

  GlobalSettings? _settings;

  /// General settings for everyone; the admin part only for a super admin.
  Future<GlobalSettings> settings({bool refresh = false}) async {
    if (_settings != null && !refresh) return _settings!;
    try {
      return _settings = await _p.loadSettings(admin: _isSuperAdmin);
    } catch (_) {
      return GlobalSettings(); // offline / no access: built-in defaults
    }
  }

  Future<String?> saveSettings(GlobalSettings s) async {
    _requireSuperAdmin();
    if (s.appName.trim().isEmpty) {
      return 'ॲपचे नाव लिहा · Enter the application name';
    }
    if (s.trialDays < 0 || s.planDays <= 0 || s.graceDays < 0) {
      return 'दिवस चुकीचे · Check the number of days';
    }
    try {
      await _p.saveSettings(s);
    } catch (e) {
      return _err(e);
    }
    _settings = s;
    _audit('GLOBAL', 'SETTINGS_UPDATED', 'SETTINGS', 'general');
    return null;
  }

  // ---- one store's own settings ----

  /// Whether this login may change [storeId]'s settings: a super admin, or
  /// that store's own admin (the rules say the same).
  bool canEditStoreSettings(String storeId) {
    final ctx = _ctx;
    if (ctx == null) return false;
    return ctx.isSuperAdmin || (ctx.isStoreAdmin && ctx.storeId == storeId);
  }

  Future<AppSettings> storeSettings(String storeId) async {
    if (!canEditStoreSettings(storeId) && _ctx?.storeId != storeId) {
      throw const StoreContextException('Settings belong to their store.');
    }
    return await _p.loadStoreSettings(storeId) ?? AppSettings();
  }

  /// Saves [after] as [storeId]'s settings (that store only) and audits
  /// each changed setting with its old and new value.
  Future<String?> saveStoreSettings(
      String storeId, AppSettings before, AppSettings after) async {
    if (!canEditStoreSettings(storeId)) {
      return 'फक्त या दुकानाचा मालक सेटिंग्ज बदलू शकतो · Only this store\'s admin can change its settings';
    }
    if (after.shop.trim().isEmpty) {
      return 'दुकानाचे नाव लिहा · Enter the shop name';
    }
    try {
      await _p.saveStoreSettings(storeId, after);
      // A new shop name renames the store too (one name everywhere).
      if (after.shop.trim() != before.shop.trim()) {
        final st = await repo.loadStore(storeId);
        if (st != null && st.storeName != after.shop.trim()) {
          final renamed = st.copyWith(
              storeName: after.shop.trim(), updatedAt: DateTime.now());
          await _p.updateStoreFields(storeId, {
            'storeName': renamed.storeName,
            'updatedAt': renamed.updatedAt.toIso8601String(),
          });
          await storeChanged(st, renamed);
        }
      }
    } catch (e) {
      return _err(e);
    }
    auditSettings(storeId, before, after);
    return null;
  }

  /// One audit entry per changed setting of [storeId].
  void auditSettings(String storeId, AppSettings before, AppSettings after) {
    final a = before.toMap(), b = after.toMap();
    final now = DateTime.now();
    for (final k in b.keys) {
      if ('${a[k]}' == '${b[k]}') continue;
      unawaited(repo
          .addAudit(AuditEntry(
              storeId: storeId,
              userId: _uid,
              role: _ctx?.role ?? '',
              action: 'SETTING_CHANGED',
              entityType: 'SETTINGS',
              entityId: storeId,
              at: now,
              field: k,
              oldValue: a[k] == null ? '' : '${a[k]}',
              newValue: b[k] == null ? '' : '${b[k]}'))
          .catchError((_) {}));
    }
  }

  // ---- notification feeds ----

  /// This user's feed (from their StoreContext — never from input).
  NotificationQuery? myQuery() {
    final ctx = _ctx;
    if (ctx == null) return null;
    final sid = ctx.storeId;
    if (ctx.isSuperAdmin) {
      // Inside one store: only that store's notifications (what its users
      // see, plus platform events about it). All stores only on the Super
      // Admin screens (no store open).
      return sid == null
          ? const NotificationQuery(audiences: [Audience.superAdmin])
          : NotificationQuery(storeId: sid, audiences: const [
              Audience.storeAll,
              Audience.storeAdmin,
              Audience.superAdmin,
            ]);
    }
    if (sid == null) return null;
    return NotificationQuery(
        storeId: sid,
        audiences: ctx.isStoreAdmin
            ? const [Audience.storeAll, Audience.storeAdmin]
            : const [Audience.storeAll]);
  }

  Stream<List<AppNotification>> watchMine() {
    final q = myQuery();
    if (q == null) return Stream.value(const []);
    return _p.watchNotifications(q).map((l) {
      final now = DateTime.now();
      return [for (final n in l) if (n.visibleAt(now)) n];
    });
  }

  /// What the super admin sent to stores (latest first).
  Stream<List<AppNotification>> watchSent() {
    _requireSuperAdmin();
    return _p.watchNotifications(const NotificationQuery(
        audiences: [Audience.storeAdmin, Audience.storeAll], limit: 60));
  }

  int unreadCount(List<AppNotification> l) =>
      l.where((n) => !n.isReadBy(_uid)).length;

  Future<void> markRead(Iterable<AppNotification> list) async {
    final ids = [for (final n in list) if (!n.isReadBy(_uid)) n.id];
    if (ids.isEmpty) return;
    await _p.markRead(ids, _uid);
  }

  // ---- building notifications ----

  AppNotification _note({
    required String? storeId,
    required String audience,
    required String type,
    required String title,
    required String message,
    String priority = 'normal',
    String? entityType,
    String? entityId,
    List<String> channels = const [Channels.inApp],
    Map<String, String> channelStatus = const {Channels.inApp: ChannelStatus.delivered},
    DateTime? visibleFrom,
    DateTime? expiresAt,
    String? batchId,
    String? link,
    String? imageUrl,
  }) {
    final now = DateTime.now();
    return AppNotification(
      id: _p.newId(),
      storeId: storeId,
      audience: audience,
      type: type,
      title: title,
      message: message,
      priority: priority,
      entityType: entityType,
      entityId: entityId,
      channels: channels,
      channelStatus: channelStatus,
      senderUid: _uid,
      status: visibleFrom != null && visibleFrom.isAfter(now) ? 'scheduled' : 'sent',
      createdAt: now,
      visibleFrom: visibleFrom ?? now,
      expiresAt: expiresAt,
      // The super admin's own actions arrive already read (no noise);
      // a store admin's change is unread for the super admin.
      readBy: audience == Audience.superAdmin && _isSuperAdmin
          ? {_uid: now.toIso8601String()}
          : const {},
      batchId: batchId,
      link: link,
      imageUrl: imageUrl,
    );
  }

  /// Records an event for the super admin. A failed write never blocks the
  /// change that caused it.
  Future<void> notifySuperAdmin(String type, String title, String message,
      {String? storeId, String? entityType, String? entityId, String priority = 'normal'}) async {
    try {
      await _p.addNotifications([
        _note(
            storeId: storeId,
            audience: Audience.superAdmin,
            type: type,
            title: title,
            message: message,
            priority: priority,
            entityType: entityType,
            entityId: entityId)
      ]);
    } catch (_) {}
  }

  Future<void> _notifyStore(String storeId, String type, String title, String message,
      {String? audience, String priority = 'normal'}) async {
    final g = await settings();
    if (!g.inAppEnabled || !g.allows(type)) return;
    try {
      await _p.addNotifications([
        _note(
            storeId: storeId,
            audience: audience ??
                (NoticeType.forWholeStore(type) ? Audience.storeAll : Audience.storeAdmin),
            type: type,
            title: title,
            message: message,
            priority: priority)
      ]);
    } catch (_) {}
  }

  // ---- store changes: audit per field + notifications ----

  static const _labels = {
    'storeName': 'Store name',
    'legalName': 'Legal name',
    'address': 'Address',
    'city': 'City',
    'state': 'State',
    'pincode': 'Pincode',
    'phone': 'Phone',
    'email': 'Email',
    'gstNumber': 'GST number',
    'status': 'Status',
    'ownerName': 'Owner name',
    'ownerEmail': 'Owner email',
    'ownerPhone': 'Owner phone',
    'ownerWhatsApp': 'Owner WhatsApp',
    'notifyChannel': 'Notification channel',
    'planName': 'Plan',
    'planStatus': 'Plan status',
    'planExpiryDate': 'Plan expiry date',
    'renewalAmount': 'Renewal amount',
    'paymentStatus': 'Payment status',
    'nextPaymentDate': 'Next payment date',
    'gracePeriodUntil': 'Grace period',
  };

  static Map<String, (String, String)> diff(Store before, Store after) {
    final a = before.describe(), b = after.describe();
    return {
      for (final k in b.keys)
        if (a[k] != b[k]) k: (a[k] ?? '', b[k] ?? ''),
    };
  }

  static String _show(String v) => v.isEmpty ? '(none)' : v;

  /// After [before] became [after]: one audit entry per changed field and
  /// ONE notification for the super admin (activation/deactivation/plan/
  /// payment/update — whichever matters most). [notify] false: audit only
  /// (the caller sends its own, more specific notification).
  Future<void> storeChanged(Store before, Store after, {bool notify = true}) async {
    final changes = diff(before, after);
    if (changes.isEmpty) return;
    final now = DateTime.now();
    for (final e in changes.entries) {
      unawaited(repo
          .addAudit(AuditEntry(
              storeId: after.id,
              userId: _uid,
              role: _ctx?.role ?? '',
              action: 'STORE_FIELD_CHANGED',
              entityType: 'STORE',
              entityId: after.id,
              at: now,
              field: e.key,
              oldValue: e.value.$1,
              newValue: e.value.$2))
          .catchError((_) {}));
    }
    if (!notify) return;
    final id = after.id;
    if (changes.containsKey('status')) {
      final on = after.isActive;
      await notifySuperAdmin(
          on ? NoticeType.storeActivated : NoticeType.storeDeactivated,
          on ? 'Store Activated' : 'Store Deactivated',
          'Store $id has been ${on ? 'activated' : 'deactivated'}.',
          storeId: id, entityType: 'STORE', entityId: id,
          priority: on ? 'normal' : 'high');
      await _notifyStore(
          id,
          on ? NoticeType.storeActivated : NoticeType.storeDeactivated,
          on ? 'Store activated' : 'Store deactivated',
          on
              ? '${after.storeName} is active again. You can continue working.'
              : '${after.storeName} has been deactivated. Please contact support.',
          audience: Audience.storeAll);
      changes.remove('status');
      if (changes.isEmpty) return;
    }
    final planKeys = {'planName', 'planStatus', 'planExpiryDate', 'renewalAmount'};
    final type = changes.keys.any(planKeys.contains)
        ? NoticeType.storePlanChanged
        : changes.containsKey('paymentStatus')
            ? (after.paymentStatus == PaymentStatus.paid
                ? NoticeType.paymentReceived
                : after.paymentStatus == PaymentStatus.failed
                    ? NoticeType.paymentFailed
                    : NoticeType.paymentPending)
            : NoticeType.storeUpdated;
    final parts = [
      for (final e in changes.entries)
        '${_labels[e.key] ?? e.key} changed from ${_show(e.value.$1)} to ${_show(e.value.$2)}'
    ];
    await notifySuperAdmin(
        type,
        type == NoticeType.storePlanChanged ? 'Store Plan Changed' : 'Store Updated',
        '$id has been updated. ${parts.join('; ')}.',
        storeId: id, entityType: 'STORE', entityId: id);
  }

  Future<void> storeCreated(Store st) => notifySuperAdmin(
      NoticeType.storeCreated,
      'Store Created',
      'New store ${st.id} "${st.storeName}" has been created.',
      storeId: st.id, entityType: 'STORE', entityId: st.id);

  /// A store admin edits their own store's name/contact details (only
  /// [Store.ownerEditable]; plan/payment/status stay the super admin's).
  Future<String?> updateMyStore(Store before, Store after) async {
    final ctx = _ctx;
    if (ctx == null || ctx.storeId != before.id || !(ctx.isStoreAdmin || ctx.isSuperAdmin)) {
      return 'परवानगी नाही · Not allowed';
    }
    if (after.storeName.trim().isEmpty) return 'दुकानाचे नाव लिहा · Enter the store name';
    final a = before.toMap(), b = after.toMap();
    final fields = {
      for (final k in Store.ownerEditable)
        if (a[k] != b[k]) k: b[k],
    };
    if (fields.isEmpty) return null;
    fields['updatedAt'] = DateTime.now().toIso8601String();
    try {
      await _p.updateStoreFields(before.id, fields);
      // The shop name on bills is the store's name — one name everywhere.
      if (fields.containsKey('storeName')) {
        await _p.setShopName(before.id, after.storeName);
      }
    } catch (e) {
      return _err(e);
    }
    await storeChanged(before, after);
    return null;
  }

  /// After the super admin renamed a store: its shop settings get the same
  /// name.
  Future<void> syncShopName(String storeId, String name) async {
    try {
      await _p.setShopName(storeId, name);
    } catch (_) {}
  }

  // ---- staff changes ----

  Future<void> staffChanged(Staff? before, Staff after, String storeId) async {
    final who = '${after.name} (${after.isAdmin ? 'Store Admin' : 'Staff'})';
    if (before == null) {
      await notifySuperAdmin(NoticeType.staffAdded,
          after.isAdmin ? 'Store Admin Created' : 'Staff Added',
          '$who was added to store $storeId.',
          storeId: storeId, entityType: 'STAFF', entityId: after.id);
      return;
    }
    if (before.active && !after.active) {
      await notifySuperAdmin(NoticeType.staffDisabled, 'Staff Disabled',
          '$who was disabled in store $storeId.',
          storeId: storeId, entityType: 'STAFF', entityId: after.id);
      return;
    }
    if (!before.active && after.active) {
      await notifySuperAdmin(NoticeType.staffActivated, 'Staff Activated',
          '$who was activated in store $storeId.',
          storeId: storeId, entityType: 'STAFF', entityId: after.id);
      return;
    }
    final parts = [
      if (before.role != after.role) 'role ${before.role} → ${after.role}',
      if (before.canOverride != after.canOverride ||
          before.maxDiscountPct != after.maxDiscountPct)
        'permissions changed (price override ${after.canOverride ? 'on' : 'off'}, max discount ${after.maxDiscountPct.round()}%)',
    ];
    if (parts.isEmpty) return; // name/phone only — not worth a notification
    await notifySuperAdmin(NoticeType.staffChanged, 'Staff Changed',
        '$who in store $storeId: ${parts.join('; ')}.',
        storeId: storeId, entityType: 'STAFF', entityId: after.id);
  }

  // ---- plans, payments, renewals ----

  Future<List<Plan>> plans() => _p.listPlans();

  Future<String?> savePlan(Plan plan) async {
    _requireSuperAdmin();
    if (plan.name.trim().isEmpty) return 'प्लॅनचे नाव लिहा · Enter the plan name';
    if (plan.durationDays <= 0 || plan.price < 0) {
      return 'दिवस / किंमत चुकीची · Check the duration and price';
    }
    try {
      await _p.savePlan(plan);
    } catch (e) {
      return _err(e);
    }
    _audit('GLOBAL', 'PLAN_SAVED', 'PLAN', plan.id, note: plan.name);
    return null;
  }

  Future<List<StorePayment>> payments(String storeId) {
    final ctx = _ctx;
    if (ctx == null || !(ctx.isSuperAdmin || (ctx.isStoreAdmin && ctx.storeId == storeId))) {
      throw const StoreContextException('Payment records belong to their store.');
    }
    return _p.listPayments(storeId);
  }

  Map<String, String> _values(Store st, GlobalSettings g, {double? amount}) {
    final exp = st.planExpiryDate;
    final due = st.nextPaymentDate ?? exp;
    return {
      'storeName': st.storeName,
      'storeCode': st.id,
      'amount': money(amount ?? st.renewalAmount ?? 0),
      'dueDate': due == null ? '' : ddmmyyyy(due),
      'expiryDate': exp == null ? '' : ddmmyyyy(exp),
      'days': '${st.daysToExpiry(DateTime.now()) ?? ''}',
      'appName': g.appName,
      'supportPhone': g.supportPhone,
    };
  }

  /// Changes a store's plan (super admin). Upgrade/downgrade is told apart
  /// by price. Audit per field, the super admin and the owner are told.
  Future<String?> changePlan(Store before,
      {Plan? plan,
      String? planStatus,
      DateTime? expiry,
      double? renewalAmount,
      String notes = ''}) async {
    _requireSuperAdmin();
    final g = await settings();
    final after = before.copyWith(
      planId: plan?.id,
      planName: plan?.name,
      planStatus: planStatus,
      planStartDate: plan != null && plan.id != before.planId ? DateTime.now() : null,
      planExpiryDate: expiry,
      nextPaymentDate: expiry,
      gracePeriodUntil: expiry?.add(Duration(days: g.graceDays)),
      renewalAmount: renewalAmount ?? plan?.price,
      updatedAt: DateTime.now(),
    );
    final fields = _planFields(after);
    try {
      await _p.updateStoreFields(before.id, fields);
    } catch (e) {
      return _err(e);
    }
    await storeChanged(before, after, notify: false);
    final oldPlan = before.planId == null
        ? null
        : (await _safePlans()).where((p) => p.id == before.planId).firstOrNull;
    final how = plan == null || oldPlan == null || plan.id == oldPlan.id
        ? 'changed'
        : plan.price > oldPlan.price
            ? 'upgraded'
            : plan.price < oldPlan.price
                ? 'downgraded'
                : 'changed';
    final what = [
      if (plan != null) 'plan ${before.planName ?? '(none)'} → ${plan.name}',
      if (planStatus != null && planStatus != before.planStatus) 'status → $planStatus',
      if (expiry != null) 'valid until ${ddmmyyyy(expiry)}',
      if (notes.trim().isNotEmpty) 'note: ${notes.trim()}',
    ].join('; ');
    await notifySuperAdmin(NoticeType.storePlanChanged, 'Store Plan Changed',
        '${before.id} plan $how: $what.',
        storeId: before.id, entityType: 'STORE', entityId: before.id);
    await _notifyStore(before.id, NoticeType.storePlanChanged, 'Your plan was updated',
        'Your ${g.appName} plan for ${after.storeName} was $how${expiry == null ? '' : '. Valid until ${ddmmyyyy(expiry)}'}.');
    return null;
  }

  Map<String, dynamic> _planFields(Store s) {
    final m = s.toMap();
    return {
      for (final k in const [
        'planId', 'planName', 'planStatus', 'planStartDate', 'planExpiryDate',
        'renewalAmount', 'paymentStatus', 'lastPaymentDate', 'nextPaymentDate',
        'gracePeriodUntil', 'updatedAt',
      ])
        k: m[k],
    };
  }

  Future<List<Plan>> _safePlans() async {
    try {
      return await _p.listPlans();
    } catch (_) {
      return const [];
    }
  }

  /// Records a payment by hand (no gateway). A PAID renewal extends the
  /// plan: new expiry = later of today / current expiry + the plan's days
  /// (or [extendTo]); the store, audit trail, super admin and owner are
  /// all updated. Returns an error, or null.
  Future<String?> recordPayment(Store before, {
    required double amount,
    required String status,
    String method = '',
    String transactionId = '',
    Plan? plan,
    bool renew = true,
    DateTime? extendTo,
    DateTime? paymentDate,
    String notes = '',
  }) async {
    _requireSuperAdmin();
    if (amount <= 0) return 'रक्कम लिहा · Enter the amount';
    if (!PaymentStatus.all.contains(status)) return 'स्थिती चुकीची · Bad status';
    final g = await settings();
    final now = DateTime.now();
    final paidOn = paymentDate ?? now;
    final p0 = plan ??
        (before.planId == null
            ? null
            : (await _safePlans()).where((p) => p.id == before.planId).firstOrNull);
    final paid = status == PaymentStatus.paid;
    DateTime? newExpiry;
    DateTime? periodStart;
    if (paid && renew) {
      final from = before.planExpiryDate != null && before.planExpiryDate!.isAfter(now)
          ? before.planExpiryDate!
          : now;
      periodStart = from;
      newExpiry = extendTo ?? from.add(Duration(days: p0?.durationDays ?? g.planDays));
    }
    final payment = StorePayment(
      id: _p.newId(),
      amount: amount,
      paymentDate: paidOn,
      method: method.trim(),
      transactionId: transactionId.trim(),
      planId: p0?.id ?? before.planId,
      periodStart: periodStart,
      periodEnd: newExpiry,
      status: status,
      recordedBy: _uid,
      notes: notes.trim(),
      createdAt: now,
    );
    final after = before.copyWith(
      paymentStatus: status,
      lastPaymentDate: paid ? paidOn : null,
      planId: newExpiry != null ? p0?.id : null,
      planName: newExpiry != null ? p0?.name : null,
      planStatus: newExpiry != null ? PlanStatus.active : null,
      planExpiryDate: newExpiry,
      nextPaymentDate: newExpiry,
      gracePeriodUntil: newExpiry?.add(Duration(days: g.graceDays)),
      renewalAmount: newExpiry != null ? (p0?.price ?? amount) : null,
      updatedAt: now,
    );
    try {
      await _p.addPayment(before.id, payment);
      await _p.updateStoreFields(before.id, _planFields(after));
    } catch (e) {
      return _err(e);
    }
    await storeChanged(before, after, notify: false);
    _audit(before.id, paid ? (newExpiry != null ? 'PLAN_RENEWED' : 'PAYMENT_RECORDED') : 'PAYMENT_${status.toUpperCase()}',
        'PAYMENT', payment.id, note: '${money(amount)} $status');
    final amt = money(amount);
    if (paid) {
      final until = newExpiry == null ? '' : ' Plan renewed until ${ddmmyyyy(newExpiry)}.';
      await notifySuperAdmin(newExpiry != null ? NoticeType.planRenewed : NoticeType.paymentReceived,
          newExpiry != null ? 'Renewal Recorded' : 'Payment Received',
          'Payment of $amt received from ${before.id} "${before.storeName}".$until',
          storeId: before.id, entityType: 'PAYMENT', entityId: payment.id);
      await _notifyStore(
          before.id,
          NoticeType.paymentConfirmation,
          'Payment received',
          renderTemplate(g.template(NoticeType.paymentConfirmation),
              _values(after, g, amount: amount)));
    } else {
      final type = status == PaymentStatus.failed
          ? NoticeType.paymentFailed
          : status == PaymentStatus.pending
              ? NoticeType.paymentPending
              : NoticeType.storeUpdated;
      await notifySuperAdmin(type, 'Payment ${status[0].toUpperCase()}${status.substring(1)}',
          'Payment of $amt for ${before.id} "${before.storeName}" is $status.',
          storeId: before.id, entityType: 'PAYMENT', entityId: payment.id,
          priority: status == PaymentStatus.failed ? 'high' : 'normal');
    }
    return null;
  }

  // ---- sending ----

  /// The stores in [group] (from the live store list).
  static List<Store> resolve(List<Store> stores, String group,
      {Set<String> selected = const {}, required DateTime now, int expiringWithinDays = 7}) {
    String st(Store s) => s.planStatusAt(now, expiringWithinDays: expiringWithinDays);
    return switch (group) {
      RecipientGroup.all => stores,
      RecipientGroup.active => [for (final s in stores) if (s.isActive) s],
      RecipientGroup.expiring => [for (final s in stores) if (st(s) == PlanStatus.expiring) s],
      RecipientGroup.expired => [for (final s in stores) if (st(s) == PlanStatus.expired) s],
      _ => [for (final s in stores) if (selected.contains(s.id)) s],
    };
  }

  /// Sends one notification to every store in [stores]: in-app for
  /// [audience] of each store, plus WhatsApp/SMS to each owner where a
  /// provider exists (otherwise recorded as provider_required — never as
  /// sent). [message] may use {placeholders}. [scheduledFor]: in-app shows
  /// from then; WhatsApp/SMS have no scheduler (reported).
  Future<SendReport> send({
    required List<Store> stores,
    required String type,
    required String subject,
    required String message,
    required Set<String> channels,
    String? audience,
    DateTime? scheduledFor,
    DateTime? expiresAt,
    String priority = 'normal',
    String? link,
    String? imageUrl,
  }) async {
    _requireSuperAdmin();
    final g = await settings();
    final batch = _p.newId();
    final notes = <AppNotification>[];
    final tally = <String, Map<String, int>>{};
    for (final st in stores) {
      final values = _values(st, g);
      final m = OutgoingMessage(
          store: st,
          type: type,
          title: renderTemplate(subject, values),
          message: renderTemplate(message, values));
      final status = await this.channels.deliver(m,
          selected: channels, settings: g, scheduledFor: scheduledFor);
      for (final e in status.entries) {
        final t = tally[e.key] ??= {};
        t[e.value] = (t[e.value] ?? 0) + 1;
      }
      final inApp = status[Channels.inApp];
      if (inApp == ChannelStatus.delivered || inApp == ChannelStatus.scheduled) {
        notes.add(_note(
            storeId: st.id,
            audience: audience ??
                (NoticeType.forWholeStore(type) ? Audience.storeAll : Audience.storeAdmin),
            type: type,
            title: m.title,
            message: m.message,
            priority: priority,
            channels: channels.toList(),
            channelStatus: status,
            visibleFrom: scheduledFor,
            expiresAt: expiresAt,
            batchId: batch,
            link: link,
            imageUrl: imageUrl));
      }
    }
    await _p.addNotifications(notes);
    final report = SendReport(stores.length, tally);
    _audit('GLOBAL', 'NOTIFICATION_SENT', 'NOTIFICATION', batch,
        note: '$type → ${stores.length} store(s): ${_tallyText(report)}');
    return report;
  }

  static String _tallyText(SendReport r) => [
        for (final c in r.byChannel.entries)
          '${c.key} ${[for (final s in c.value.entries) '${s.key}=${s.value}'].join(',')}'
      ].join('; ');

  // ---- reminders ----

  /// Generates the plan reminders due today (see [dueReminders]) — each
  /// one only once (claimed in stores/{id}/reminders). Run by the super
  /// admin ("Run reminders now"); a backend scheduler can run the same
  /// rules later. Returns how many were generated.
  Future<int> runReminders(List<Store> stores, {DateTime? now}) async {
    _requireSuperAdmin();
    final g = await settings(refresh: true);
    final at = now ?? DateTime.now();
    var made = 0;
    for (final r in dueReminders(stores, g, at)) {
      final claimed = await _p.claimReminder(r.store.id, r.key, {
        'type': r.type,
        'daysToExpiry': r.daysToExpiry,
        'createdAt': at.toIso8601String(),
        'by': _uid,
      });
      if (!claimed) continue;
      final values = _values(r.store, g)..['days'] = '${r.daysToExpiry.abs()}';
      final title = switch (r.type) {
        NoticeType.planExpired => 'Plan expired',
        NoticeType.planExpiry => 'Plan expires today',
        _ => r.urgent ? 'Urgent: renew your plan' : 'Plan renewal reminder',
      };
      final template = r.type == NoticeType.renewalReminder && r.daysToExpiry <= 3
          ? g.template(NoticeType.planExpiry) // "expires in X days"
          : g.template(r.type);
      await send(
          stores: [r.store],
          type: r.type,
          subject: title,
          message: renderTemplate(template, values),
          channels: {Channels.inApp, Channels.whatsApp, Channels.sms},
          priority: r.urgent ? 'urgent' : 'high');
      made++;
    }
    if (made > 0) {
      await notifySuperAdmin(NoticeType.renewalReminder, 'Reminders Generated',
          '$made plan reminder(s) generated for stores whose plan is expiring or expired.');
    }
    return made;
  }

  // ---- announcements ----

  Future<List<Announcement>> announcements({int limit = 50}) async {
    try {
      return await _p.listAnnouncements(limit: limit);
    } catch (_) {
      return const [];
    }
  }

  /// Publishes [a] to the stores it targets (as in-app notifications for
  /// every user of each store, shown from [Announcement.startAt] until
  /// [Announcement.expiresAt]). Returns the number of stores, or throws.
  Future<int> publishAnnouncement(Announcement a, List<Store> allStores) async {
    _requireSuperAdmin();
    final now = DateTime.now();
    final targets = switch (a.target) {
      'selected' => [for (final s in allStores) if (a.storeIds.contains(s.id)) s],
      'active' => [for (final s in allStores) if (s.isActive) s],
      'plan' => [for (final s in allStores) if (s.planId != null && s.planId == a.planId) s],
      _ => allStores,
    };
    final report = await send(
        stores: targets,
        type: NoticeType.announcement,
        subject: a.title,
        message: a.message,
        channels: a.channels.toSet(),
        audience: Audience.storeAll,
        scheduledFor: a.startAt.isAfter(now) ? a.startAt : null,
        expiresAt: a.expiresAt,
        priority: a.priority,
        link: a.link,
        imageUrl: a.imageUrl);
    await _p.saveAnnouncement(Announcement.fromMap(a.id, {
      ...a.toMap(),
      'deliveredTo': report.stores,
    }));
    return report.stores;
  }

  String newId() => _p.newId();

  // ---- helpers ----

  void _audit(String storeId, String action, String type, String id, {String? note}) {
    unawaited(repo
        .addAudit(AuditEntry(
            storeId: storeId,
            userId: _uid,
            role: _ctx?.role ?? '',
            action: action,
            entityType: type,
            entityId: id,
            at: DateTime.now(),
            note: note))
        .catchError((_) {}));
  }

  static String _err(Object e) {
    final t = e.toString();
    if (t.contains('permission-denied')) {
      return 'परवानगी नाही · Permission denied';
    }
    return 'जतन झाले नाही · Could not save — $t';
  }
}

/// 31/12/2026
String ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
