import 'bill.dart';
import 'enums.dart';

/// One product line of a draft bill — exactly what the bill-entry row
/// holds: unit, quantity, the catalogue rate when the line was added, and
/// the rate charged on THIS bill (a changed rate never touches the product).
class DraftLine {
  final String productId;
  final SaleType saleType;
  final double qty;
  final double catalogRate;
  final double rate;

  const DraftLine({
    required this.productId,
    required this.saleType,
    required this.qty,
    required this.catalogRate,
    required this.rate,
  });

  double get lineTotal => rate * qty;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'saleType': saleType.id,
        'qty': qty,
        'catalogRate': catalogRate,
        'rate': rate,
      };

  factory DraftLine.fromMap(Map<String, dynamic> m) => DraftLine(
        productId: (m['productId'] ?? '') as String,
        saleType: SaleTypeX.fromId(m['saleType'] as String?),
        qty: (m['qty'] ?? 0).toDouble(),
        catalogRate: (m['catalogRate'] ?? m['rate'] ?? 0).toDouble(),
        rate: (m['rate'] ?? 0).toDouble(),
      );
}

/// A bill the shopkeeper started but has not finished (📝 ड्राफ्ट).
///
/// A draft is saved work only: it holds no stock, no payment and no khata
/// entry, and has no bill number — [number] is its own "D…" sequence. Only
/// finalizing it (the normal sale) creates a real [Bill]; that same commit
/// removes the draft. [version] goes up by one on every save so a phone
/// holding an older copy can't silently overwrite newer changes.
class DraftBill {
  final String id;
  final int number;
  final String? customerId;
  final String customerName; // shown on the list even before parties load
  final List<DraftLine> lines;
  final List<Payment> payments; // planned split only — nothing recorded

  /// Previous due the customer will pay with this bill (planned only).
  final double dueCollect;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;
  final int version;

  const DraftBill({
    required this.id,
    required this.number,
    this.customerId,
    this.customerName = '',
    required this.lines,
    this.payments = const [],
    this.dueCollect = 0,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.updatedBy,
    this.version = 1,
  });

  /// "D1024" — never shown as a bill number.
  String get label => 'D$number';

  double get total => lines.fold(0.0, (s, l) => s + l.lineTotal);

  Map<String, dynamic> toMap() => {
        'status': 'draft',
        'number': number,
        'customerId': customerId,
        'customerName': customerName,
        'lines': lines.map((l) => l.toMap()).toList(),
        'payments': payments.map((p) => p.toMap()).toList(),
        'dueCollect': dueCollect,
        'totalAmount': total,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'createdBy': createdBy,
        'updatedBy': updatedBy,
        'version': version,
      };

  factory DraftBill.fromMap(String id, Map<String, dynamic> m) {
    final created = DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now();
    return DraftBill(
      id: id,
      number: (m['number'] ?? 0) as int,
      customerId: m['customerId'] as String?,
      customerName: (m['customerName'] ?? '') as String,
      lines: ((m['lines'] ?? []) as List)
          .map((l) => DraftLine.fromMap(Map<String, dynamic>.from(l)))
          .toList(),
      payments: ((m['payments'] ?? []) as List)
          .map((p) => Payment.fromMap(Map<String, dynamic>.from(p)))
          .toList(),
      dueCollect: (m['dueCollect'] ?? 0).toDouble(),
      createdAt: created,
      updatedAt: DateTime.tryParse(m['updatedAt'] ?? '') ?? created,
      createdBy: m['createdBy'] as String?,
      updatedBy: m['updatedBy'] as String?,
      version: (m['version'] ?? 1) as int,
    );
  }
}

/// A draft save was refused because the stored copy is not the one this
/// phone started from — nothing was overwritten.
class DraftConflictException implements Exception {
  /// True when the draft no longer exists (finalized or deleted elsewhere);
  /// false when another phone saved a newer version.
  final bool missing;
  const DraftConflictException({required this.missing});
  @override
  String toString() =>
      missing ? 'draft no longer exists' : 'draft changed on another device';
}
