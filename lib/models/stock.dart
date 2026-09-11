/// Live stock for one product: two units — full bags and loose kg (from opened
/// bags). Kept as its own record (1:1 with product) so real-time listeners are
/// lightweight and don't reload product/photo data.
class Stock {
  final String productId;
  int bags;
  double looseKg;

  Stock({required this.productId, this.bags = 0, this.looseKg = 0});

  /// Total effective stock in kg = bags × bagWeight + loose. Low-stock and
  /// oversell checks use this so loose kg is never ignored.
  double effectiveKg(int bagWeightKg) => bags * bagWeightKg + looseKg;

  Stock clone() => Stock(productId: productId, bags: bags, looseKg: looseKg);

  Map<String, dynamic> toMap() =>
      {'bagsRemaining': bags, 'looseKgRemaining': looseKg};

  factory Stock.fromMap(String productId, Map<String, dynamic> m) => Stock(
        productId: productId,
        bags: (m['bagsRemaining'] ?? 0) as int,
        looseKg: (m['looseKgRemaining'] ?? 0).toDouble(),
      );
}
