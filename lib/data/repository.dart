import 'platform_repository.dart';
import 'dart:typed_data';

import '../models/app_settings.dart';
import '../models/batch.dart';
import '../models/bill.dart';
import '../models/branch.dart';
import '../models/brand.dart';
import '../models/customer.dart';
import '../models/draft_bill.dart';
import '../models/enums.dart';
import '../models/product.dart';
import '../models/purchase.dart';
import '../models/staff.dart';
import '../models/store.dart';
import '../models/stock.dart';
import '../models/stock_log.dart';
import '../models/supplier.dart';
import 'stock_commit.dart';

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
  final List<Purchase> purchases;

  HistorySnapshot({
    required this.logs,
    required this.bills,
    required this.customers,
    required this.batches,
    this.purchases = const [],
  });
}

/// Persistence boundary. Swap [InMemoryRepository] for [FirestoreRepository]
/// in main.dart once Firebase is configured — nothing else changes.
abstract class Repository {
  /// The signed-in staff member for an authenticated repository. Local/demo
  /// repositories deliberately have no user, keeping their UI Firebase-free.
  String? get currentUserId => null;

  // ---- multi-store ----
  //
  // Every store-owned read is limited to, and every store-owned write is
  // stamped with, the store in [context] — screens never pass a store id.
  // Without a store context those operations throw StoreContextException
  // rather than touch other stores' data.

  /// Who is signed in and which store the data belongs to.
  StoreContext? get context;

  /// Sets the store context (after login, or when a super admin opens a
  /// store); null on sign-out.
  void useContext(StoreContext? context);

  /// Signs the user out of the backend (nothing to do for local data).
  Future<void> signOut();

  /// The signed-in user's own staff/{uid} record (null: none exists).
  Future<Staff?> loadMyProfile();

  /// stores/{storeId}, or null.
  Future<Store?> loadStore(String storeId);

  // ---- super admin (global) ----
  Future<List<Store>> listStores();

  /// Creates a new store with its own default settings and counters.
  /// Fails if the store code is already taken.
  Future<void> createStore(Store store, AppSettings settings);
  Future<void> updateStore(Store store);

  /// Staff of [storeId] (all users when null — super admin only).
  Future<List<Staff>> listUsers({String? storeId});

  /// Creates or updates a user's staff record (their role and store).
  Future<void> saveUser(Staff user);

  /// Creates a Firebase sign-in for a new store user without signing the
  /// current (super admin) user out; returns the new uid.
  Future<String> createLoginAccount(String email, String password);

  /// Super Admin platform data (stores live, settings, plans, payments,
  /// notifications, announcements).
  PlatformRepository get platform;

  /// Changes the signed-in user's own password after confirming the
  /// current one (Firebase asks for a recent sign-in).
  Future<void> changeOwnPassword(String current, String next);

  /// Sets another user's password. Done by the `setUserPassword` Cloud
  /// Function, which checks the caller may do it (super admin: any store
  /// user; store admin: staff of their own store) and signs that user out
  /// of their other devices.
  Future<void> setUserPassword(String uid, String password);

  /// Appends to the store-aware audit trail.
  Future<void> addAudit(AuditEntry entry);

  /// Recent audit entries — one store's, or all stores' when null.
  Future<List<AuditEntry>> loadAudit({String? storeId, int limit = 200});

  /// Catalogue + stock + settings + staff — everything needed to open the
  /// counter screen. Load this first and show the UI as soon as it resolves.
  Future<CoreSnapshot> loadCore();

  /// Bills, stock logs, and customer ledgers. Load this in the background
  /// after [loadCore] — the counter UI does not wait on it.
  Future<HistorySnapshot> loadHistory();

  Future<int> nextBillNumber();
  Future<int> nextPurchaseNumber();

  // ---- draft bills (unfinished sales; no stock/payment/khata effect) ----

  /// Every saved draft bill (any order).
  Future<List<DraftBill>> loadDrafts();

  /// The next draft number ("D…") — a separate counter from bill numbers,
  /// so drafts never use up a real bill number.
  Future<int> nextDraftNumber();

  /// Writes [draft]. With [expectedVersion] null the draft must be new;
  /// otherwise the stored copy must still be at [expectedVersion] (and
  /// [draft] carries expectedVersion + 1). Throws [DraftConflictException]
  /// — writing nothing — when the stored copy is missing or newer.
  Future<void> saveDraft(DraftBill draft, {int? expectedVersion});

  /// Deletes a draft (no stock, payment or khata is touched).
  Future<void> deleteDraft(String draftId);

  /// Commits one stock-affecting business operation (sale, void, bill edit,
  /// purchase, purchase void/edit, stock-in, return) atomically: batch
  /// quantity deltas are applied to the CURRENT stored values (never a
  /// stale local copy), no batch may go below zero, bill/purchase status
  /// patches re-check the expected status, and every document in the
  /// commit is written all-or-nothing. Throws [StockCommitException] when
  /// rejected; nothing is written in that case.
  Future<void> commitStock(StockCommit commit);

  Future<void> upsertBrand(Brand brand);

  /// Deletes brand [brandId] together with [productIds] (its products —
  /// the caller has checked they hold no stock and have no history) in ONE
  /// atomic write, so a product is never left without its brand.
  Future<void> deleteBrand(String brandId,
      {List<String> productIds = const []});

  /// Uploads an (optional) brand logo/photo to `brands/{brandId}/…` in
  /// Storage and returns its download URL.
  Future<String> uploadBrandPhoto(
      String brandId, Uint8List bytes, String extension);

  /// Removes a brand photo by its download URL (missing file is fine).
  Future<void> deleteBrandPhoto(String url);
  Future<void> upsertStaff(Staff staff);
  Future<void> upsertProduct(Product product, {Stock? initialStock});
  Future<void> deleteProduct(String productId);

  Future<void> upsertBranch(Branch branch);
  Future<void> upsertSupplier(Supplier supplier);
  Future<void> deleteSupplier(String supplierId);
  Future<void> upsertBatch(Batch batch);

  Future<void> setStock(Stock stock);
  Future<void> addStockLog(StockLog log);

  Future<void> upsertCustomer(Customer customer);
  Future<void> addLedgerEntry(
      String customerId, LedgerEntry entry, double newOutstanding);

  Future<void> saveSettings(AppSettings settings);

  /// Uploads the photo of a supplier's paper bill for purchase
  /// [purchaseId] (to `purchase-bills/{purchaseId}/…` in Storage) and
  /// returns where it was stored. Purchases work without a photo.
  Future<StoredPhoto> uploadPurchaseBillPhoto(
      String purchaseId, Uint8List bytes, String extension);

  /// Reads a previously uploaded bill photo back (null if it is gone).
  Future<Uint8List?> loadPurchaseBillPhoto(String path);

  /// Deletes an uploaded bill photo — only used to clean up after a
  /// purchase save that failed; saved revisions keep their photos.
  Future<void> deletePurchaseBillPhoto(String path);
}

/// Where an uploaded photo was stored: [path] for the app, [url] for display.
class StoredPhoto {
  final String path;
  final String url;
  const StoredPhoto(this.path, this.url);
}

/// `purchase-bills/{purchaseId}/bill_<time>.<ext>` — one folder per
/// purchase; a new file name each upload so a replaced photo never
/// overwrites the one an older revision still points at.
String purchaseBillPhotoPath(String purchaseId, String extension) {
  final ext = extension.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  final safe = const {'jpg', 'jpeg', 'png', 'webp'}.contains(ext) ? ext : 'jpg';
  return 'purchase-bills/$purchaseId/bill_${DateTime.now().millisecondsSinceEpoch}.$safe';
}
