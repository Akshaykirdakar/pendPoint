import '../models/app_settings.dart';
import '../models/bill.dart';
import '../models/brand.dart';
import '../models/customer.dart';
import '../models/enums.dart';
import '../models/product.dart';
import '../models/stock.dart';
import '../models/stock_log.dart';
import 'repository.dart';
import 'seed_data.dart';

/// Default repository — keeps everything in memory, seeded with a sample shop,
/// so the app builds and runs with zero backend setup. All mutations are no-ops
/// here because [AppState] already holds the working copy; this just satisfies
/// the [Repository] contract. Swap for [FirestoreRepository] to persist.
class InMemoryRepository implements Repository {
  int _counter = 1000;

  @override
  Future<Snapshot> loadAll() async {
    final snap = buildSeed();
    _counter = snap.billCounter;
    return snap;
  }

  @override
  Future<int> nextBillNumber() async => ++_counter;

  @override
  Future<void> upsertBrand(Brand brand) async {}
  @override
  Future<void> upsertProduct(Product product, {Stock? initialStock}) async {}
  @override
  Future<void> deleteProduct(String productId) async {}
  @override
  Future<void> setStock(Stock stock) async {}
  @override
  Future<void> addStockLog(StockLog log) async {}
  @override
  Future<void> saveBill(Bill bill) async {}
  @override
  Future<void> updateBillStatus(String billId, BillStatus status) async {}
  @override
  Future<void> upsertCustomer(Customer customer) async {}
  @override
  Future<void> addLedgerEntry(
      String customerId, LedgerEntry entry, double newOutstanding) async {}
  @override
  Future<void> saveSettings(AppSettings settings) async {}
}
