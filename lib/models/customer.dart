/// Credit (khata / उधार) ledger entry: a credit sale (+) or a repayment (−).
class LedgerEntry {
  final String type; // 'credit-sale' | 'repayment'
  final double amount;
  final String? billId;
  final String? note;
  final DateTime at;

  const LedgerEntry({
    required this.type,
    required this.amount,
    this.billId,
    this.note,
    required this.at,
  });

  bool get isRepayment => type == 'repayment';

  Map<String, dynamic> toMap() => {
        'type': type,
        'amount': amount,
        'billId': billId,
        'note': note,
        'createdAt': at.toIso8601String(),
      };

  factory LedgerEntry.fromMap(Map<String, dynamic> m) => LedgerEntry(
        type: (m['type'] ?? 'credit-sale') as String,
        amount: (m['amount'] ?? 0).toDouble(),
        billId: m['billId'] as String?,
        note: m['note'] as String?,
        at: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
      );
}

/// A khata customer. [outstanding] is maintained transactionally alongside the
/// ledger so the balance is never recomputed on the client.
class Customer {
  final String id;
  String name;
  String mobile;
  double outstanding;
  final List<LedgerEntry> ledger;

  Customer({
    required this.id,
    required this.name,
    this.mobile = '',
    this.outstanding = 0,
    List<LedgerEntry>? ledger,
  }) : ledger = ledger ?? [];

  Map<String, dynamic> toMap() => {
        'name': name,
        'mobile': mobile,
        'outstandingBalance': outstanding,
      };

  factory Customer.fromMap(
          String id, Map<String, dynamic> m, List<LedgerEntry> ledger) =>
      Customer(
        id: id,
        name: (m['name'] ?? '') as String,
        mobile: (m['mobile'] ?? '') as String,
        outstanding: (m['outstandingBalance'] ?? 0).toDouble(),
        ledger: ledger,
      );
}
