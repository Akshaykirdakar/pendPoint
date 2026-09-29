import 'enums.dart';

/// One line on a purchase bill: so many bags of one product, bought at
/// [rate] per bag, received into batch [batchId]. [rate] is the actual
/// PURCHASE rate — the selling price stays on the product
/// ([sellingRateAtPurchase] is only a snapshot for reference/margin).
class PurchaseItem {
  final String productId;
  final String brandId;
  final int bags;
  final double rate; // purchase rate per bag
  final double amount; // bags × rate
  final String batchId;
  final String batchNo;
  final DateTime? expiry;
  final DateTime? manufactureDate;
  final double sellingRateAtPurchase;

  const PurchaseItem({
    required this.productId,
    required this.brandId,
    required this.bags,
    required this.rate,
    required this.amount,
    required this.batchId,
    required this.batchNo,
    this.expiry,
    this.manufactureDate,
    this.sellingRateAtPurchase = 0,
  });

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'brandId': brandId,
        'bags': bags,
        'purchaseRate': rate,
        'amount': amount,
        'batchId': batchId,
        'batchNo': batchNo,
        'expiry': expiry?.toIso8601String(),
        'manufactureDate': manufactureDate?.toIso8601String(),
        'sellingRateAtPurchase': sellingRateAtPurchase,
      };

  factory PurchaseItem.fromMap(Map<String, dynamic> m) => PurchaseItem(
        productId: (m['productId'] ?? '') as String,
        brandId: (m['brandId'] ?? '') as String,
        bags: (m['bags'] ?? 0) as int,
        rate: (m['purchaseRate'] ?? 0).toDouble(),
        amount: (m['amount'] ?? 0).toDouble(),
        batchId: (m['batchId'] ?? '') as String,
        batchNo: (m['batchNo'] ?? '') as String,
        expiry: m['expiry'] != null ? DateTime.tryParse(m['expiry']) : null,
        manufactureDate: m['manufactureDate'] != null
            ? DateTime.tryParse(m['manufactureDate'])
            : null,
        sellingRateAtPurchase: (m['sellingRateAtPurchase'] ?? 0).toDouble(),
      );
}

/// A purchase bill from a supplier (purchase party) — the inward
/// counterpart of [Bill]. Stored as `purchases/{id}` with its lines in the
/// `purchaseItems` subcollection, exactly like bills/billItems. Like bills,
/// purchases are never deleted: void or edit (void + new revision).
class Purchase {
  final String id;
  final int purchaseNumber;
  final String supplierId;
  final String supplierName;
  final String supplierBillNo;
  final DateTime purchaseDate; // date on the supplier's bill
  final List<PurchaseItem> items;
  final double subtotal;
  final double otherCharges; // transport/loading/etc. — 0 when none
  final double total;
  final BillStatus status;
  final String? branchId;
  final String? staffId;
  final DateTime createdAt;
  final int revision;
  final String? originalPurchaseId;
  final String? replacedByPurchaseId;

  /// Optional photo of the supplier's paper bill, for reference only. The
  /// image lives in Firebase Storage (`purchase-bills/{purchaseId}/…`);
  /// the purchase stores only its download URL and storage path. The path
  /// is for the app (delete/replace) and is never shown to the user.
  final String? billPhotoUrl;
  final String? billPhotoPath;

  const Purchase({
    required this.id,
    required this.purchaseNumber,
    required this.supplierId,
    required this.supplierName,
    this.supplierBillNo = '',
    required this.purchaseDate,
    required this.items,
    required this.subtotal,
    this.otherCharges = 0,
    required this.total,
    this.status = BillStatus.finalized,
    this.branchId,
    this.staffId,
    required this.createdAt,
    this.revision = 0,
    this.originalPurchaseId,
    this.replacedByPurchaseId,
    this.billPhotoUrl,
    this.billPhotoPath,
  });

  bool get hasBillPhoto => (billPhotoPath ?? '').isNotEmpty;

  int get totalBags => items.fold(0, (s, i) => s + i.bags);

  Purchase copyWith({BillStatus? status, String? replacedByPurchaseId}) =>
      Purchase(
        id: id,
        purchaseNumber: purchaseNumber,
        supplierId: supplierId,
        supplierName: supplierName,
        supplierBillNo: supplierBillNo,
        purchaseDate: purchaseDate,
        items: items,
        subtotal: subtotal,
        otherCharges: otherCharges,
        total: total,
        status: status ?? this.status,
        branchId: branchId,
        staffId: staffId,
        createdAt: createdAt,
        revision: revision,
        originalPurchaseId: originalPurchaseId,
        replacedByPurchaseId: replacedByPurchaseId ?? this.replacedByPurchaseId,
        billPhotoUrl: billPhotoUrl,
        billPhotoPath: billPhotoPath,
      );

  Map<String, dynamic> toMap() => {
        'purchaseNumber': purchaseNumber,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'supplierBillNo': supplierBillNo,
        'purchaseDate': purchaseDate.toIso8601String(),
        'subtotal': subtotal,
        'otherCharges': otherCharges,
        'totalAmount': total,
        'status': status.id,
        'branchId': branchId,
        'createdBy': staffId,
        'createdAt': createdAt.toIso8601String(),
        'revision': revision,
        'originalPurchaseId': originalPurchaseId,
        'replacedByPurchaseId': replacedByPurchaseId,
        'billPhotoUrl': billPhotoUrl,
        'billPhotoPath': billPhotoPath,
        // purchaseItems are a subcollection — see FirestoreRepository.
      };

  factory Purchase.fromMap(
          String id, Map<String, dynamic> m, List<PurchaseItem> items) =>
      Purchase(
        id: id,
        purchaseNumber: (m['purchaseNumber'] ?? 0) as int,
        supplierId: (m['supplierId'] ?? '') as String,
        supplierName: (m['supplierName'] ?? '') as String,
        supplierBillNo: (m['supplierBillNo'] ?? '') as String,
        purchaseDate: DateTime.tryParse(m['purchaseDate'] ?? '') ??
            DateTime.tryParse(m['createdAt'] ?? '') ??
            DateTime.now(),
        items: items,
        subtotal: (m['subtotal'] ?? 0).toDouble(),
        otherCharges: (m['otherCharges'] ?? 0).toDouble(),
        total: (m['totalAmount'] ?? 0).toDouble(),
        status: BillStatusX.fromId(m['status'] as String?),
        branchId: m['branchId'] as String?,
        staffId: m['createdBy'] as String?,
        createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
        revision: (m['revision'] ?? 0) as int,
        originalPurchaseId: m['originalPurchaseId'] as String?,
        replacedByPurchaseId: m['replacedByPurchaseId'] as String?,
        // Absent on purchases saved before bill photos existed.
        billPhotoUrl: m['billPhotoUrl'] as String?,
        billPhotoPath: m['billPhotoPath'] as String?,
      );
}
