/// A feed brand (e.g. Godrej, Kargil, Local).
class Brand {
  final String id;
  final String name; // English
  final String nameMr; // Marathi

  const Brand({required this.id, required this.name, required this.nameMr});

  Brand copyWith({String? name, String? nameMr}) => Brand(
        id: id,
        name: name ?? this.name,
        nameMr: nameMr ?? this.nameMr,
      );

  Map<String, dynamic> toMap() => {'name': name, 'nameMr': nameMr};

  factory Brand.fromMap(String id, Map<String, dynamic> m) => Brand(
        id: id,
        name: (m['name'] ?? '') as String,
        nameMr: (m['nameMr'] ?? '') as String,
      );
}
