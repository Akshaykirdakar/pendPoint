/// A shop location/branch. Product catalogue is shared (see [Product.branchIds]
/// for the per-branch assignment), but stock/batches/bills are branch-scoped.
class Branch {
  final String id;
  final String name;
  final String nameMr;
  final String address;
  final bool active;

  const Branch({
    required this.id,
    required this.name,
    required this.nameMr,
    this.address = '',
    this.active = true,
  });

  Branch copyWith({String? name, String? nameMr, String? address, bool? active}) =>
      Branch(
        id: id,
        name: name ?? this.name,
        nameMr: nameMr ?? this.nameMr,
        address: address ?? this.address,
        active: active ?? this.active,
      );

  Map<String, dynamic> toMap() =>
      {'name': name, 'nameMr': nameMr, 'address': address, 'active': active};

  factory Branch.fromMap(String id, Map<String, dynamic> m) => Branch(
        id: id,
        name: (m['name'] ?? '') as String,
        nameMr: (m['nameMr'] ?? '') as String,
        address: (m['address'] ?? '') as String,
        active: (m['active'] ?? true) as bool,
      );
}
