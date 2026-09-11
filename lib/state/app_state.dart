import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../data/repository.dart';
import '../models/app_settings.dart';
import '../models/bill.dart';
import '../models/brand.dart';
import '../models/customer.dart';
import '../models/enums.dart';
import '../models/product.dart';
import '../models/staff.dart';
import '../models/stock.dart';
import '../models/stock_log.dart';
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
  List<Product> products = [];
  Map<String, Stock> stock = {};
  List<StockLog> logs = [];
  List<Bill> bills = [];
  List<Customer> customers = [];
  List<Staff> staff = [];
  AppSettings settings = AppSettings();
  bool loading = true;
  Object? bootstrapError;

  // ---- current cart ----
  final List<CartLine> cart = [];
  String? cartCustomerId;
  final List<Payment> payments = [];

  Future<void> bootstrap() async {
    bootstrapError = null;
    loading = true;
    notifyListeners();
    try {
      // A hung Firestore call (dropped connection, silently-blocked request,
      // stuck IndexedDB/persistence layer on web) should surface as an
      // error the UI can show, not spin the splash screen forever.
      final s = await repo.loadAll().timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw StateError(
            'Timed out loading shop data — check your connection and Firestore rules.'),
      );
      brands = s.brands;
      products = s.products;
      stock = s.stock;
      logs = s.logs;
      bills = s.bills;
      customers = s.customers;
      staff = s.staff;
      settings = s.settings;
    } catch (error) {
      bootstrapError = error;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ---- lookups ----
  Brand? brandOf(String id) => brands.where((b) => b.id == id).firstOrNull;
  Product? productOf(String id) =>
      products.where((p) => p.id == id).firstOrNull;
  Stock stockOf(String id) => stock[id] ?? Stock(productId: id);
  Staff get owner => staff.firstWhere(
      (s) => s.isAdmin,
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

  List<Bill> get finalBills =>
      bills.where((b) => b.status == BillStatus.finalized).toList();

  /// Products with a purchase-log expiry within 30 days and still in stock.
  List<({Product product, int days, String? batch})> get nearExpiry {
    final now = DateTime.now();
    final out = <({Product product, int days, String? batch})>[];
    for (final l in logs) {
      if (l.type != StockLogType.purchase || l.expiry == null) continue;
      final days = l.expiry!.difference(now).inDays;
      final p = productOf(l.productId);
      if (days <= 30 && p != null && effKg(l.productId) > 0) {
        out.add((product: p, days: days, batch: l.batchNo));
      }
    }
    return out;
  }

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

  // ---- finalize sale (atomic stock deduction + credit ledger) ----
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

    final number = await repo.nextBillNumber();
    final now = DateTime.now();
    final cust = cartCustomerId != null
        ? customers.firstWhere((c) => c.id == cartCustomerId)
        : null;

    final items = cart
        .map((l) => BillItem(
              productId: l.productId,
              saleType: l.saleType,
              qty: l.qty,
              catalogRate: l.catalogRate,
              rate: l.rate,
              lineTotal: l.lineTotal,
            ))
        .toList();

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
    );

    // Deduct stock; open bags as needed for by-weight sales.
    for (final it in items) {
      final s = stockOf(it.productId);
      final p = productOf(it.productId)!;
      if (it.saleType == SaleType.bag) {
        s.bags -= it.qty.round();
      } else {
        var need = it.qty;
        while (s.looseKg < need && s.bags > 0) {
          s.bags -= 1;
          s.looseKg += p.bagWeightKg;
          _log(StockLog(
            id: _uid('L'),
            productId: it.productId,
            type: StockLogType.bagOpened,
            bagsDelta: -1,
            looseKgDelta: p.bagWeightKg.toDouble(),
            note: 'auto on sale',
            at: now,
          ));
        }
        s.looseKg -= need;
      }
      stock[it.productId] = s;
      await repo.setStock(s);
      _log(StockLog(
        id: _uid('L'),
        productId: it.productId,
        type: StockLogType.sale,
        bagsDelta: it.saleType == SaleType.bag ? -it.qty.round() : 0,
        looseKgDelta: it.saleType == SaleType.kg ? -it.qty : 0,
        billId: bill.id,
        at: now,
      ));
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
    for (final it in b.items) {
      final s = stockOf(it.productId);
      if (it.saleType == SaleType.bag) {
        s.bags += it.qty.round();
      } else {
        s.looseKg += it.qty;
      }
      stock[it.productId] = s;
      await repo.setStock(s);
      _log(StockLog(
        id: _uid('L'),
        productId: it.productId,
        type: StockLogType.saleVoid,
        bagsDelta: it.saleType == SaleType.bag ? it.qty.round() : 0,
        looseKgDelta: it.saleType == SaleType.kg ? it.qty : 0,
        billId: b.id,
        note: 'bill #${b.billNumber}',
        at: now,
      ));
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

  // ---- inventory ----
  Future<void> stockIn(String productId, int bags,
      {double? cost, String? batch, DateTime? expiry, String? supplier}) async {
    final s = stockOf(productId);
    s.bags += bags;
    stock[productId] = s;
    await repo.setStock(s);
    _log(StockLog(
      id: _uid('L'),
      productId: productId,
      type: StockLogType.purchase,
      bagsDelta: bags,
      cost: cost,
      batchNo: batch,
      expiry: expiry,
      supplier: supplier,
      at: DateTime.now(),
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
  Future<void> saveProduct(
      {String? id,
      required String brandId,
      required String name,
      required String nameMr,
      required int bagWeightKg,
      required double fullBagPrice,
      required double perKgPrice,
      double costPrice = 0,
      double minPriceFloor = 0,
      int? lowThreshold}) async {
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
      );
      await repo.upsertProduct(products[idx]);
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
      );
      products.add(np);
      stock[np.id] = Stock(productId: np.id);
      await repo.upsertProduct(np, initialStock: stock[np.id]);
    }
    notifyListeners();
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

  // ---- settings ----
  Future<void> updateSettings(void Function(AppSettings) mutate) async {
    mutate(settings);
    await repo.saveSettings(settings);
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
}
