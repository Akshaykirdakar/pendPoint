/// Multi-store (tenant) model.
///
/// One Firebase project serves many stores. Every store-owned document
/// carries `storeId`; a signed-in user's store comes from their protected
/// `staff/{uid}` record — never from anything the user types. Firestore
/// rules enforce the same boundary independently of this app.
library;

/// Roles. The stored values stay the ones the app already used ('admin',
/// 'staff') so existing staff records keep working unchanged; the
/// super-admin role is new.
abstract final class Roles {
  /// SUPER_ADMIN — manages stores and their users; may open any store.
  static const superAdmin = 'super_admin';

  /// STORE_ADMIN — the owner/admin of one store (existing 'admin').
  static const storeAdmin = 'admin';

  /// STAFF — counter staff of one store (existing 'staff').
  static const staff = 'staff';

  static const all = [superAdmin, storeAdmin, staff];
}

/// The store the app's data was in before multi-store: every existing
/// record is migrated to it (see tools/migrate_multistore.mjs).
const legacyStoreId = 'STORE001';

enum StoreStatus { active, inactive }

extension StoreStatusX on StoreStatus {
  String get id => this == StoreStatus.active ? 'ACTIVE' : 'INACTIVE';
  static StoreStatus fromId(String? v) =>
      v == 'INACTIVE' ? StoreStatus.inactive : StoreStatus.active;
}

/// stores/{storeId}. The store code IS the document id, so it is unique by
/// construction and can never change (it is the security boundary).
class Store {
  final String id; // = storeCode, e.g. STR002
  final String storeName;
  final String legalName;
  final String address;
  final String city;
  final String state;
  final String pincode;
  final String phone;
  final String email;
  final String gstNumber;
  final StoreStatus status;
  final String currency;
  final String timezone;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;

  // ---- owner / contact (all optional; older store documents have none) ----
  final String ownerName;
  final String ownerEmail;
  final String ownerPhone;
  final String ownerWhatsApp;

  /// whatsApp | sms | both | none
  final String notifyChannel;

  // ---- plan / subscription (all optional) ----
  final String? planId;
  final String? planName;

  /// trial | active | suspended as set; see [planStatusAt] for the
  /// effective status (expiring / expired follow from the expiry date).
  final String? planStatus;
  final DateTime? planStartDate;
  final DateTime? planExpiryDate;
  final double? renewalAmount;

  /// pending | paid | failed | refunded (the latest), or null.
  final String? paymentStatus;
  final DateTime? lastPaymentDate;
  final DateTime? nextPaymentDate;
  final DateTime? gracePeriodUntil;

  const Store({
    required this.id,
    required this.storeName,
    this.legalName = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.phone = '',
    this.email = '',
    this.gstNumber = '',
    this.status = StoreStatus.active,
    this.currency = 'INR',
    this.timezone = 'Asia/Kolkata',
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.ownerName = '',
    this.ownerEmail = '',
    this.ownerPhone = '',
    this.ownerWhatsApp = '',
    this.notifyChannel = 'whatsApp',
    this.planId,
    this.planName,
    this.planStatus,
    this.planStartDate,
    this.planExpiryDate,
    this.renewalAmount,
    this.paymentStatus,
    this.lastPaymentDate,
    this.nextPaymentDate,
    this.gracePeriodUntil,
  });

  String get storeCode => id;

  /// The plan status on [now]: suspended/trial/active as set, `expired`
  /// after the expiry date, `expiring` within [expiringWithinDays] of it,
  /// `none` when no plan was ever recorded (the original store).
  String planStatusAt(DateTime now, {int expiringWithinDays = 7}) {
    if (planStatus == 'suspended') return 'suspended';
    final exp = planExpiryDate;
    if (exp == null) return planStatus ?? 'none';
    final days = daysToExpiry(now)!;
    if (days < 0) return 'expired';
    if (days <= expiringWithinDays) return 'expiring';
    return planStatus ?? 'active';
  }

  /// Whole days from [now] to the plan's expiry date (negative after it).
  int? daysToExpiry(DateTime now) {
    final exp = planExpiryDate;
    if (exp == null) return null;
    final a = DateTime(now.year, now.month, now.day);
    final b = DateTime(exp.year, exp.month, exp.day);
    return b.difference(a).inDays;
  }

  /// The owner's WhatsApp number (or phone) when they want WhatsApp.
  String? get whatsAppTarget {
    if (notifyChannel != 'whatsApp' && notifyChannel != 'both') return null;
    final n = ownerWhatsApp.isNotEmpty ? ownerWhatsApp : ownerPhone;
    return n.isEmpty ? null : n;
  }

  /// The owner's phone when they want SMS.
  String? get smsTarget {
    if (notifyChannel != 'sms' && notifyChannel != 'both') return null;
    return ownerPhone.isEmpty ? null : ownerPhone;
  }
  bool get isActive => status == StoreStatus.active;

  /// Store codes: 3–20 capital letters/digits/dashes (they become document
  /// ids and storage paths).
  static final codePattern = RegExp(r'^[A-Z0-9][A-Z0-9-]{2,19}$');

  Store copyWith({
    String? storeName,
    String? legalName,
    String? address,
    String? city,
    String? state,
    String? pincode,
    String? phone,
    String? email,
    String? gstNumber,
    StoreStatus? status,
    DateTime? updatedAt,
    String? ownerName,
    String? ownerEmail,
    String? ownerPhone,
    String? ownerWhatsApp,
    String? notifyChannel,
    String? planId,
    String? planName,
    String? planStatus,
    DateTime? planStartDate,
    DateTime? planExpiryDate,
    double? renewalAmount,
    String? paymentStatus,
    DateTime? lastPaymentDate,
    DateTime? nextPaymentDate,
    DateTime? gracePeriodUntil,
  }) =>
      Store(
        id: id,
        storeName: storeName ?? this.storeName,
        legalName: legalName ?? this.legalName,
        address: address ?? this.address,
        city: city ?? this.city,
        state: state ?? this.state,
        pincode: pincode ?? this.pincode,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        gstNumber: gstNumber ?? this.gstNumber,
        status: status ?? this.status,
        currency: currency,
        timezone: timezone,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        createdBy: createdBy,
        ownerName: ownerName ?? this.ownerName,
        ownerEmail: ownerEmail ?? this.ownerEmail,
        ownerPhone: ownerPhone ?? this.ownerPhone,
        ownerWhatsApp: ownerWhatsApp ?? this.ownerWhatsApp,
        notifyChannel: notifyChannel ?? this.notifyChannel,
        planId: planId ?? this.planId,
        planName: planName ?? this.planName,
        planStatus: planStatus ?? this.planStatus,
        planStartDate: planStartDate ?? this.planStartDate,
        planExpiryDate: planExpiryDate ?? this.planExpiryDate,
        renewalAmount: renewalAmount ?? this.renewalAmount,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        lastPaymentDate: lastPaymentDate ?? this.lastPaymentDate,
        nextPaymentDate: nextPaymentDate ?? this.nextPaymentDate,
        gracePeriodUntil: gracePeriodUntil ?? this.gracePeriodUntil,
      );

  Map<String, dynamic> toMap() => {
        'storeCode': id,
        'storeName': storeName,
        'legalName': legalName,
        'address': address,
        'city': city,
        'state': state,
        'pincode': pincode,
        'phone': phone,
        'email': email,
        'gstNumber': gstNumber,
        'status': status.id,
        'currency': currency,
        'timezone': timezone,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'createdBy': createdBy,
        'ownerName': ownerName,
        'ownerEmail': ownerEmail,
        'ownerPhone': ownerPhone,
        'ownerWhatsApp': ownerWhatsApp,
        'notifyChannel': notifyChannel,
        'planId': planId,
        'planName': planName,
        'planStatus': planStatus,
        'planStartDate': planStartDate?.toIso8601String(),
        'planExpiryDate': planExpiryDate?.toIso8601String(),
        'renewalAmount': renewalAmount,
        'paymentStatus': paymentStatus,
        'lastPaymentDate': lastPaymentDate?.toIso8601String(),
        'nextPaymentDate': nextPaymentDate?.toIso8601String(),
        'gracePeriodUntil': gracePeriodUntil?.toIso8601String(),
      };

  /// The fields a person edits, as text — for change detection, the audit
  /// trail and "what changed" notifications.
  Map<String, String> describe() => {
        'storeName': storeName,
        'legalName': legalName,
        'address': address,
        'city': city,
        'state': state,
        'pincode': pincode,
        'phone': phone,
        'email': email,
        'gstNumber': gstNumber,
        'status': status.id,
        'ownerName': ownerName,
        'ownerEmail': ownerEmail,
        'ownerPhone': ownerPhone,
        'ownerWhatsApp': ownerWhatsApp,
        'notifyChannel': notifyChannel,
        'planName': planName ?? '',
        'planStatus': planStatus ?? '',
        'planExpiryDate': _day(planExpiryDate),
        'renewalAmount': renewalAmount == null ? '' : '$renewalAmount',
        'paymentStatus': paymentStatus ?? '',
        'nextPaymentDate': _day(nextPaymentDate),
        'gracePeriodUntil': _day(gracePeriodUntil),
      };

  static String _day(DateTime? d) => d == null
      ? ''
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Fields a store's own admin may edit (name and contact details). Plan,
  /// payment and status are the super admin's (firestore.rules agree).
  static const ownerEditable = {
    'storeName',
    'legalName',
    'address',
    'city',
    'state',
    'pincode',
    'phone',
    'email',
    'gstNumber',
    'ownerName',
    'ownerEmail',
    'ownerPhone',
    'ownerWhatsApp',
    'notifyChannel',
  };

  factory Store.fromMap(String id, Map<String, dynamic> m) {
    final created = DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now();
    return Store(
      id: id,
      storeName: (m['storeName'] ?? id) as String,
      legalName: (m['legalName'] ?? '') as String,
      address: (m['address'] ?? '') as String,
      city: (m['city'] ?? '') as String,
      state: (m['state'] ?? '') as String,
      pincode: (m['pincode'] ?? '') as String,
      phone: (m['phone'] ?? '') as String,
      email: (m['email'] ?? '') as String,
      gstNumber: (m['gstNumber'] ?? '') as String,
      status: StoreStatusX.fromId(m['status'] as String?),
      currency: (m['currency'] ?? 'INR') as String,
      timezone: (m['timezone'] ?? 'Asia/Kolkata') as String,
      createdAt: created,
      updatedAt: DateTime.tryParse(m['updatedAt'] ?? '') ?? created,
      createdBy: m['createdBy'] as String?,
      ownerName: (m['ownerName'] ?? '') as String,
      ownerEmail: (m['ownerEmail'] ?? '') as String,
      ownerPhone: (m['ownerPhone'] ?? '') as String,
      ownerWhatsApp: (m['ownerWhatsApp'] ?? '') as String,
      notifyChannel: (m['notifyChannel'] ?? 'whatsApp') as String,
      planId: m['planId'] as String?,
      planName: m['planName'] as String?,
      planStatus: m['planStatus'] as String?,
      planStartDate: _dt(m['planStartDate']),
      planExpiryDate: _dt(m['planExpiryDate']),
      renewalAmount: (m['renewalAmount'] as num?)?.toDouble(),
      paymentStatus: m['paymentStatus'] as String?,
      lastPaymentDate: _dt(m['lastPaymentDate']),
      nextPaymentDate: _dt(m['nextPaymentDate']),
      gracePeriodUntil: _dt(m['gracePeriodUntil']),
    );
  }

  static DateTime? _dt(Object? v) => v is String ? DateTime.tryParse(v) : null;
}

/// Thrown instead of ever running a store-owned read or write without a
/// store — falling back to "all records" would leak other stores' data.
class StoreContextException implements Exception {
  final String message;
  const StoreContextException(
      [this.message =
          'No store context available. Store-scoped operation cannot continue.']);
  @override
  String toString() => message;
}

/// Who is signed in, in what role, and which store the app is working in.
/// Built once after login from the user's protected staff record; screens
/// and the repository read it from here instead of each looking up the
/// Firebase user and a store id themselves.
class StoreContext {
  final String uid;
  final String role;

  /// The store the data belongs to. For a store user it is their assigned
  /// store; for a super admin it is the store they chose to open (null on
  /// the super-admin dashboard).
  final String? storeId;
  final Store? store;

  const StoreContext({
    required this.uid,
    required this.role,
    this.storeId,
    this.store,
  });

  bool get isSuperAdmin => role == Roles.superAdmin;
  bool get isStoreAdmin => role == Roles.storeAdmin;
  bool get isStaff => role == Roles.staff;

  /// The store id, or [StoreContextException] — for store-owned data.
  String get requireStoreId {
    final id = storeId;
    if (id == null || id.isEmpty) throw const StoreContextException();
    return id;
  }

  /// A super admin opening [store] keeps their own identity; only the
  /// administrative store context changes.
  StoreContext openStore(Store store) {
    if (!isSuperAdmin) {
      throw const StoreContextException(
          'Only a super admin can switch stores.');
    }
    return StoreContext(uid: uid, role: role, storeId: store.id, store: store);
  }
}

/// auditLogs/{id} — who did what, in which store.
class AuditEntry {
  final String storeId;
  final String userId;
  final String role;
  final String action; // e.g. BILL_FINALIZED, BILL_VOID, STORE_CREATED
  final String entityType; // BILL, PURCHASE, PRODUCT, STAFF, STORE…
  final String entityId;
  final DateTime at;
  final String? note;

  /// For a change of one field: which, and its value before / after.
  final String? field;
  final String? oldValue;
  final String? newValue;

  const AuditEntry({
    required this.storeId,
    required this.userId,
    required this.role,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.at,
    this.note,
    this.field,
    this.oldValue,
    this.newValue,
  });

  Map<String, dynamic> toMap() => {
        'storeId': storeId,
        'userId': userId,
        'role': role,
        'action': action,
        'entityType': entityType,
        'entityId': entityId,
        'timestamp': at.toIso8601String(),
        if (note != null) 'note': note,
        if (field != null) 'field': field,
        if (field != null) 'oldValue': oldValue,
        if (field != null) 'newValue': newValue,
      };

  factory AuditEntry.fromMap(Map<String, dynamic> m) => AuditEntry(
        storeId: (m['storeId'] ?? '') as String,
        userId: (m['userId'] ?? '') as String,
        role: (m['role'] ?? '') as String,
        action: (m['action'] ?? '') as String,
        entityType: (m['entityType'] ?? '') as String,
        entityId: (m['entityId'] ?? '') as String,
        at: DateTime.tryParse(m['timestamp'] ?? '') ?? DateTime.now(),
        note: m['note'] as String?,
        field: m['field'] as String?,
        oldValue: m['oldValue'] as String?,
        newValue: m['newValue'] as String?,
      );
}
