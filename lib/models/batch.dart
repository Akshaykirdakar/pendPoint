import 'enums.dart';

/// One inventory lot — the real, depletable unit of stock (spec: "Batch must
/// be a first-class inventory entity"). A product can have many [Batch]es,
/// each with its own branch, supplier, expiry and remaining quantity; they
/// are never merged just because the product matches. [Product]-level stock
/// (see `AppState.stockOf`) is a cached rollup *derived from* the sum of a
/// product's batches — batches are the source of truth.
///
/// [sourceBatchId] is set only when this batch was created by a branch
/// transfer (see `AppState.transferStock`) — it links back to the batch it
/// was split from, preserving batch/expiry/cost identity across branches
/// without merging distinct origin batches.
class Batch {
  final String id;
  final String branchId;
  final String productId;
  final String? supplierId;
  final String batchNo;
  final DateTime? manufactureDate;
  final DateTime? expiry;
  double unitCost; // per-bag cost — latest purchase cost on a top-up
  int bagsReceived; // cumulative across top-ups of this same batch
  int bagsAvailable;
  double looseKgAvailable; // opened from this batch's bags
  int bagsSold;
  double looseKgSold;
  int bagsReturned;
  double looseKgReturned;
  int bagsAdjusted;
  double looseKgAdjusted;
  BatchStatus status;
  final String? sourceBatchId;
  final DateTime createdAt;
  DateTime updatedAt;

  Batch({
    required this.id,
    required this.branchId,
    required this.productId,
    this.supplierId,
    required this.batchNo,
    this.manufactureDate,
    this.expiry,
    this.unitCost = 0,
    this.bagsReceived = 0,
    this.bagsAvailable = 0,
    this.looseKgAvailable = 0,
    this.bagsSold = 0,
    this.looseKgSold = 0,
    this.bagsReturned = 0,
    this.looseKgReturned = 0,
    this.bagsAdjusted = 0,
    this.looseKgAdjusted = 0,
    this.status = BatchStatus.active,
    this.sourceBatchId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Total available quantity in kg (bags × bag weight + loose), for
  /// low-stock/FEFO/display math — mirrors `Stock.effectiveKg`.
  double availableKg(int bagWeightKg) =>
      bagsAvailable * bagWeightKg + looseKgAvailable;

  /// Live, never-stored truth: has this batch actually run out? (`status`
  /// tracks manual holds/write-offs; depletion is always computed.)
  bool isDepleted(int bagWeightKg) => availableKg(bagWeightKg) <= 0;

  /// Live expiry check — a batch is only "expired" once its calendar date has
  /// passed, regardless of what [status] says (see the shared
  /// expiry-status calculation used everywhere: dashboard, POS, reports).
  bool get isExpired {
    if (expiry == null) return false;
    final today = DateTime.now();
    final d = DateTime(expiry!.year, expiry!.month, expiry!.day);
    return d.isBefore(DateTime(today.year, today.month, today.day));
  }

  int? daysRemaining([DateTime? now]) {
    if (expiry == null) return null;
    final today = now ?? DateTime.now();
    final d = DateTime(expiry!.year, expiry!.month, expiry!.day);
    final t = DateTime(today.year, today.month, today.day);
    return d.difference(t).inDays;
  }

  /// Sellable right now: has stock, isn't expired, and isn't manually blocked.
  bool isSellable(int bagWeightKg) =>
      !isExpired && status != BatchStatus.blocked && !isDepleted(bagWeightKg);

  Map<String, dynamic> toMap() => {
        'branchId': branchId,
        'productId': productId,
        'supplierId': supplierId,
        'batchNo': batchNo,
        'manufactureDate': manufactureDate?.toIso8601String(),
        'expiry': expiry?.toIso8601String(),
        'unitCost': unitCost,
        'bagsReceived': bagsReceived,
        'bagsAvailable': bagsAvailable,
        'looseKgAvailable': looseKgAvailable,
        'bagsSold': bagsSold,
        'looseKgSold': looseKgSold,
        'bagsReturned': bagsReturned,
        'looseKgReturned': looseKgReturned,
        'bagsAdjusted': bagsAdjusted,
        'looseKgAdjusted': looseKgAdjusted,
        'status': status.id,
        'sourceBatchId': sourceBatchId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Batch.fromMap(String id, Map<String, dynamic> m) => Batch(
        id: id,
        branchId: (m['branchId'] ?? '') as String,
        productId: (m['productId'] ?? '') as String,
        supplierId: m['supplierId'] as String?,
        batchNo: (m['batchNo'] ?? '') as String,
        manufactureDate: m['manufactureDate'] != null
            ? DateTime.tryParse(m['manufactureDate'])
            : null,
        expiry: m['expiry'] != null ? DateTime.tryParse(m['expiry']) : null,
        unitCost: (m['unitCost'] ?? 0).toDouble(),
        bagsReceived: (m['bagsReceived'] ?? 0) as int,
        bagsAvailable: (m['bagsAvailable'] ?? 0) as int,
        looseKgAvailable: (m['looseKgAvailable'] ?? 0).toDouble(),
        bagsSold: (m['bagsSold'] ?? 0) as int,
        looseKgSold: (m['looseKgSold'] ?? 0).toDouble(),
        bagsReturned: (m['bagsReturned'] ?? 0) as int,
        looseKgReturned: (m['looseKgReturned'] ?? 0).toDouble(),
        bagsAdjusted: (m['bagsAdjusted'] ?? 0) as int,
        looseKgAdjusted: (m['looseKgAdjusted'] ?? 0).toDouble(),
        status: BatchStatusX.fromId(m['status'] as String?),
        sourceBatchId: m['sourceBatchId'] as String?,
        createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(m['updatedAt'] ?? '') ?? DateTime.now(),
      );
}
