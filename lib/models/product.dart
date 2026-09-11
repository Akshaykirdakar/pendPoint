/// A bag type / product under a brand.
///
/// Note (from the reviewed spec): [perKgPrice] is an INDEPENDENT stored field,
/// not derived from [fullBagPrice] / [bagWeightKg] — loose retail is priced
/// higher than the bulk bag rate. [minPriceFloor] guards against underselling
/// on a price override. The QR is product-level (not per physical unit).
class Product {
  final String id;
  final String brandId;
  final String name; // English
  final String nameMr; // Marathi
  final int bagWeightKg; // e.g. 50
  final String
      swatch; // placeholder photo tint key (emoji) until a real photoUrl
  final String? photoUrl; // Firebase Storage URL (cached on device for offline)
  final double fullBagPrice;
  final double perKgPrice;
  final double costPrice; // optional — enables margin reporting
  final double minPriceFloor; // optional — override guard
  final int lowStockThresholdBags; // evaluated against total kg
  final String qr; // encoded product code, e.g. "PEND-P1"

  const Product({
    required this.id,
    required this.brandId,
    required this.name,
    required this.nameMr,
    required this.bagWeightKg,
    this.swatch = '🟩',
    this.photoUrl,
    required this.fullBagPrice,
    required this.perKgPrice,
    this.costPrice = 0,
    this.minPriceFloor = 0,
    this.lowStockThresholdBags = 5,
    required this.qr,
  });

  /// Per-kg floor derived from the bag floor for by-weight overrides.
  double get perKgFloor =>
      bagWeightKg == 0 ? minPriceFloor : (minPriceFloor / bagWeightKg);

  double catalogRate(bool isBag) => isBag ? fullBagPrice : perKgPrice;
  double floorRate(bool isBag) => isBag ? minPriceFloor : perKgFloor;

  Product copyWith({
    String? brandId,
    String? name,
    String? nameMr,
    int? bagWeightKg,
    String? swatch,
    String? photoUrl,
    double? fullBagPrice,
    double? perKgPrice,
    double? costPrice,
    double? minPriceFloor,
    int? lowStockThresholdBags,
  }) =>
      Product(
        id: id,
        brandId: brandId ?? this.brandId,
        name: name ?? this.name,
        nameMr: nameMr ?? this.nameMr,
        bagWeightKg: bagWeightKg ?? this.bagWeightKg,
        swatch: swatch ?? this.swatch,
        photoUrl: photoUrl ?? this.photoUrl,
        fullBagPrice: fullBagPrice ?? this.fullBagPrice,
        perKgPrice: perKgPrice ?? this.perKgPrice,
        costPrice: costPrice ?? this.costPrice,
        minPriceFloor: minPriceFloor ?? this.minPriceFloor,
        lowStockThresholdBags:
            lowStockThresholdBags ?? this.lowStockThresholdBags,
        qr: qr,
      );

  Map<String, dynamic> toMap() => {
        'brandId': brandId,
        'name': name,
        'nameMr': nameMr,
        'bagWeightKg': bagWeightKg,
        'swatch': swatch,
        'photoUrl': photoUrl,
        'fullBagPrice': fullBagPrice,
        'perKgPrice': perKgPrice,
        'costPrice': costPrice,
        'minPriceFloor': minPriceFloor,
        'lowStockThreshold': lowStockThresholdBags,
        'qrCode': qr,
      };

  factory Product.fromMap(String id, Map<String, dynamic> m) => Product(
        id: id,
        brandId: (m['brandId'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        nameMr: (m['nameMr'] ?? '') as String,
        bagWeightKg: (m['bagWeightKg'] ?? 50) as int,
        swatch: (m['swatch'] ?? '🟩') as String,
        photoUrl: m['photoUrl'] as String?,
        fullBagPrice: (m['fullBagPrice'] ?? 0).toDouble(),
        perKgPrice: (m['perKgPrice'] ?? 0).toDouble(),
        costPrice: (m['costPrice'] ?? 0).toDouble(),
        minPriceFloor: (m['minPriceFloor'] ?? 0).toDouble(),
        lowStockThresholdBags: (m['lowStockThreshold'] ?? 5) as int,
        qr: (m['qrCode'] ?? 'PEND-$id') as String,
      );
}
