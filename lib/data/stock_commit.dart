import '../models/batch.dart';
import '../models/bill.dart';
import '../models/customer.dart';
import '../models/enums.dart';
import '../models/purchase.dart';
import '../models/stock_log.dart';

/// A change to one inventory batch, expressed as DELTAS (never absolute
/// values), so the repository can apply it against the batch's *current*
/// server-side quantities inside a transaction instead of overwriting them
/// with a possibly-stale local copy.
class BatchDelta {
  final String batchId;
  final String productId;

  /// Set when the batch does not exist yet (first purchase of a new batch
  /// no.). Its quantity fields are ignored — the deltas below are applied to
  /// zero.
  final Batch? create;

  int bagsAvailable = 0;
  double looseKgAvailable = 0;
  int bagsReceived = 0;
  int bagsSold = 0;
  double looseKgSold = 0;
  int bagsReturned = 0;
  double looseKgReturned = 0;

  /// Latest purchase cost per bag (a purchase top-up overwrites it).
  double? unitCost;

  BatchDelta(this.batchId, this.productId, {this.create});

  bool get isEmpty =>
      create == null &&
      unitCost == null &&
      bagsAvailable == 0 &&
      looseKgAvailable.abs() < 1e-9 &&
      bagsReceived == 0 &&
      bagsSold == 0 &&
      looseKgSold.abs() < 1e-9 &&
      bagsReturned == 0 &&
      looseKgReturned.abs() < 1e-9;

  /// Applies this delta to [b] in place.
  void applyTo(Batch b, DateTime at) {
    b.bagsAvailable += bagsAvailable;
    b.looseKgAvailable = _round(b.looseKgAvailable + looseKgAvailable);
    b.bagsReceived += bagsReceived;
    b.bagsSold += bagsSold;
    b.looseKgSold = _round(b.looseKgSold + looseKgSold);
    b.bagsReturned += bagsReturned;
    b.looseKgReturned = _round(b.looseKgReturned + looseKgReturned);
    if (unitCost != null) b.unitCost = unitCost!;
    b.updatedAt = at;
  }

  static double _round(double v) => (v * 1000).roundToDouble() / 1000;
}

/// Aggregate-only stock change for a product that has no batches at all
/// (legacy data from before batch tracking).
class LegacyStockDelta {
  int bags;
  double looseKg;
  LegacyStockDelta({this.bags = 0, this.looseKg = 0});
}

/// A status change on an existing bill/purchase. [expected] is re-checked
/// inside the transaction so two devices cannot void/edit the same
/// document twice.
class StatusPatch {
  final String id;
  final BillStatus expected;
  final BillStatus status;
  final String? replacedById;
  const StatusPatch(this.id,
      {this.expected = BillStatus.finalized,
      required this.status,
      this.replacedById});
}

/// A khata ledger entry plus the change it makes to the customer's
/// outstanding balance (applied to the current server value, floored at 0).
class LedgerChange {
  final String customerId;
  final LedgerEntry entry;
  final double outstandingDelta;
  const LedgerChange(this.customerId, this.entry, this.outstandingDelta);
}

/// Everything one business operation (sale, void, bill edit, purchase,
/// purchase void/edit, stock-in, return) changes — committed all-or-nothing
/// by [Repository.commitStock]. A batch may never be left with negative
/// available stock; if another device sold the same bags first, the whole
/// commit is rejected with a [StockCommitException] and nothing is written.
class StockCommit {
  final DateTime at;
  final Map<String, BatchDelta> batches = {}; // batchId -> delta
  final Map<String, LegacyStockDelta> legacyStock = {}; // productId -> delta
  final List<StockLog> logs = [];
  final List<Bill> newBills = [];
  final List<StatusPatch> billPatches = [];
  final List<Purchase> newPurchases = [];
  final List<StatusPatch> purchasePatches = [];
  final List<LedgerChange> ledger = [];

  StockCommit(this.at);

  BatchDelta batch(String batchId, String productId) =>
      batches.putIfAbsent(batchId, () => BatchDelta(batchId, productId));

  LegacyStockDelta legacy(String productId) =>
      legacyStock.putIfAbsent(productId, () => LegacyStockDelta());

  /// Net change to each product's cross-batch stock rollup.
  Map<String, (int, double)> get rollupDeltas {
    final out = <String, (int, double)>{};
    void add(String pid, int bags, double kg) {
      final cur = out[pid] ?? (0, 0.0);
      out[pid] = (cur.$1 + bags, cur.$2 + kg);
    }

    for (final d in batches.values) {
      add(d.productId, d.bagsAvailable, d.looseKgAvailable);
    }
    legacyStock.forEach((pid, d) => add(pid, d.bags, d.looseKg));
    return out;
  }
}

/// A commit was rejected — typically stock changed on another device, or a
/// bill was already voided/edited elsewhere. Nothing was written.
class StockCommitException implements Exception {
  final String message;
  const StockCommitException(this.message);
  @override
  String toString() => message;
}
