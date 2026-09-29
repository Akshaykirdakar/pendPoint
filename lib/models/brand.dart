/// A feed brand (e.g. Godrej, Kargil, Local).
class Brand {
  final String id;
  final String name; // English
  final String nameMr; // Marathi

  /// Inactive brands stay in the catalogue, stock and reports (history is
  /// never hidden) but are not offered when picking a brand/product for a
  /// NEW sale or purchase.
  final bool active;

  /// Optional logo/photo (Firebase Storage download URL).
  final String? photoUrl;

  const Brand({
    required this.id,
    required this.name,
    required this.nameMr,
    this.active = true,
    this.photoUrl,
  });

  Brand copyWith(
          {String? name,
          String? nameMr,
          bool? active,
          Object? photoUrl = _unchanged}) =>
      Brand(
        id: id,
        name: name ?? this.name,
        nameMr: nameMr ?? this.nameMr,
        active: active ?? this.active,
        photoUrl: identical(photoUrl, _unchanged)
            ? this.photoUrl
            : photoUrl as String?,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'nameMr': nameMr,
        'active': active,
        'photoUrl': photoUrl,
      };

  factory Brand.fromMap(String id, Map<String, dynamic> m) => Brand(
        id: id,
        name: (m['name'] ?? '') as String,
        nameMr: (m['nameMr'] ?? '') as String,
        // Absent on brands saved before this existed → active, no photo.
        active: (m['active'] ?? true) as bool,
        photoUrl: (m['photoUrl'] as String?)?.trim().isEmpty ?? true
            ? null
            : m['photoUrl'] as String,
      );
}

const Object _unchanged = Object();
