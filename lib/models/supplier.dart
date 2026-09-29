/// A purchase/stock-in supplier — the *purchase* side of the Party Master
/// (see `models/party.dart`) — a proper master entity (never a free-text
/// field on a purchase row). Batches reference a supplier by [id]; a supplier
/// referenced by any batch/purchase can only be deactivated, never
/// hard-deleted (see [AppState.deleteSupplier]).
class Supplier {
  final String id;
  final String name;
  final String mobile;
  final String altMobile;
  final String address;
  final String gstin;
  final String email;
  final double openingBalance;
  final bool active;
  final String notes;
  final DateTime createdAt;

  /// Party code / number (shared with the matching [Customer] when the party
  /// is both a buyer and a seller). Empty on suppliers created earlier.
  final String code;

  const Supplier({
    required this.id,
    required this.name,
    this.code = '',
    this.mobile = '',
    this.altMobile = '',
    this.address = '',
    this.gstin = '',
    this.email = '',
    this.openingBalance = 0,
    this.active = true,
    this.notes = '',
    required this.createdAt,
  });

  Supplier copyWith({
    String? name,
    String? code,
    String? mobile,
    String? altMobile,
    String? address,
    String? gstin,
    String? email,
    double? openingBalance,
    bool? active,
    String? notes,
  }) =>
      Supplier(
        id: id,
        name: name ?? this.name,
        code: code ?? this.code,
        mobile: mobile ?? this.mobile,
        altMobile: altMobile ?? this.altMobile,
        address: address ?? this.address,
        gstin: gstin ?? this.gstin,
        email: email ?? this.email,
        openingBalance: openingBalance ?? this.openingBalance,
        active: active ?? this.active,
        notes: notes ?? this.notes,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'mobile': mobile,
        'altMobile': altMobile,
        'address': address,
        'gstin': gstin,
        'email': email,
        'openingBalance': openingBalance,
        'active': active,
        'notes': notes,
        'code': code,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Supplier.fromMap(String id, Map<String, dynamic> m) => Supplier(
        id: id,
        name: (m['name'] ?? '') as String,
        mobile: (m['mobile'] ?? '') as String,
        altMobile: (m['altMobile'] ?? '') as String,
        address: (m['address'] ?? '') as String,
        gstin: (m['gstin'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        openingBalance: (m['openingBalance'] ?? 0).toDouble(),
        active: (m['active'] ?? true) as bool,
        notes: (m['notes'] ?? '') as String,
        code: (m['code'] ?? '') as String,
        createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
      );
}
