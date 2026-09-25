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

/// A full bootstrap snapshot of the shop. Kept as a convenience for repository
/// implementations (e.g. [InMemoryRepository] builds one seed and splits it
/// into [CoreSnapshot]/[HistorySnapshot]) — the app itself only ever asks for
/// the two staged pieces below.
class Snapshot {
  final List<Brand> brands;
  final List<Branch> branches;
  final List<Supplier> suppliers;
  final List<Product> products;
  final Map<String, Stock> stock; // productId -> Stock
  final List<Batch> batches;
  final List<StockLog> logs;
  final List<Bill> bills;
  final List<Customer> customers;
  final List<Staff> staff;
  final AppSettings settings;
  final int billCounter;

  Snapshot({
    required this.brands,
    required this.branches,
    required this.suppliers,
    required this.products,
    required this.stock,
    required this.batches,
    required this.logs,
    required this.bills,
    required this.customers,
    required this.staff,
    required this.settings,
    required this.billCounter,
  });
}

/// Everything the counter UI needs to open for business: catalogue, current
/// stock, settings, and staff. Deliberately excludes bills/customers/logs —
/// [AppState.bootstrap] shows the POS as soon as this loads, without waiting
/// on potentially-large history. Branches/suppliers are masters (rarely
/// change) so they load with the core, same as brands.
class CoreSnapshot {
  final List<Brand> brands;
  final List<Branch> branches;
  final List<Supplier> suppliers;
  final List<Product> products;
  final Map<String, Stock> stock;
  final List<Staff> staff;
  final AppSettings settings;
  final int billCounter;

  CoreSnapshot({
    required this.brands,
    required this.branches,
    required this.suppliers,
    required this.products,
    required this.stock,
    required this.staff,
    required this.settings,
    required this.billCounter,
  });
}

/// The potentially-large history data — bills (with items), stock logs,
/// batches, and customers (with their full ledgers) — loaded in the
/// background after [CoreSnapshot], so a shop with years of bills doesn't
/// delay opening the counter screen. Batches sit here (not in [CoreSnapshot])
/// because they mutate on every sale/stock-in, like stock logs.
class HistorySnapshot {
  final List<StockLog> logs;
  final List<Bill> bills;
  final List<Customer> customers;
  final List<Batch> batches;

  HistorySnapshot({
    required this.logs,
    required this.bills,
    required this.customers,
    required this.batches,
  });
}

/// Persistence boundary. Swap [InMemoryRepository] for [FirestoreRepository]
/// in main.dart once Firebase is configured — nothing else changes.
abstract class Repository {
  /// The signed-in staff member for an authenticated repository. Local/demo
  /// repositories deliberately have no user, keeping their UI Firebase-free.
  String? get currentUserId => null;

  /// Catalogue + stock + settings + staff — everything needed to open the
  /// counter screen. Load this first and show the UI as soon as it resolves.
  Future<CoreSnapshot> loadCore();

  /// Bills, stock logs, and customer ledgers. Load this in the background
  /// after [loadCore] — the counter UI does not wait on it.
  Future<HistorySnapshot> loadHistory();

  Future<int> nextBillNumber();

  Future<void> upsertBrand(Brand brand);
  Future<void> upsertStaff(Staff staff);
  Future<void> upsertProduct(Product product, {Stock? initialStock});
  Future<void> deleteProduct(String productId);

  Future<void> upsertBranch(Branch branch);
  Future<void> upsertSupplier(Supplier supplier);
  Future<void> deleteSupplier(String supplierId);
  Future<void> upsertBatch(Batch batch);

  Future<void> setStock(Stock stock);
  Future<void> addStockLog(StockLog log);

  Future<void> saveBill(Bill bill);
  Future<void> updateBillStatus(String billId, BillStatus status);

  Future<void> upsertCustomer(Customer customer);
  Future<void> addLedgerEntry(
      String customerId, LedgerEntry entry, double newOutstanding);

  Future<void> saveSettings(AppSettings settings);
}
