import 'store.dart';

/// A staff login — staff/{uid}, keyed by the Firebase Auth uid. Override
/// rights gate who can discount below catalogue price; [maxDiscountPct] is
/// the ceiling a staff member can apply without Owner PIN.
/// PINs are demo-only here — in production store a hash (see FirestoreRepository)
/// and authenticate with Firebase Auth.
///
/// Multi-store: [storeId] is the one store this user works in (null only
/// for a super admin). It is set by a super admin (or, for staff of their
/// own store, a store admin) — never chosen by the user themselves.
class Staff {
  final String id;
  final String name;
  final String? email;
  final String phone;
  final String
      role; // Roles.superAdmin | Roles.storeAdmin ('admin') | Roles.staff
  final String? storeId;
  final bool active;
  final bool canOverride;
  final double maxDiscountPct;
  final String pin;

  const Staff({
    required this.id,
    required this.name,
    this.email,
    this.phone = '',
    required this.role,
    this.storeId,
    this.active = true,
    this.canOverride = true,
    this.maxDiscountPct = 5,
    this.pin = '0000',
  });

  /// Store admin (owner) of their store — the existing 'admin' role.
  bool get isAdmin => role == Roles.storeAdmin;
  bool get isSuperAdmin => role == Roles.superAdmin;

  Staff copyWith({
    String? name,
    String? email,
    String? phone,
    String? role,
    String? storeId,
    bool? active,
    bool? canOverride,
    double? maxDiscountPct,
  }) =>
      Staff(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        role: role ?? this.role,
        storeId: storeId ?? this.storeId,
        active: active ?? this.active,
        canOverride: canOverride ?? this.canOverride,
        maxDiscountPct: maxDiscountPct ?? this.maxDiscountPct,
        pin: pin,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        if (email != null) 'email': email,
        'phone': phone,
        'role': role,
        'storeId': storeId,
        'active': active,
        'canOverridePrice': canOverride,
        'maxDiscountPct': maxDiscountPct,
        // 'pinHash': ... // never store a raw PIN in production
      };

  factory Staff.fromMap(String id, Map<String, dynamic> m) => Staff(
        id: id,
        name: (m['name'] ?? '') as String,
        email: m['email'] as String?,
        phone: (m['phone'] ?? '') as String,
        role: (m['role'] ?? Roles.staff) as String,
        storeId: m['storeId'] as String?,
        active: (m['active'] ?? true) as bool,
        canOverride: (m['canOverridePrice'] ?? true) as bool,
        maxDiscountPct: (m['maxDiscountPct'] ?? 5).toDouble(),
        pin: (m['pin'] ?? '0000') as String,
      );
}
