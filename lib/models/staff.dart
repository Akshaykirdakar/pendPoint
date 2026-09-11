/// A staff login. Override rights gate who can discount below catalogue price;
/// [maxDiscountPct] is the ceiling a staff member can apply without Owner PIN.
/// PINs are demo-only here — in production store a hash (see FirestoreRepository)
/// and authenticate with Firebase Auth.
class Staff {
  final String id;
  final String name;
  final String role; // 'admin' | 'staff'
  final bool canOverride;
  final double maxDiscountPct;
  final String pin;

  const Staff({
    required this.id,
    required this.name,
    required this.role,
    this.canOverride = true,
    this.maxDiscountPct = 5,
    this.pin = '0000',
  });

  bool get isAdmin => role == 'admin';

  Map<String, dynamic> toMap() => {
        'name': name,
        'role': role,
        'canOverridePrice': canOverride,
        'maxDiscountPct': maxDiscountPct,
        // 'pinHash': ... // never store a raw PIN in production
      };

  factory Staff.fromMap(String id, Map<String, dynamic> m) => Staff(
        id: id,
        name: (m['name'] ?? '') as String,
        role: (m['role'] ?? 'staff') as String,
        canOverride: (m['canOverridePrice'] ?? true) as bool,
        maxDiscountPct: (m['maxDiscountPct'] ?? 5).toDouble(),
        pin: (m['pin'] ?? '0000') as String,
      );
}
