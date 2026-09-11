import '../models/app_settings.dart';
import '../models/bill.dart';
import '../models/brand.dart';
import '../models/customer.dart';
import '../models/enums.dart';
import '../models/product.dart';
import '../models/staff.dart';
import '../models/stock.dart';
import '../models/stock_log.dart';

/// A full bootstrap snapshot of the shop, loaded once at startup and then kept
/// in memory by [AppState] for a snappy counter UI. Persistence happens through
/// the granular [Repository] methods below.
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

/// Persistence boundary. Swap [InMemoryRepository] for [FirestoreRepository]
/// in main.dart once Firebase is configured — nothing else changes.
abstract class Repository {
  Future<Snapshot> loadAll();

  Future<int> nextBillNumber();

  Future<void> upsertBrand(Brand brand);
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
