import 'enums.dart';

/// A single line on a bill.
///
/// KEY (from the reviewed spec): [catalogRate] stores the catalogue price at the
/// moment of sale, so the override/discount report can show *by how much* a
/// price was edited — a boolean alone can't. [rate] is what was actually charged.
class BillItem {
  final String productId;
  final SaleType saleType;
  final double qty; // bags (int-valued) or kg
  final double catalogRate; // catalogue price at time of sale
  final double rate; // price actually charged
  final double lineTotal;

  /// Which batch this line actually depleted (null on bills created before
  /// batch tracking existed, or for a not-batch-tracked product) — see the
  /// reviewed branch/batch/expiry architecture. A product sold across
  /// multiple batches in one sale produces one [BillItem] per batch used.
  final String? batchId;
  final String? batchNo;
  final String? supplierId;
  final DateTime? expiry;

  const BillItem({
    required this.productId,
    required this.saleType,
    required this.qty,
    required this.catalogRate,
    required this.rate,
    required this.lineTotal,
    this.batchId,
    this.batchNo,
    this.supplierId,
    this.expiry,
  });

  bool get isPriceOverridden => rate != catalogRate;
  double get discountAmount => (catalogRate - rate) * qty;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'saleType': saleType.id,
        'quantityOrWeight': qty,
        'catalogRateAtSale': catalogRate,
        'rate': rate,
        'lineTotal': lineTotal,
        'isPriceOverridden': isPriceOverridden,
        'batchId': batchId,
        'batchNo': batchNo,
        'supplierId': supplierId,
        'expiry': expiry?.toIso8601String(),
      };

  factory BillItem.fromMap(Map<String, dynamic> m) => BillItem(
        productId: (m['productId'] ?? '') as String,
        saleType: SaleTypeX.fromId(m['saleType'] as String?),
        qty: (m['quantityOrWeight'] ?? 0).toDouble(),
        catalogRate: (m['catalogRateAtSale'] ?? m['rate'] ?? 0).toDouble(),
        rate: (m['rate'] ?? 0).toDouble(),
        lineTotal: (m['lineTotal'] ?? 0).toDouble(),
        batchId: m['batchId'] as String?,
        batchNo: m['batchNo'] as String?,
        supplierId: m['supplierId'] as String?,
        expiry: m['expiry'] != null ? DateTime.tryParse(m['expiry']) : null,
      );
}

/// One payment portion (supports split payment, e.g. part cash + part credit).
class Payment {
  final PayMode mode;
  final double amount;
  const Payment(this.mode, this.amount);

  Map<String, dynamic> toMap() => {'mode': mode.id, 'amount': amount};
  factory Payment.fromMap(Map<String, dynamic> m) => Payment(
      PayModeX.fromId(m['mode'] as String?), (m['amount'] ?? 0).toDouble());
}

class Bill {
  final String id;
  final int billNumber;
  final String? customerId;
  final String customerName;
  final List<BillItem> items;
  final double subtotal;
  final double discountTotal;
  final double total;
  final List<Payment> payments;
  final BillStatus status;
  final DateTime at;
  final String? staffId;
  final String? branchId; // null on bills created before branches existed

  const Bill({
    required this.id,
    required this.billNumber,
    this.customerId,
    this.customerName = '',
    required this.items,
    required this.subtotal,
    required this.discountTotal,
    required this.total,
    required this.payments,
    this.status = BillStatus.finalized,
    required this.at,
    this.staffId,
    this.branchId,
  });

  double get creditAmount => payments
      .where((p) => p.mode == PayMode.credit)
      .fold(0.0, (s, p) => s + p.amount);

  Bill copyWith({BillStatus? status}) => Bill(
        id: id,
        billNumber: billNumber,
        customerId: customerId,
        customerName: customerName,
        items: items,
        subtotal: subtotal,
        discountTotal: discountTotal,
        total: total,
        payments: payments,
        status: status ?? this.status,
        at: at,
        staffId: staffId,
        branchId: branchId,
      );

  Map<String, dynamic> toMap() => {
        'billNumber': billNumber,
        'customerId': customerId,
        'customerName': customerName,
        'subtotal': subtotal,
        'discountTotal': discountTotal,
        'totalAmount': total,
        'payments': payments.map((p) => p.toMap()).toList(),
        'status': status.id,
        'createdAt': at.toIso8601String(),
        'createdBy': staffId,
        'branchId': branchId,
        // billItems are a subcollection in Firestore — see FirestoreRepository.
      };

  factory Bill.fromMap(
          String id, Map<String, dynamic> m, List<BillItem> items) =>
      Bill(
        id: id,
        billNumber: (m['billNumber'] ?? 0) as int,
        customerId: m['customerId'] as String?,
        customerName: (m['customerName'] ?? '') as String,
        items: items,
        subtotal: (m['subtotal'] ?? 0).toDouble(),
        discountTotal: (m['discountTotal'] ?? 0).toDouble(),
        total: (m['totalAmount'] ?? 0).toDouble(),
        payments: ((m['payments'] ?? []) as List)
            .map((p) => Payment.fromMap(Map<String, dynamic>.from(p)))
            .toList(),
        status: BillStatusX.fromId(m['status'] as String?),
        at: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
        staffId: m['createdBy'] as String?,
        branchId: m['branchId'] as String?,
      );
}
