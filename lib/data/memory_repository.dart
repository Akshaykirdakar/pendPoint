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
import '../models/stock.dart';
import '../models/stock_log.dart';
import '../models/staff.dart';
import '../models/supplier.dart';
import 'repository.dart';
import 'stock_commit.dart';
import 'seed_data.dart';

/// Default repository — keeps everything in memory, seeded with a sample shop,
/// so the app builds and runs with zero backend setup. All mutations are no-ops
/// here because [AppState] already holds the working copy; this just satisfies
/// the [Repository] contract. Swap for [FirestoreRepository] to persist.
class InMemoryRepository implements Repository {
  int _counter = 1000;
  int _purchaseCounter = 0;

  // Set by loadCore() and consumed by loadHistory() so a single bootstrap
  // cycle's two staged reads come from the same seed instance. A *new*
  // bootstrap cycle (e.g. "Reset sample data") calls loadCore() again, which
  // regenerates a fresh seed — this is not a cross-cycle cache.
  Snapshot? _pendingSeed;

  @override
  Future<CoreSnapshot> loadCore() async {
    final snap = buildSeed();
    _pendingSeed = snap;
    _counter = snap.billCounter;
    return CoreSnapshot(
      brands: snap.brands,
      branches: snap.branches,
      suppliers: snap.suppliers,
      products: snap.products,
      stock: snap.stock,
      staff: snap.staff,
      settings: snap.settings,
      billCounter: snap.billCounter,
    );
  }

  @override
  Future<HistorySnapshot> loadHistory() async {
    final snap = _pendingSeed ?? buildSeed();
    _pendingSeed = null;
    return HistorySnapshot(
      logs: snap.logs,
      bills: snap.bills,
      customers: snap.customers,
      batches: snap.batches,
      purchases: const [],
    );
  }

  @override
  Future<int> nextBillNumber() async => ++_counter;
  @override
  Future<int> nextPurchaseNumber() async => ++_purchaseCounter;

  int _draftCounter = 1000;

  /// Saved drafts, kept like a Firestore collection would (with versions)
  /// so draft conflicts behave the same here as on a real backend.
  final Map<String, DraftBill> drafts = {};

  @override
  Future<List<DraftBill>> loadDrafts() async => drafts.values.toList();

  @override
  Future<int> nextDraftNumber() async => ++_draftCounter;

  @override
  Future<void> saveDraft(DraftBill draft, {int? expectedVersion}) async {
    final stored = drafts[draft.id];
    if (expectedVersion == null) {
      if (stored != null) throw const DraftConflictException(missing: false);
    } else if (stored == null) {
      throw const DraftConflictException(missing: true);
    } else if (stored.version != expectedVersion) {
      throw const DraftConflictException(missing: false);
    }
    drafts[draft.id] = draft;
  }

  @override
  Future<void> deleteDraft(String draftId) async => drafts.remove(draftId);

  /// [AppState] validates every commit against its working copy before
  /// calling this, and there is no other device to race with, so the only
  /// thing kept here is the draft a sale finalizes.
  @override
  Future<void> commitStock(StockCommit commit) async {
    final draftId = commit.finalizedDraftId;
    if (draftId == null) return;
    final stored = drafts[draftId];
    if (stored == null) throw const StockCommitException(draftGoneMessage);
    if (commit.finalizedDraftVersion != null &&
        stored.version != commit.finalizedDraftVersion) {
      throw const StockCommitException(draftChangedMessage);
    }
    drafts.remove(draftId);
  }

  @override
  Future<void> upsertBrand(Brand brand) async {}
  @override
  Future<void> deleteBrand(String brandId,
      {List<String> productIds = const []}) async {}

  @override
  Future<String> uploadBrandPhoto(
      String brandId, Uint8List bytes, String extension) async {
    final path =
        'brands/$brandId/logo_${DateTime.now().microsecondsSinceEpoch}.$extension';
    photos[path] = bytes;
    return 'memory://$path';
  }

  @override
  Future<void> deleteBrandPhoto(String url) async =>
      photos.remove(url.replaceFirst('memory://', ''));
  @override
  Future<void> upsertStaff(Staff staff) async {}
  @override
  Future<void> upsertProduct(Product product, {Stock? initialStock}) async {}
  @override
  Future<void> deleteProduct(String productId) async {}
  @override
  Future<void> upsertBranch(Branch branch) async {}
  @override
  Future<void> upsertSupplier(Supplier supplier) async {}
  @override
  Future<void> deleteSupplier(String supplierId) async {}
  @override
  Future<void> upsertBatch(Batch batch) async {}
  @override
  Future<void> setStock(Stock stock) async {}
  @override
  Future<void> addStockLog(StockLog log) async {}
  @override
  Future<void> upsertCustomer(Customer customer) async {}
  @override
  Future<void> addLedgerEntry(
      String customerId, LedgerEntry entry, double newOutstanding) async {}
  @override
  Future<void> saveSettings(AppSettings settings) async {}

  @override
  String? get currentUserId => null;

  /// Bill photos kept in memory, keyed by storage-style path.
  final Map<String, Uint8List> photos = {};

  @override
  Future<StoredPhoto> uploadPurchaseBillPhoto(
      String purchaseId, Uint8List bytes, String extension) async {
    final path = purchaseBillPhotoPath(purchaseId, extension);
    photos[path] = bytes;
    return StoredPhoto(path, 'memory://$path');
  }

  @override
  Future<Uint8List?> loadPurchaseBillPhoto(String path) async => photos[path];

  @override
  Future<void> deletePurchaseBillPhoto(String path) async =>
      photos.remove(path);
}
