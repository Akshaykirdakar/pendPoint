import '../models/app_settings.dart';
import '../models/bill.dart';
import '../models/brand.dart';
import '../models/customer.dart';
import '../models/enums.dart';
import '../models/product.dart';
import '../models/staff.dart';
import '../models/stock.dart';
import '../models/stock_log.dart';

/// A full bootstrap snapshot of the shop. Kept as a convenience for repository
/// implementations (e.g. [InMemoryRepository] builds one seed and splits it
/// into [CoreSnapshot]/[HistorySnapshot]) — the app itself only ever asks for
/// the two staged pieces below.
class Snapshot {
  final List<Brand> brands;
  final List<Product> products;
  final Map<String, Stock> stock; // productId -> Stock
  final List<StockLog> logs;
  final List<Bill> bills;
  final List<Customer> customers;
  final List<Staff> staff;
  final AppSettings settings;
  final int billCounter;

  Snapshot({
    required this.brands,
    required this.products,
    required this.stock,
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
/// on potentially-large history.
class CoreSnapshot {
  final List<Brand> brands;
  final List<Product> products;
  final Map<String, Stock> stock;
  final List<Staff> staff;
  final AppSettings settings;
  final int billCounter;

  CoreSnapshot({
    required this.brands,
    required this.products,
    required this.stock,
    required this.staff,
    required this.settings,
    required this.billCounter,
  });
}

/// The potentially-large history data — bills (with items), stock logs, and
/// customers (with their full ledgers) — loaded in the background after
/// [CoreSnapshot], so a shop with years of bills doesn't delay opening the
/// counter screen.
class HistorySnapshot {
  final List<StockLog> logs;
  final List<Bill> bills;
  final List<Customer> customers;

  HistorySnapshot({
    required this.logs,
    required this.bills,
    required this.customers,
  });
}

/// Persistence boundary. Swap [InMemoryRepository] for [FirestoreRepository]
/// in main.dart once Firebase is configured — nothing else changes.
abstract class Repository {
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

  Future<void> setStock(Stock stock);
  Future<void> addStockLog(StockLog log);

  Future<void> saveBill(Bill bill);
  Future<void> updateBillStatus(String billId, BillStatus status);

  Future<void> upsertCustomer(Customer customer);
  Future<void> addLedgerEntry(
      String customerId, LedgerEntry entry, double newOutstanding);

  Future<void> saveSettings(AppSettings settings);
}
