import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../data/repository.dart';
import '../models/app_settings.dart';
import '../models/batch.dart';
import '../models/bill.dart';
import '../models/branch.dart';
import '../models/brand.dart';
import '../models/customer.dart';
import '../models/enums.dart';
import '../models/product.dart';
import '../models/staff.dart';
import '../models/stock.dart';
import '../models/stock_log.dart';
import '../models/supplier.dart';
import 'cart_line.dart';

/// Result of trying to finalize a sale.
class SaleResult {
  final bool ok;
  final String? error;
  final Bill? bill;
  const SaleResult.success(this.bill)
      : ok = true,
        error = null;
  const SaleResult.failure(this.error)
      : ok = false,
        bill = null;
}

/// Central app state + business logic. Holds the working copy in memory for a
/// snappy counter UI and writes through [repo] for persistence.
class AppState extends ChangeNotifier {
  final Repository repo;
  AppState(this.repo);

  // ---- data ----
  List<Brand> brands = [];
  List<Branch> branches = [];
  List<Supplier> suppliers = [];
  List<Product> products = [];
  Map<String, Stock> stock = {};
  List<Batch> batches = [];
  List<StockLog> logs = [];
  List<Bill> bills = [];
  List<Customer> customers = [];
  List<Staff> staff = [];
  AppSettings settings = AppSettings();
  bool loading = true;
  Object? bootstrapError;

  /// The branch Stock In/POS/Reports operate against by default. Set once
  /// branches are known (bootstrap, or after creating the first branch);
  /// screens that need a specific branch (Stock In, Reports) can still pick a
  /// different one without changing this.
  String? activeBranchId;

  void setActiveBranch(String id) {
    activeBranchId = id;
    notifyListeners();
  }

  // History (bills, customers+ledgers, stock logs) loads separately, in the
  // background, after the core catalogue/stock — see [bootstrap]. Reports/
  // Khata/Returns/History screens watch these to show an inline loading
  // note instead of a false "no data" empty state; Home/Sell/Stock don't
  // depend on history at all and never wait on it.
  bool historyLoading = false;
  Object? historyError;

  // Bumped on every bootstrap() call; a history load only applies its result
  // if it's still the most recent one, so an overlapping/second bootstrap
  // (e.g. a Retry tap, or "Reset sample data") can't have its history
  // clobbered by a slower, now-stale load from the previous cycle.
  int _bootstrapSeq = 0;

  // ---- current cart ----
  final List<CartLine> cart = [];
  String? cartCustomerId;
  final List<Payment> payments = [];

  /// Loads the catalogue/stock/settings/staff first and shows the counter
  /// screen as soon as that's ready, then loads history (bills, customers,
  /// stock logs) in the background without blocking the UI.
  Future<void> bootstrap() async {
    bootstrapError = null;
    loading = true;
    historyError = null;
    final seq = ++_bootstrapSeq;
    notifyListeners();
    try {
      // A hung Firestore call (dropped connection, silently-blocked request,
      // stuck IndexedDB/persistence layer on web) should surface as an
      // error the UI can show, not spin the splash screen forever.
      final core = await repo.loadCore().timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw StateError(
                'Timed out loading shop data — check your connection and Firestore rules.'),
          );
      brands = core.brands;
      // Retain one backing branch for legacy batch data; branch management is
      // deliberately not exposed in the single-shop app.
      branches = core.branches.isEmpty ? [] : [core.branches.first];
      suppliers = core.suppliers;
      products = core.products;
      stock = core.stock;
      staff = core.staff;
      settings = core.settings;
      await _migrateBranchesAndProducts();
      activeBranchId ??= branches.where((b) => b.active).firstOrNull?.id ??
          branches.firstOrNull?.id;
    } catch (error) {
      bootstrapError = error;
    } finally {
      loading = false;
      notifyListeners();
    }
    if (bootstrapError != null) return; // core failed — don't load history
    unawaited(_loadHistory(seq));
  }

  Future<void> _loadHistory(int seq) async {
    historyLoading = true;
    historyError = null;
    notifyListeners();
    try {
      final history = await repo.loadHistory().timeout(
            const Duration(seconds: 20),
            onTimeout: () =>
                throw StateError('Timed out loading bill/customer history.'),
          );
      if (seq != _bootstrapSeq) return; // superseded by a newer bootstrap
      logs = history.logs;
      bills = history.bills;
      customers = history.customers;
      batches = history.batches;
      await _migrateLegacyStockToBatches();
    } catch (error) {
      if (seq != _bootstrapSeq) return;
      historyError = error;
      debugPrint('[pend] history load error: $error');
    } finally {
      if (seq == _bootstrapSeq) {
        historyLoading = false;
        notifyListeners();
      }
    }
  }

  // ---- lookups ----
  Brand? brandOf(String id) => brands.where((b) => b.id == id).firstOrNull;
  Branch? branchOf(String id) => branches.where((b) => b.id == id).firstOrNull;
  Supplier? supplierOf(String id) =>
      suppliers.where((s) => s.id == id).firstOrNull;
  Product? productOf(String id) =>
      products.where((p) => p.id == id).firstOrNull;
  Stock stockOf(String id) => stock[id] ?? Stock(productId: id);
  Batch? batchOf(String id) => batches.where((b) => b.id == id).firstOrNull;

  /// Batches for one product, optionally narrowed to a branch — sorted FEFO
  /// (nearest expiry first; batches with no expiry last), per the reviewed
  /// FEFO allocation rule.
  List<Batch> batchesOf(String productId, {String? branchId}) {
    final list = batches
        .where((b) =>
            b.productId == productId &&
            (branchId == null || b.branchId == branchId))
        .toList()
      ..sort((a, b) {
        if (a.expiry == null && b.expiry == null) return 0;
        if (a.expiry == null) return 1;
        if (b.expiry == null) return -1;
        return a.expiry!.compareTo(b.expiry!);
      });
    return list;
  }
  Staff get owner => staff.firstWhere((s) => s.isAdmin,
      orElse: () => staff.isNotEmpty
          ? staff.first
          : const Staff(id: 'unknown', name: 'Staff', role: 'staff'));

  double effKg(String id) {
    final p = productOf(id);
    if (p == null) return 0;
    return stockOf(id).effectiveKg(p.bagWeightKg);
  }

  StockLevel levelOf(String id) {
    final p = productOf(id);
    if (p == null) return StockLevel.out;
    final e = effKg(id);
    final threshold = p.lowStockThresholdBags * p.bagWeightKg;
    if (e <= 0) return StockLevel.out;
    if (e < threshold) return StockLevel.low;
    return StockLevel.ok;
  }

  List<Product> get lowStock =>
      products.where((p) => levelOf(p.id) != StockLevel.ok).toList();

  /// Distinct product categories/types currently in the catalogue (for the
  /// Reports product-type filter). Products without one are simply absent
  /// from this list — they still show up under "All Products".
  List<String> get categories {
    final set = <String>{};
    for (final p in products) {
      final cat = p.category;
      if (cat != null && cat.isNotEmpty) set.add(cat);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<Bill> get finalBills =>
      bills.where((b) => b.status == BillStatus.finalized).toList();

  // ---- cart ----
  double get cartSubtotal => cart.fold(0.0, (s, l) => s + l.lineTotal);
  double get cartDiscount =>
      cart.fold(0.0, (s, l) => s + (l.catalogRate - l.rate) * l.qty);
  double get cartTotal => cartSubtotal;

  void addToCart(String productId, SaleType type, double qty, {double? rate}) {
    final p = productOf(productId);
    if (p == null) return;
    final catalog = p.catalogRate(type == SaleType.bag);
    cart.add(CartLine(
      productId: productId,
      saleType: type,
      qty: qty,
      catalogRate: catalog,
      rate: rate ?? catalog,
    ));
    notifyListeners();
  }

  void changeLineQty(int i, double delta) {
    final l = cart[i];
    final v = (l.qty + delta * l.step);
    l.qty = v < l.step ? l.step : double.parse(v.toStringAsFixed(2));
    notifyListeners();
  }

  void setLineQty(int i, double qty) {
    cart[i].qty = qty <= 0 ? cart[i].step : qty;
    notifyListeners();
  }

  void setLineRate(int i, double rate) {
    cart[i].rate = rate;
    notifyListeners();
  }

  void removeLine(int i) {
    cart.removeAt(i);
    notifyListeners();
  }

  void setCartCustomer(String? id) {
    cartCustomerId = id;
    notifyListeners();
  }

  // ---- payments ----
  void ensurePayments() {
    if (payments.isEmpty) payments.add(Payment(PayMode.cash, cartTotal));
  }

  void setPayment(int i, {PayMode? mode, double? amount}) {
    final p = payments[i];
    payments[i] = Payment(mode ?? p.mode, amount ?? p.amount);
    notifyListeners();
  }

  void addSplitPayment() {
    final paid = payments.fold(0.0, (s, p) => s + p.amount);
    payments.add(Payment(
        PayMode.credit, (cartTotal - paid).clamp(0, cartTotal).toDouble()));
    notifyListeners();
  }

  void removePayment(int i) {
    payments.removeAt(i);
    notifyListeners();
  }

  void resetPayments() {
    payments.clear();
  }

  // ---- override gating (see reviewed spec, findings 1 & 11) ----
  /// Returns null if the rate is allowed, or a reason string if blocked/needs PIN.
  /// [pinApproved] short-circuits the discount gate after Owner PIN entry.
  String? checkRate(CartLine line, double rate, {bool pinApproved = false}) {
    final p = productOf(line.productId);
    if (p == null) return 'उत्पादन सापडले नाही';
    final floor = p.floorRate(line.isBag);
    if (settings.floorOn && rate < floor) {
      return 'किमान भावाखाली · Below floor (min ₹${floor.round()})';
    }
    if (!pinApproved && settings.gateOverride) {
      final discPct = line.catalogRate == 0
          ? 0
          : (line.catalogRate - rate) / line.catalogRate * 100;
      if (discPct > settings.gateOverridePct) return 'NEEDS_PIN';
    }
    return null;
  }

  bool verifyOwnerPin(String pin) => pin == owner.pin;

  /// FEFO (First-Expiry-First-Out) allocation plan for one cart line: which
  /// batches to deplete, and by how much, without mutating anything — see
  /// the reviewed spec §7/§8/§19. Returns null if [branchId] has less than
  /// [qtyNeeded] of sellable (non-expired, non-blocked, in-stock) stock for
  /// this product, so the caller can fail the whole sale before anything is
  /// written. A product with no batches at all (not yet migrated/stocked)
  /// falls back to the legacy aggregate [Stock] check instead of failing
  /// outright, so it can still be sold.
  List<(Batch, double)>? _planFefo(
      String productId, String branchId, SaleType saleType, double qtyNeeded) {
    final product = productOf(productId);
    if (product == null) return null;
    final allBatches = batchesOf(productId, branchId: branchId);
    final candidates = allBatches
        .where((b) => b.isSellable(product.bagWeightKg))
        .toList(); // batchesOf already sorts FEFO (nearest expiry first)

    if (allBatches.isEmpty) {
      // No real batches for this product/branch at all yet — legacy
      // fallback using the aggregate rollup, so an unmigrated/never-stocked
      // product doesn't simply refuse to sell. (If batches DO exist but none
      // are currently sellable — all expired/blocked/depleted — this must
      // NOT fall back to the aggregate rollup, since that rollup still
      // counts expired-but-physically-present stock; falling through to the
      // empty-candidates branch below correctly fails the sale instead.)
      final s = stockOf(productId);
      final available =
          saleType == SaleType.bag ? s.bags.toDouble() : s.looseKg + s.bags * product.bagWeightKg;
      return available >= qtyNeeded ? [] : null;
    }

    final plan = <(Batch, double)>[];
    var remaining = qtyNeeded;
    for (final b in candidates) {
      if (remaining <= 0) break;
      final available = saleType == SaleType.bag
          ? b.bagsAvailable.toDouble()
          : b.availableKg(product.bagWeightKg);
      if (available <= 0) continue;
      final take = remaining < available ? remaining : available;
      plan.add((b, take));
      remaining -= take;
    }
    return remaining <= 0.0001 ? plan : null;
  }

  // ---- finalize sale (FEFO batch allocation + credit ledger) ----
  Future<SaleResult> finalizeSale() async {
    if (cart.isEmpty) {
      return const SaleResult.failure('बिल रिकामे · Cart is empty');
    }
    ensurePayments();
    final total = cartTotal;
    final paid = payments.fold(0.0, (s, p) => s + p.amount);
    if ((paid - total).abs() > 0.5) {
      return const SaleResult.failure(
          'पेमेंट रक्कम जुळत नाही · Payment must equal total');
    }
    final hasCredit =
        payments.any((p) => p.mode == PayMode.credit && p.amount > 0);
    if (hasCredit && cartCustomerId == null) {
      return const SaleResult.failure(
          'उधारसाठी ग्राहक निवडा · Pick a customer for credit');
    }
    final branchId = activeBranchId;
    if (branchId == null) {
      return const SaleResult.failure('शाखा निवडलेली नाही · No branch selected');
    }

    // Plan every line's FEFO allocation FIRST, without mutating anything —
    // if any line can't be fully covered by sellable (non-expired) stock,
    // fail the whole sale before anything is written (spec §19).
    final plans = <String, List<(Batch, double)>>{}; // cartLine index -> plan
    for (var i = 0; i < cart.length; i++) {
      final l = cart[i];
      final plan = _planFefo(l.productId, branchId, l.saleType, l.qty);
      if (plan == null) {
        final p = productOf(l.productId);
        return SaleResult.failure(
            'अपुरा साठा · Not enough sellable stock for ${p?.nameMr ?? l.productId}');
      }
      plans['$i'] = plan;
    }

    final number = await repo.nextBillNumber();
    final now = DateTime.now();
    final cust = cartCustomerId != null
        ? customers.firstWhere((c) => c.id == cartCustomerId)
        : null;

    // Build BillItems — one per (cart line, batch actually used); a line
    // that spans multiple batches becomes multiple BillItems (spec §8's
    // split-sale example), each retaining its own batch/expiry/supplier.
    final items = <BillItem>[];
    final touchedProducts = <String>{};
    for (var i = 0; i < cart.length; i++) {
      final l = cart[i];
      final plan = plans['$i']!;
      if (plan.isEmpty) {
        // Legacy fallback (no real batches yet) — one plain line, no batch info.
        items.add(BillItem(
          productId: l.productId,
          saleType: l.saleType,
          qty: l.qty,
          catalogRate: l.catalogRate,
          rate: l.rate,
          lineTotal: l.lineTotal,
        ));
        continue;
      }
      for (final (batch, qty) in plan) {
        items.add(BillItem(
          productId: l.productId,
          saleType: l.saleType,
          qty: qty,
          catalogRate: l.catalogRate,
          rate: l.rate,
          lineTotal: l.rate * qty,
          batchId: batch.id,
          batchNo: batch.batchNo,
          supplierId: batch.supplierId,
          expiry: batch.expiry,
        ));
      }
    }

    final bill = Bill(
      id: 'BILL$number',
      billNumber: number,
      customerId: cartCustomerId,
      customerName: cust?.name ?? '',
      items: items,
      subtotal: cartSubtotal,
      discountTotal: cartDiscount,
      total: total,
      payments: List.of(payments),
      at: now,
      staffId: owner.id,
      branchId: branchId,
    );

    // Commit: deduct each allocated batch (opening its own bags as needed
    // for a by-weight sale, so the kg sold traces back to the same batch),
    // and log one StockLog per batch actually depleted.
    for (var i = 0; i < cart.length; i++) {
      final l = cart[i];
      final plan = plans['$i']!;
      final p = productOf(l.productId)!;
      touchedProducts.add(l.productId);
      if (plan.isEmpty) {
        // Legacy aggregate deduction (no batches yet for this product).
        final s = stockOf(l.productId);
        if (l.saleType == SaleType.bag) {
          s.bags -= l.qty.round();
        } else {
          var need = l.qty;
          while (s.looseKg < need && s.bags > 0) {
            s.bags -= 1;
            s.looseKg += p.bagWeightKg;
          }
          s.looseKg -= need;
        }
        stock[l.productId] = s;
        await repo.setStock(s);
        _log(StockLog(
          id: _uid('L'),
          productId: l.productId,
          type: StockLogType.sale,
          bagsDelta: l.saleType == SaleType.bag ? -l.qty.round() : 0,
          looseKgDelta: l.saleType == SaleType.kg ? -l.qty : 0,
          billId: bill.id,
          branchId: branchId,
          at: now,
        ));
        continue;
      }
      for (final (batch, qty) in plan) {
        if (l.saleType == SaleType.bag) {
          batch.bagsAvailable -= qty.round();
          batch.bagsSold += qty.round();
        } else {
          var need = qty;
          // Open this SAME batch's bags as needed — the kg sold must trace
          // back to the batch it actually came from (spec §7).
          while (batch.looseKgAvailable < need && batch.bagsAvailable > 0) {
            batch.bagsAvailable -= 1;
            batch.looseKgAvailable += p.bagWeightKg;
            _log(StockLog(
              id: _uid('L'),
              productId: l.productId,
              type: StockLogType.bagOpened,
              bagsDelta: -1,
              looseKgDelta: p.bagWeightKg.toDouble(),
              note: 'auto on sale',
              branchId: branchId,
              batchId: batch.id,
              at: now,
            ));
          }
          batch.looseKgAvailable -= need;
          batch.looseKgSold += need;
        }
        batch.updatedAt = now;
        await repo.upsertBatch(batch);
        _log(StockLog(
          id: _uid('L'),
          productId: l.productId,
          type: StockLogType.sale,
          bagsDelta: l.saleType == SaleType.bag ? -qty.round() : 0,
          looseKgDelta: l.saleType == SaleType.kg ? -qty : 0,
          billId: bill.id,
          branchId: branchId,
          batchId: batch.id,
          supplierId: batch.supplierId,
          at: now,
        ));
      }
    }
    for (final pid in touchedProducts) {
      recomputeStockFor(pid);
    }

    bills.insert(0, bill);
    await repo.saveBill(bill);

    // Credit -> ledger.
    final creditAmt = bill.creditAmount;
    if (creditAmt > 0 && cust != null) {
      final entry = LedgerEntry(
          type: 'credit-sale',
          amount: creditAmt,
          billId: bill.id,
          note: 'bill #$number',
          at: now);
      cust.outstanding += creditAmt;
      cust.ledger.insert(0, entry);
      await repo.addLedgerEntry(cust.id, entry, cust.outstanding);
    }

    // Clear cart.
    cart.clear();
    cartCustomerId = null;
    payments.clear();
    notifyListeners();
    return SaleResult.success(bill);
  }

  Future<void> voidBill(String billId) async {
    final idx = bills.indexWhere((b) => b.id == billId);
    if (idx < 0 || bills[idx].status == BillStatus.voided) return;
    final b = bills[idx];
    final now = DateTime.now();
    final touchedProducts = <String>{};
    for (final it in b.items) {
      touchedProducts.add(it.productId);
      // Credit back to the exact batch this line was sold from (spec §13 —
      // "prefer returning stock to the original batch"); a legacy line with
      // no batchId (sold before batch tracking, or a never-migrated
      // product) falls back to the aggregate rollup.
      final batch = it.batchId == null ? null : batchOf(it.batchId!);
      if (batch != null) {
        if (it.saleType == SaleType.bag) {
          batch.bagsAvailable += it.qty.round();
          batch.bagsSold -= it.qty.round();
        } else {
          batch.looseKgAvailable += it.qty;
          batch.looseKgSold -= it.qty;
        }
        batch.updatedAt = now;
        await repo.upsertBatch(batch);
      } else {
        final s = stockOf(it.productId);
        if (it.saleType == SaleType.bag) {
          s.bags += it.qty.round();
        } else {
          s.looseKg += it.qty;
        }
        stock[it.productId] = s;
        await repo.setStock(s);
      }
      _log(StockLog(
        id: _uid('L'),
        productId: it.productId,
        type: StockLogType.saleVoid,
        bagsDelta: it.saleType == SaleType.bag ? it.qty.round() : 0,
        looseKgDelta: it.saleType == SaleType.kg ? it.qty : 0,
        billId: b.id,
        note: 'bill #${b.billNumber}',
        at: now,
        branchId: b.branchId,
        batchId: it.batchId,
        supplierId: it.supplierId,
      ));
    }
    for (final pid in touchedProducts) {
      recomputeStockFor(pid);
    }
    // Reverse credit.
    if (b.customerId != null && b.creditAmount > 0) {
      final cust = customers.where((c) => c.id == b.customerId).firstOrNull;
      if (cust != null) {
        cust.outstanding = (cust.outstanding - b.creditAmount)
            .clamp(0, double.infinity)
            .toDouble();
        final entry = LedgerEntry(
            type: 'repayment',
            amount: b.creditAmount,
            note: 'void #${b.billNumber}',
            at: now);
        cust.ledger.insert(0, entry);
        await repo.addLedgerEntry(cust.id, entry, cust.outstanding);
      }
    }
    bills[idx] = b.copyWith(status: BillStatus.voided);
    await repo.updateBillStatus(b.id, BillStatus.voided);
    notifyListeners();
  }

  /// How much of one bill line has already been returned — scans existing
  /// [StockLogType.returned] entries logged against this exact bill+line
  /// (matched by billId + batchId + productId), so a partial return can
  /// never exceed what that line actually sold (spec §13/§19). A legacy
  /// line with no batchId is matched by billId + productId alone.
  double returnedSoFar(Bill bill, BillItem item) => logs
      .where((l) =>
          l.type == StockLogType.returned &&
          l.billId == bill.id &&
          l.productId == item.productId &&
          l.batchId == item.batchId)
      .fold(0.0, (s, l) => s + l.bagsDelta.abs() + l.looseKgDelta.abs());

  /// Partial sales return (spec §13): credits [qty] back to the exact batch
  /// [item] was sold from (falling back to the aggregate rollup for a
  /// legacy line with no batch), and never lets the total returned on this
  /// line exceed what it originally sold. Does not alter the original bill
  /// — bills are an immutable audit record; the return is its own logged
  /// movement, traceable back to [bill] via [StockLog.billId].
  Future<String?> returnSaleLine(Bill bill, BillItem item, double qty) async {
    if (qty <= 0) return 'योग्य प्रमाण टाका · Enter a valid quantity';
    final already = returnedSoFar(bill, item);
    if (already + qty > item.qty + 0.0001) {
      return 'मूळ विक्रीपेक्षा जास्त परतावा शक्य नाही · Cannot return more than sold';
    }
    final now = DateTime.now();
    final batch = item.batchId == null ? null : batchOf(item.batchId!);
    if (batch != null) {
      if (item.saleType == SaleType.bag) {
        batch.bagsAvailable += qty.round();
        batch.bagsReturned += qty.round();
      } else {
        batch.looseKgAvailable += qty;
        batch.looseKgReturned += qty;
      }
      batch.updatedAt = now;
      await repo.upsertBatch(batch);
    } else {
      final s = stockOf(item.productId);
      if (item.saleType == SaleType.bag) {
        s.bags += qty.round();
      } else {
        s.looseKg += qty;
      }
      stock[item.productId] = s;
      await repo.setStock(s);
    }
    recomputeStockFor(item.productId);
    _log(StockLog(
      id: _uid('L'),
      productId: item.productId,
      type: StockLogType.returned,
      bagsDelta: item.saleType == SaleType.bag ? qty.round() : 0,
      looseKgDelta: item.saleType == SaleType.kg ? qty : 0,
      billId: bill.id,
      note: 'partial return · bill #${bill.billNumber}',
      at: now,
      branchId: bill.branchId,
      batchId: item.batchId,
      supplierId: item.supplierId,
    ));
    notifyListeners();
    return null;
  }

  // ---- inventory ----
  /// Records a purchase against a real [Batch] (spec §1/§5/§17: Branch →
  /// Product → Supplier → Batch → Expiry → Stock). If a still-active batch
  /// with the same (branch, product, batchNo) already exists, tops it up
  /// (spec §5 "handle it according to existing inventory rules instead of
  /// blindly creating duplicate batches") rather than creating a second one;
  /// otherwise creates a new batch. Always keeps the cross-branch [Stock]
  /// rollup in sync via [recomputeStockFor].
  ///
  /// Validation (spec §19) is the caller's job for user-facing messages
  /// (see [StockInScreen]) — this asserts the same invariants defensively so
  /// a programming mistake fails loudly rather than corrupting inventory.
  Future<void> stockIn({
    required String branchId,
    required String productId,
    required String supplierId,
    String? batchNo,
    DateTime? manufactureDate,
    DateTime? expiry,
    int bags = 0,
    double looseKg = 0,
    double? cost,
  }) async {
    assert(bags > 0 || looseKg > 0, 'stockIn: quantity must be > 0');
    final product = productOf(productId);
    assert(product != null, 'stockIn: unknown product');
    if (product == null) return;
    assert(!product.batchTrackingEnabled || (batchNo != null && batchNo.isNotEmpty),
        'stockIn: batch number required for this product');
    assert(!product.expiryTrackingEnabled || expiry != null,
        'stockIn: expiry required for this product');

    final now = DateTime.now();
    Batch? target;
    if (batchNo != null && batchNo.isNotEmpty) {
      target = batches
          .where((b) =>
              b.branchId == branchId &&
              b.productId == productId &&
              b.batchNo == batchNo &&
              b.status == BatchStatus.active)
          .firstOrNull;
    }

    if (target != null) {
      target.bagsReceived += bags;
      target.bagsAvailable += bags;
      target.looseKgAvailable += looseKg;
      if (cost != null) target.unitCost = cost; // latest purchase cost wins
      target.updatedAt = now;
      await repo.upsertBatch(target);
    } else {
      target = Batch(
        id: _uid('batch'),
        branchId: branchId,
        productId: productId,
        supplierId: supplierId,
        batchNo: batchNo ?? 'B-${DateTime.now().millisecondsSinceEpoch}',
        manufactureDate: manufactureDate,
        expiry: expiry,
        unitCost: cost ?? 0,
        bagsReceived: bags,
        bagsAvailable: bags,
        looseKgAvailable: looseKg,
        createdAt: now,
        updatedAt: now,
      );
      batches.add(target);
      await repo.upsertBatch(target);
    }

    recomputeStockFor(productId);
    _log(StockLog(
      id: _uid('L'),
      productId: productId,
      type: StockLogType.purchase,
      bagsDelta: bags,
      looseKgDelta: looseKg,
      cost: cost,
      batchNo: target.batchNo,
      expiry: expiry,
      supplier: supplierOf(supplierId)?.name,
      at: now,
      branchId: branchId,
      batchId: target.id,
      supplierId: supplierId,
    ));
    notifyListeners();
  }

  Future<void> openBag(String productId) async {
    final s = stockOf(productId);
    final p = productOf(productId)!;
    if (s.bags < 1) return;
    s.bags -= 1;
    s.looseKg += p.bagWeightKg;
    stock[productId] = s;
    await repo.setStock(s);
    _log(StockLog(
        id: _uid('L'),
        productId: productId,
        type: StockLogType.bagOpened,
        bagsDelta: -1,
        looseKgDelta: p.bagWeightKg.toDouble(),
        note: 'manual',
        at: DateTime.now()));
    notifyListeners();
  }

  Future<void> adjustStock(
      String productId, int bagsDelta, double kgDelta, String note) async {
    final s = stockOf(productId);
    s.bags = (s.bags + bagsDelta).clamp(0, 1 << 30);
    s.looseKg = (s.looseKg + kgDelta).clamp(0, double.infinity).toDouble();
    stock[productId] = s;
    await repo.setStock(s);
    _log(StockLog(
        id: _uid('L'),
        productId: productId,
        type: StockLogType.adjustment,
        bagsDelta: bagsDelta,
        looseKgDelta: kgDelta,
        note: note,
        at: DateTime.now()));
    notifyListeners();
  }

  /// Branch-to-branch stock transfer (spec §14). Deducts [qty] from
  /// [sourceBatchId] and creates or tops up a batch in [destBranchId]
  /// carrying the same batch no./expiry/cost/supplier, linked back via
  /// [Batch.sourceBatchId] — never merged into a destination batch that
  /// came from a *different* origin batch, so distinct lots stay distinct.
  Future<String?> transferStock(
      String sourceBatchId, String destBranchId, {int bags = 0, double looseKg = 0}) async {
    final source = batchOf(sourceBatchId);
    if (source == null) return 'बॅच सापडली नाही · Batch not found';
    if (bags <= 0 && looseKg <= 0) {
      return 'योग्य प्रमाण टाका · Enter a valid quantity';
    }
    if (bags > source.bagsAvailable || looseKg > source.looseKgAvailable + 0.0001) {
      return 'उपलब्ध साठ्यापेक्षा जास्त हस्तांतरण शक्य नाही · Cannot transfer more than available';
    }
    final now = DateTime.now();
    source.bagsAvailable -= bags;
    source.looseKgAvailable -= looseKg;
    source.updatedAt = now;
    await repo.upsertBatch(source);
    _log(StockLog(
      id: _uid('L'),
      productId: source.productId,
      type: StockLogType.transferOut,
      bagsDelta: -bags,
      looseKgDelta: -looseKg,
      note: 'to branch $destBranchId',
      at: now,
      branchId: source.branchId,
      batchId: source.id,
      supplierId: source.supplierId,
    ));

    // Same batch no. already open at the destination (from an earlier
    // transfer of this same lot) — top it up rather than duplicating it.
    var dest = batches
        .where((b) =>
            b.branchId == destBranchId &&
            b.sourceBatchId == source.id &&
            b.status == BatchStatus.active)
        .firstOrNull;
    if (dest != null) {
      dest.bagsReceived += bags;
      dest.bagsAvailable += bags;
      dest.looseKgAvailable += looseKg;
      dest.updatedAt = now;
      await repo.upsertBatch(dest);
    } else {
      dest = Batch(
        id: _uid('batch'),
        branchId: destBranchId,
        productId: source.productId,
        supplierId: source.supplierId,
        batchNo: source.batchNo,
        manufactureDate: source.manufactureDate,
        expiry: source.expiry,
        unitCost: source.unitCost,
        bagsReceived: bags,
        bagsAvailable: bags,
        looseKgAvailable: looseKg,
        sourceBatchId: source.id,
        createdAt: now,
        updatedAt: now,
      );
      batches.add(dest);
      await repo.upsertBatch(dest);
    }
    _log(StockLog(
      id: _uid('L'),
      productId: source.productId,
      type: StockLogType.transferIn,
      bagsDelta: bags,
      looseKgDelta: looseKg,
      note: 'from branch ${source.branchId}',
      at: now,
      branchId: destBranchId,
      batchId: dest.id,
      supplierId: source.supplierId,
    ));

    recomputeStockFor(source.productId);
    notifyListeners();
    return null;
  }

  // ---- customers / khata ----
  Future<Customer> saveCustomer(
      {String? id, required String name, String mobile = ''}) async {
    if (id != null) {
      final c = customers.firstWhere((x) => x.id == id);
      c.name = name;
      c.mobile = mobile;
      await repo.upsertCustomer(c);
      notifyListeners();
      return c;
    }
    final c = Customer(id: _uid('c'), name: name, mobile: mobile);
    customers.add(c);
    await repo.upsertCustomer(c);
    notifyListeners();
    return c;
  }

  Future<void> recordRepayment(
      String customerId, double amount, PayMode mode) async {
    final c = customers.firstWhere((x) => x.id == customerId);
    c.outstanding =
        (c.outstanding - amount).clamp(0, double.infinity).toDouble();
    final entry = LedgerEntry(
        type: 'repayment', amount: amount, note: mode.name, at: DateTime.now());
    c.ledger.insert(0, entry);
    await repo.addLedgerEntry(c.id, entry, c.outstanding);
    notifyListeners();
  }

  double get totalOutstanding =>
      customers.fold(0.0, (s, c) => s + c.outstanding);

  // ---- catalogue ----
  Future<Product> saveProduct(
      {String? id,
      required String brandId,
      required String name,
      required String nameMr,
      required int bagWeightKg,
      required double fullBagPrice,
      required double perKgPrice,
      double costPrice = 0,
      double minPriceFloor = 0,
      int? lowThreshold,
      Object? photoUrl = _notProvided,
      Object? category = _notProvided}) async {
    late final Product saved;
    if (id != null) {
      final idx = products.indexWhere((p) => p.id == id);
      products[idx] = products[idx].copyWith(
        brandId: brandId,
        name: name,
        nameMr: nameMr,
        bagWeightKg: bagWeightKg,
        fullBagPrice: fullBagPrice,
        perKgPrice: perKgPrice,
        costPrice: costPrice,
        minPriceFloor: minPriceFloor,
        lowStockThresholdBags: lowThreshold,
        photoUrl: identical(photoUrl, _notProvided)
            ? products[idx].photoUrl
            : photoUrl as String?,
        category: identical(category, _notProvided)
            ? products[idx].category
            : category as String?,
      );
      await repo.upsertProduct(products[idx]);
      saved = products[idx];
    } else {
      final np = Product(
        id: _uid('p'),
        brandId: brandId,
        name: name,
        nameMr: nameMr,
        bagWeightKg: bagWeightKg,
        fullBagPrice: fullBagPrice,
        perKgPrice: perKgPrice,
        costPrice: costPrice,
        minPriceFloor: minPriceFloor,
        lowStockThresholdBags: lowThreshold ?? settings.lowDefaultBags,
        qr: 'PEND-${DateTime.now().millisecondsSinceEpoch}',
        photoUrl:
            identical(photoUrl, _notProvided) ? null : photoUrl as String?,
        category:
            identical(category, _notProvided) ? null : category as String?,
      );
      products.add(np);
      stock[np.id] = Stock(productId: np.id);
      await repo.upsertProduct(np, initialStock: stock[np.id]);
      saved = np;
    }
    notifyListeners();
    return saved;
  }

  Future<void> deleteProduct(String id) async {
    products.removeWhere((p) => p.id == id);
    stock.remove(id);
    await repo.deleteProduct(id);
    notifyListeners();
  }

  Future<void> saveBrand(
      {String? id, required String name, required String nameMr}) async {
    if (id != null) {
      final idx = brands.indexWhere((b) => b.id == id);
      brands[idx] = brands[idx].copyWith(name: name, nameMr: nameMr);
      await repo.upsertBrand(brands[idx]);
    } else {
      final b = Brand(id: _uid('b'), name: name, nameMr: nameMr);
      brands.add(b);
      await repo.upsertBrand(b);
    }
    notifyListeners();
  }

  Future<void> saveBranch(
      {String? id,
      required String name,
      required String nameMr,
      String address = '',
      bool active = true}) async {
    if (id != null) {
      final idx = branches.indexWhere((b) => b.id == id);
      branches[idx] = branches[idx]
          .copyWith(name: name, nameMr: nameMr, address: address, active: active);
      await repo.upsertBranch(branches[idx]);
    } else {
      final b = Branch(
          id: _uid('br'), name: name, nameMr: nameMr, address: address);
      branches.add(b);
      await repo.upsertBranch(b);
      activeBranchId ??= b.id;
    }
    notifyListeners();
  }

  // ---- suppliers ----
  Future<Supplier> saveSupplier(
      {String? id,
      required String name,
      String mobile = '',
      String altMobile = '',
      String address = '',
      String gstin = '',
      String email = '',
      double openingBalance = 0,
      bool active = true,
      String notes = ''}) async {
    late final Supplier saved;
    if (id != null) {
      final idx = suppliers.indexWhere((s) => s.id == id);
      suppliers[idx] = suppliers[idx].copyWith(
        name: name,
        mobile: mobile,
        altMobile: altMobile,
        address: address,
        gstin: gstin,
        email: email,
        openingBalance: openingBalance,
        active: active,
        notes: notes,
      );
      saved = suppliers[idx];
    } else {
      saved = Supplier(
        id: _uid('sup'),
        name: name,
        mobile: mobile,
        altMobile: altMobile,
        address: address,
        gstin: gstin,
        email: email,
        openingBalance: openingBalance,
        active: active,
        notes: notes,
        createdAt: DateTime.now(),
      );
      suppliers.add(saved);
    }
    await repo.upsertSupplier(saved);
    notifyListeners();
    return saved;
  }

  /// A supplier referenced by any batch/purchase can never be hard-deleted —
  /// only deactivated (spec: "Do NOT hard-delete a supplier that is
  /// referenced by purchases, stock batches, bills or accounting records").
  bool supplierHasHistory(String supplierId) =>
      batches.any((b) => b.supplierId == supplierId) ||
      logs.any((l) => l.supplierId == supplierId);

  Future<void> deleteSupplier(String id) async {
    if (supplierHasHistory(id)) {
      // Soft-delete: deactivate instead of removing the record.
      final idx = suppliers.indexWhere((s) => s.id == id);
      if (idx < 0) return;
      suppliers[idx] = suppliers[idx].copyWith(active: false);
      await repo.upsertSupplier(suppliers[idx]);
      notifyListeners();
      return;
    }
    suppliers.removeWhere((s) => s.id == id);
    await repo.deleteSupplier(id);
    notifyListeners();
  }

  Future<void> saveStaff(Staff member) async {
    final index = staff.indexWhere((s) => s.id == member.id);
    if (index < 0) {
      staff.add(member);
    } else {
      staff[index] = member;
    }
    try {
      await repo.upsertStaff(member);
      notifyListeners();
    } catch (_) {
      if (index < 0) staff.removeWhere((s) => s.id == member.id);
      rethrow;
    }
  }

  // ---- settings ----
  Future<void> updateSettings(void Function(AppSettings) mutate) async {
    final next = settings.copy();
    mutate(next);
    await repo.saveSettings(next);
    settings = next;
    notifyListeners();
  }

  Future<void> resetSampleData() async {
    await bootstrap();
    cart.clear();
    cartCustomerId = null;
    payments.clear();
    notifyListeners();
  }

  // ---- reports ----
  List<Bill> billsSince(DateTime since) =>
      finalBills.where((b) => b.at.isAfter(since)).toList();

  // ---- helpers ----
  void _log(StockLog l) => logs.insert(0, l);
  int _seq = 0;
  String _uid(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch}${_seq++}';

  /// Recomputes the cross-branch [Stock] rollup for one product from its
  /// [batches] — the batches are the source of truth; [stock] is only a fast,
  /// branch-agnostic read path for dashboard/product-list display (see the
  /// reviewed branch/batch/expiry architecture). Call after any batch
  /// mutation (stock-in, sale, void, adjustment, transfer).
  void recomputeStockFor(String productId) {
    var bags = 0;
    var looseKg = 0.0;
    for (final b in batches.where((b) => b.productId == productId)) {
      bags += b.bagsAvailable;
      looseKg += b.looseKgAvailable;
    }
    final s = Stock(productId: productId, bags: bags, looseKg: looseKg);
    stock[productId] = s;
    unawaited(repo.setStock(s));
  }

  // ---- migration: pre-branch/batch data → the new architecture ----
  // Runs once, automatically, the first time a shop with no branches yet is
  // opened (a fresh Firestore project or an existing one from before this
  // change) — see reviewed spec §18 "do not break existing data". Both steps
  // are idempotent (gated on "nothing to migrate yet") so a retried
  // bootstrap, or a shop that already has branches, never re-runs them.
  bool _migratedBranches = false;
  Future<void> _migrateBranchesAndProducts() async {
    if (_migratedBranches || branches.isNotEmpty) {
      _migratedBranches = true;
      return;
    }
    _migratedBranches = true;
    final main = Branch(id: _uid('br'), name: 'Main Branch', nameMr: 'मुख्य शाखा');
    branches.add(main);
    await repo.upsertBranch(main);
    for (var i = 0; i < products.length; i++) {
      if (products[i].branchIds.isNotEmpty) continue;
      products[i] = products[i].copyWith(branchIds: [main.id]);
      await repo.upsertProduct(products[i]);
    }
  }

  /// Step two of the migration — needs [batches] (history-tier) to know
  /// whether it has already run. For every product with real stock but no
  /// batch yet, creates exactly ONE legacy batch holding that current
  /// quantity (see the reviewed migration strategy: this deliberately does
  /// NOT try to reconstruct one batch per historical purchase log, since the
  /// old aggregate model never tracked remaining-quantity-per-purchase and
  /// guessing would misstate it — historical StockLogs stay exactly as they
  /// are, untouched, as a read-only audit trail).
  bool _migratedBatches = false;
  Future<void> _migrateLegacyStockToBatches() async {
    if (_migratedBatches || batches.isNotEmpty) {
      _migratedBatches = true;
      return;
    }
    _migratedBatches = true;
    final mainBranchId = activeBranchId ?? branches.firstOrNull?.id;
    if (mainBranchId == null) return; // no branch to attach legacy stock to
    final now = DateTime.now();
    for (final p in products) {
      final s = stockOf(p.id);
      if (s.bags <= 0 && s.looseKg <= 0) continue;
      final b = Batch(
        id: _uid('batch'),
        branchId: mainBranchId,
        productId: p.id,
        batchNo: 'LEGACY-${p.id}',
        unitCost: p.costPrice,
        bagsReceived: s.bags,
        bagsAvailable: s.bags,
        looseKgAvailable: s.looseKg,
        createdAt: now,
        updatedAt: now,
      );
      batches.add(b);
      await repo.upsertBatch(b);
    }
  }
}

const Object _notProvided = Object();
