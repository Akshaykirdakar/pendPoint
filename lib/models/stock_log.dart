import 'enums.dart';

/// One stock movement. Purchases carry optional batch / expiry / cost / supplier
/// (product-level QR means expiry lives here, not on the product). Sales, voids
/// and returns carry [billId] for traceability. "bag-opened" is a single
/// conversion event: -1 bag, +bagWeight kg loose.
class StockLog {
  final String id;
  final String productId;
  final StockLogType type;
  final int bagsDelta;
  final double looseKgDelta;
  final String? billId;
  final String? batchNo;
  final DateTime? expiry;
  final double? cost; // per-bag purchase cost
  final String? supplier;
  final String? note;
  final DateTime at;

  const StockLog({
    required this.id,
    required this.productId,
    required this.type,
    this.bagsDelta = 0,
    this.looseKgDelta = 0,
    this.billId,
    this.batchNo,
    this.expiry,
    this.cost,
    this.supplier,
    this.note,
    required this.at,
  });

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'type': type.id,
        'bagsDelta': bagsDelta,
        'looseKgDelta': looseKgDelta,
        'billId': billId,
        'batchNo': batchNo,
        'expiry': expiry?.toIso8601String(),
        'cost': cost,
        'supplier': supplier,
        'note': note,
        'createdAt': at.toIso8601String(),
      };

  factory StockLog.fromMap(String id, Map<String, dynamic> m) => StockLog(
        id: id,
        productId: (m['productId'] ?? '') as String,
        type: StockLogTypeX.fromId(m['type'] as String?),
        bagsDelta: (m['bagsDelta'] ?? 0) as int,
        looseKgDelta: (m['looseKgDelta'] ?? 0).toDouble(),
        billId: m['billId'] as String?,
        batchNo: m['batchNo'] as String?,
        expiry: m['expiry'] != null ? DateTime.tryParse(m['expiry']) : null,
        cost: (m['cost'] as num?)?.toDouble(),
        supplier: m['supplier'] as String?,
        note: m['note'] as String?,
        at: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
      );
}
