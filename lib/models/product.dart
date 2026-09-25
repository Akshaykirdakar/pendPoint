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
  final String? category; // optional product type/category — for Reports

  /// Branches this product may be stocked/sold at (Stock In's Product
  /// dropdown, and POS, are both gated on this — see the reviewed branch
  /// architecture). Empty means "not yet assigned to any branch".
  final List<String> branchIds;

  /// Whether Stock In must record a batch number for this product (vs. a
  /// single untracked pool). Defaults to true — most feed products are sold
  /// in dated, supplier-attributed lots.
  final bool batchTrackingEnabled;

  /// Whether Stock In must record an expiry date for this product's batches.
  final bool expiryTrackingEnabled;

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
    this.category,
    this.branchIds = const [],
    this.batchTrackingEnabled = true,
    this.expiryTrackingEnabled = true,
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
    Object? photoUrl = _unchanged,
    double? fullBagPrice,
    double? perKgPrice,
    double? costPrice,
    double? minPriceFloor,
    int? lowStockThresholdBags,
    Object? category = _unchanged,
    List<String>? branchIds,
    bool? batchTrackingEnabled,
    bool? expiryTrackingEnabled,
  }) =>
      Product(
        id: id,
        brandId: brandId ?? this.brandId,
        name: name ?? this.name,
        nameMr: nameMr ?? this.nameMr,
        bagWeightKg: bagWeightKg ?? this.bagWeightKg,
        swatch: swatch ?? this.swatch,
        photoUrl: identical(photoUrl, _unchanged)
            ? this.photoUrl
            : photoUrl as String?,
        fullBagPrice: fullBagPrice ?? this.fullBagPrice,
        perKgPrice: perKgPrice ?? this.perKgPrice,
        costPrice: costPrice ?? this.costPrice,
        minPriceFloor: minPriceFloor ?? this.minPriceFloor,
        lowStockThresholdBags:
            lowStockThresholdBags ?? this.lowStockThresholdBags,
        qr: qr,
        category: identical(category, _unchanged)
            ? this.category
            : category as String?,
        branchIds: branchIds ?? this.branchIds,
        batchTrackingEnabled: batchTrackingEnabled ?? this.batchTrackingEnabled,
        expiryTrackingEnabled:
            expiryTrackingEnabled ?? this.expiryTrackingEnabled,
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
        'category': category,
        'branchIds': branchIds,
        'batchTrackingEnabled': batchTrackingEnabled,
        'expiryTrackingEnabled': expiryTrackingEnabled,
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
        // Absent on every product saved before this field existed — treated
        // as "uncategorized", never as a reason to fail loading the product.
        category: (m['category'] as String?)?.trim().isEmpty ?? true
            ? null
            : (m['category'] as String).trim(),
        // Absent on every product saved before branches existed — treated as
        // "not yet assigned to any branch" (migration backfills this).
        branchIds: ((m['branchIds'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        batchTrackingEnabled: (m['batchTrackingEnabled'] ?? true) as bool,
        expiryTrackingEnabled: (m['expiryTrackingEnabled'] ?? true) as bool,
      );
}

const Object _unchanged = Object();
