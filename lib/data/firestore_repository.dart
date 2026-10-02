// ---------------------------------------------------------------------------
// FirestoreRepository — the production backend.
//
// This file is NOT imported by default so the app builds and runs on the
// in-memory seed with zero setup. To switch to Firebase:
//   1. In pubspec.yaml, uncomment firebase_core / cloud_firestore (and auth,
//      storage) and run `flutter pub get`.
//   2. Run `flutterfire configure` to generate firebase_options.dart.
//   3. In main.dart: initialize Firebase and inject FirestoreRepository()
//      instead of InMemoryRepository().
//   4. Deploy firestore.rules (in the project root).
//
// Firestore layout (matches the reviewed spec, Part D):
//   brands/{brandId}
//   branches/{branchId}
//   suppliers/{supplierId}
//   products/{productId}
//   stock/{productId}                       (1:1 with product; cross-branch
//                                             rollup — see [Batch] for the
//                                             per-branch source of truth)
//   batches/{batchId}                       (the real, depletable inventory
//                                             lots — branch+product+supplier
//                                             scoped, with expiry)
//   stockLogs/{logId}
//   bills/{billId}  +  bills/{billId}/billItems/{itemId}   (subcollection)
//   purchases/{purchaseId} + purchases/{purchaseId}/purchaseItems/{itemId}
//   customers/{customerId}  +  customers/{customerId}/ledgerEntries/{entryId}
//                                            (customers = sales parties,
//                                             suppliers = purchase parties;
//                                             a "both" party shares one id)
//   staff/{staffId}
//   meta/counters  { bill: <int>, purchase: <int> }
//   meta/settings
//
// Offline: enable Firestore persistence (Settings(persistenceEnabled: true))
// so the counter keeps working without internet, syncing when back online.
// ---------------------------------------------------------------------------

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

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
import '../models/stock.dart';
import '../models/stock_log.dart';
import '../models/supplier.dart';
import 'repository.dart';
import 'stock_commit.dart';

class FirestoreRepository implements Repository {
  final FirebaseFirestore db;
  final FirebaseStorage? _storage;
  FirestoreRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
      : db = firestore ?? FirebaseFirestore.instance,
        _storage = storage;

  FirebaseStorage get storage => _storage ?? FirebaseStorage.instance;

  // ---- purchase bill photos (Firebase Storage; Firestore keeps the ref) ----
  @override
  Future<StoredPhoto> uploadPurchaseBillPhoto(
      String purchaseId, Uint8List bytes, String extension) async {
    final path = purchaseBillPhotoPath(purchaseId, extension);
    final ext = path.split('.').last;
    final ref = storage.ref(path);
    await ref.putData(bytes,
        SettableMetadata(contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}'));
    return StoredPhoto(path, await ref.getDownloadURL());
  }

  @override
  Future<Uint8List?> loadPurchaseBillPhoto(String path) async {
    try {
      return await storage.ref(path).getData(10 * 1024 * 1024);
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return null;
      rethrow;
    }
  }

  @override
  Future<void> deletePurchaseBillPhoto(String path) async {
    try {
      await storage.ref(path).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }

  @override
  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

  /// Catalogue + stock + settings + staff — enough to open the counter
  /// screen. See [Repository.loadCore].
  @override
  Future<CoreSnapshot> loadCore() async {
    debugPrint('[pend] fs: reading brands...');
    final brandsSnap = await db.collection('brands').get();
    debugPrint('[pend] fs: brands = ${brandsSnap.size}');

    debugPrint('[pend] fs: reading branches...');
    final branchesSnap = await db.collection('branches').get();
    debugPrint('[pend] fs: branches = ${branchesSnap.size}');

    debugPrint('[pend] fs: reading suppliers...');
    final suppliersSnap = await db.collection('suppliers').get();
    debugPrint('[pend] fs: suppliers = ${suppliersSnap.size}');

    debugPrint('[pend] fs: reading products...');
    final productsSnap = await db.collection('products').get();
    debugPrint('[pend] fs: products = ${productsSnap.size}');

    debugPrint('[pend] fs: reading stock...');
    final stockSnap = await db.collection('stock').get();
    debugPrint('[pend] fs: stock = ${stockSnap.size}');

    debugPrint('[pend] fs: reading staff...');
    final staffSnap = await db.collection('staff').get();
    debugPrint('[pend] fs: staff = ${staffSnap.size}');

    debugPrint('[pend] fs: reading meta/counters...');
    final counters = await db.doc('meta/counters').get();
    debugPrint('[pend] fs: meta/counters = ${counters.exists ? 1 : 0}');

    debugPrint('[pend] fs: reading meta/settings...');
    final settingsDoc = await db.doc('meta/settings').get();
    debugPrint('[pend] fs: meta/settings = ${settingsDoc.exists ? 1 : 0}');

    final brands =
        brandsSnap.docs.map((d) => Brand.fromMap(d.id, d.data())).toList();
    final branches =
        branchesSnap.docs.map((d) => Branch.fromMap(d.id, d.data())).toList();
    final suppliers = suppliersSnap.docs
        .map((d) => Supplier.fromMap(d.id, d.data()))
        .toList();
    final products =
        productsSnap.docs.map((d) => Product.fromMap(d.id, d.data())).toList();
    final stock = {
      for (final d in stockSnap.docs) d.id: Stock.fromMap(d.id, d.data())
    };
    debugPrint('[pend] fs: core totals — '
        'brands=${brands.length}, branches=${branches.length}, '
        'suppliers=${suppliers.length}, products=${products.length}, '
        'stock=${stock.length}');

    return CoreSnapshot(
      brands: brands,
      branches: branches,
      suppliers: suppliers,
      products: products,
      stock: stock,
      staff: staffSnap.docs.map((d) => Staff.fromMap(d.id, d.data())).toList(),
      settings: settingsDoc.exists
          ? AppSettings.fromMap(settingsDoc.data()!)
          : AppSettings(),
      billCounter: (counters.data()?['bill'] ?? 1000) as int,
    );
  }

  /// Bills (+ items), stock logs, and customers (+ ledgers) — loaded in the
  /// background after [loadCore]. See [Repository.loadHistory].
  @override
  Future<HistorySnapshot> loadHistory() async {
    debugPrint('[pend] fs: reading stockLogs...');
    final logsSnap = await db
        .collection('stockLogs')
        .orderBy('createdAt', descending: true)
        .limit(500)
        .get();
    debugPrint('[pend] fs: stockLogs = ${logsSnap.size}');

    debugPrint('[pend] fs: reading bills...');
    final billsSnap = await db
        .collection('bills')
        .orderBy('createdAt', descending: true)
        .limit(500)
        .get();
    debugPrint('[pend] fs: bills = ${billsSnap.size}');

    debugPrint('[pend] fs: reading customers...');
    final customersSnap = await db.collection('customers').get();
    debugPrint('[pend] fs: customers = ${customersSnap.size}');

    debugPrint('[pend] fs: reading batches...');
    final batchesSnap = await db.collection('batches').get();
    debugPrint('[pend] fs: batches = ${batchesSnap.size}');

    debugPrint('[pend] fs: reading purchases...');
    final purchasesSnap = await db
        .collection('purchases')
        .orderBy('createdAt', descending: true)
        .limit(500)
        .get();
    debugPrint('[pend] fs: purchases = ${purchasesSnap.size}');

    final bills = <Bill>[];
    for (final b in billsSnap.docs) {
      final itemsSnap = await b.reference.collection('billItems').get();
      final items =
          itemsSnap.docs.map((d) => BillItem.fromMap(d.data())).toList();
      bills.add(Bill.fromMap(b.id, b.data(), items));
    }
    final customers = <Customer>[];
    for (final c in customersSnap.docs) {
      final ledgerSnap = await c.reference
          .collection('ledgerEntries')
          .orderBy('createdAt')
          .get();
      final ledger =
          ledgerSnap.docs.map((d) => LedgerEntry.fromMap(d.data())).toList();
      customers.add(Customer.fromMap(c.id, c.data(), ledger));
    }

    final purchases = <Purchase>[];
    for (final p in purchasesSnap.docs) {
      final itemDocs = (await p.reference.collection('purchaseItems').get())
          .docs
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      final items = [for (final d in itemDocs) PurchaseItem.fromMap(d.data())];
      purchases.add(Purchase.fromMap(p.id, p.data(), items));
    }

    final logs =
        logsSnap.docs.map((d) => StockLog.fromMap(d.id, d.data())).toList();
    final batches =
        batchesSnap.docs.map((d) => Batch.fromMap(d.id, d.data())).toList();
    debugPrint('[pend] fs: history totals — '
        'bills=${bills.length}, customers=${customers.length}, '
        'logs=${logs.length}, batches=${batches.length}');

    return HistorySnapshot(
        logs: logs,
        bills: bills,
        customers: customers,
        batches: batches,
        purchases: purchases);
  }

  @override
  Future<int> nextBillNumber() async {
    final ref = db.doc('meta/counters');
    return db.runTransaction<int>((tx) async {
      final snap = await tx.get(ref);
      final current = (snap.data()?['bill'] ?? 1000) as int;
      final next = current + 1;
      tx.set(ref, {'bill': next}, SetOptions(merge: true));
      return next;
    });
  }

  @override
  Future<int> nextPurchaseNumber() async {
    final ref = db.doc('meta/counters');
    return db.runTransaction<int>((tx) async {
      final snap = await tx.get(ref);
      final next = ((snap.data()?['purchase'] ?? 0) as int) + 1;
      tx.set(ref, {'purchase': next}, SetOptions(merge: true));
      return next;
    });
  }

  // ---- draft bills: draftBills/{draftId}, version-checked on every save ----
  @override
  Future<List<DraftBill>> loadDrafts() async {
    final snap = await db.collection('draftBills').get();
    return [for (final d in snap.docs) DraftBill.fromMap(d.id, d.data())];
  }

  @override
  Future<int> nextDraftNumber() async {
    final ref = db.doc('meta/counters');
    return db.runTransaction<int>((tx) async {
      final snap = await tx.get(ref);
      final next = ((snap.data()?['draft'] ?? 1000) as int) + 1;
      tx.set(ref, {'draft': next}, SetOptions(merge: true));
      return next;
    });
  }

  @override
  Future<void> saveDraft(DraftBill draft, {int? expectedVersion}) async {
    final ref = db.collection('draftBills').doc(draft.id);
    await db.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      if (expectedVersion == null) {
        if (snap.exists) throw const DraftConflictException(missing: false);
      } else if (!snap.exists) {
        throw const DraftConflictException(missing: true);
      } else if ((snap.data()?['version'] ?? 1) != expectedVersion) {
        throw const DraftConflictException(missing: false);
      }
      tx.set(ref, draft.toMap());
    });
  }

  @override
  Future<void> deleteDraft(String draftId) =>
      db.collection('draftBills').doc(draftId).delete();

  /// See [Repository.commitStock]. One Firestore transaction: every read
  /// happens first (batches, legacy stock, customers, bills/purchases being
  /// patched), then validation against those fresh values, then all writes.
  /// Firestore retries the transaction if any document it read changes
  /// before it commits, so two counters selling the same last bag cannot
  /// both succeed.
  @override
  Future<void> commitStock(StockCommit c) async {
    await db.runTransaction<void>((tx) async {
      // ---- reads ----
      final batchSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final d in c.batches.values) {
        if (d.create != null) continue;
        batchSnaps[d.batchId] =
            await tx.get(db.collection('batches').doc(d.batchId));
      }
      final legacySnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final pid in c.legacyStock.keys) {
        legacySnaps[pid] = await tx.get(db.collection('stock').doc(pid));
      }
      final customerSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final l in c.ledger) {
        if (customerSnaps.containsKey(l.customerId)) continue;
        customerSnaps[l.customerId] =
            await tx.get(db.collection('customers').doc(l.customerId));
      }
      final billSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final p in c.billPatches) {
        billSnaps[p.id] = await tx.get(db.collection('bills').doc(p.id));
      }
      final purchaseSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final p in c.purchasePatches) {
        purchaseSnaps[p.id] =
            await tx.get(db.collection('purchases').doc(p.id));
      }
      final draftRef = c.finalizedDraftId == null
          ? null
          : db.collection('draftBills').doc(c.finalizedDraftId);
      if (draftRef != null) {
        final draft = await tx.get(draftRef);
        if (!draft.exists) throw const StockCommitException(draftGoneMessage);
        if (c.finalizedDraftVersion != null &&
            (draft.data()?['version'] ?? 1) != c.finalizedDraftVersion) {
          throw const StockCommitException(draftChangedMessage);
        }
      }

      // ---- validate against the fresh values ----
      final batchWrites = <String, Map<String, dynamic>>{};
      for (final d in c.batches.values) {
        final Batch current;
        if (d.create != null) {
          current = Batch.fromMap(d.batchId, {
            ...d.create!.toMap(),
            'bagsReceived': 0,
            'bagsAvailable': 0,
            'looseKgAvailable': 0,
            'bagsSold': 0,
            'looseKgSold': 0,
            'bagsReturned': 0,
            'looseKgReturned': 0,
          });
        } else {
          final snap = batchSnaps[d.batchId]!;
          if (!snap.exists) {
            throw StockCommitException(
                'बॅच सापडली नाही · Batch ${d.batchId} no longer exists');
          }
          current = Batch.fromMap(snap.id, snap.data()!);
        }
        d.applyTo(current, c.at);
        if (current.bagsAvailable < 0 || current.looseKgAvailable < -0.001) {
          throw StockCommitException(
              'अपुरा साठा · Stock changed on another device (batch ${current.batchNo}). Nothing was saved — please retry.');
        }
        batchWrites[d.batchId] = current.toMap();
      }
      c.legacyStock.forEach((pid, d) {
        final m = legacySnaps[pid]!.data() ?? const <String, dynamic>{};
        final bags = ((m['bagsRemaining'] ?? 0) as int) + d.bags;
        final kg = (m['looseKgRemaining'] ?? 0).toDouble() + d.looseKg;
        if (bags < 0 || kg < -0.001) {
          throw const StockCommitException(
              'अपुरा साठा · Stock changed on another device. Nothing was saved — please retry.');
        }
      });
      void checkStatus(StatusPatch p, DocumentSnapshot<Map<String, dynamic>> s,
          String what) {
        final data = s.data();
        if (data == null) {
          throw StockCommitException('$what ${p.id} not found');
        }
        if (BillStatusX.fromId(data['status'] as String?) != p.expected ||
            data['replacedByBillId'] != null ||
            data['replacedByPurchaseId'] != null) {
          throw StockCommitException(
              '$what already changed on another device — nothing was saved');
        }
      }

      for (final p in c.billPatches) {
        checkStatus(p, billSnaps[p.id]!, 'बिल · Bill');
      }
      for (final p in c.purchasePatches) {
        checkStatus(p, purchaseSnaps[p.id]!, 'खरेदी · Purchase');
      }

      // ---- writes ----
      batchWrites.forEach(
          (id, data) => tx.set(db.collection('batches').doc(id), data));
      c.rollupDeltas.forEach((pid, d) {
        tx.set(
            db.collection('stock').doc(pid),
            {
              'bagsRemaining': FieldValue.increment(d.$1),
              'looseKgRemaining': FieldValue.increment(d.$2),
            },
            SetOptions(merge: true));
      });
      for (final l in c.logs) {
        tx.set(db.collection('stockLogs').doc(l.id), l.toMap());
      }
      for (final b in c.newBills) {
        final ref = db.collection('bills').doc(b.id);
        tx.set(ref, b.toMap());
        for (var i = 0; i < b.items.length; i++) {
          tx.set(ref.collection('billItems').doc('$i'), b.items[i].toMap());
        }
      }
      for (final p in c.billPatches) {
        tx.update(db.collection('bills').doc(p.id), {
          'status': p.status.id,
          if (p.replacedById != null) 'replacedByBillId': p.replacedById,
          'statusChangedAt': c.at.toIso8601String(),
        });
      }
      for (final p in c.newPurchases) {
        final ref = db.collection('purchases').doc(p.id);
        tx.set(ref, p.toMap());
        for (var i = 0; i < p.items.length; i++) {
          tx.set(
              ref.collection('purchaseItems').doc(i.toString().padLeft(3, '0')),
              p.items[i].toMap());
        }
      }
      for (final p in c.purchasePatches) {
        tx.update(db.collection('purchases').doc(p.id), {
          'status': p.status.id,
          if (p.replacedById != null) 'replacedByPurchaseId': p.replacedById,
          'statusChangedAt': c.at.toIso8601String(),
        });
      }
      final outstanding = <String, double>{
        for (final e in customerSnaps.entries)
          e.key: (e.value.data()?['outstandingBalance'] ?? 0).toDouble(),
      };
      for (final l in c.ledger) {
        final ref = db.collection('customers').doc(l.customerId);
        tx.set(ref.collection('ledgerEntries').doc(), l.entry.toMap());
        final next = outstanding[l.customerId]! + l.outstandingDelta;
        outstanding[l.customerId] = next < 0 ? 0 : next;
      }
      outstanding.forEach((id, v) => tx.update(
          db.collection('customers').doc(id), {'outstandingBalance': v}));
      if (draftRef != null) tx.delete(draftRef);
    });
  }

  @override
  Future<void> upsertBrand(Brand brand) => db
      .collection('brands')
      .doc(brand.id)
      .set(brand.toMap(), SetOptions(merge: true));

  @override
  Future<void> deleteBrand(String brandId,
      {List<String> productIds = const []}) async {
    final batch = db.batch();
    for (final id in productIds) {
      batch.delete(db.collection('products').doc(id));
      batch.delete(db.collection('stock').doc(id));
    }
    batch.delete(db.collection('brands').doc(brandId));
    await batch.commit();
  }

  @override
  Future<String> uploadBrandPhoto(
      String brandId, Uint8List bytes, String extension) async {
    final ext = extension.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    final safe =
        const {'jpg', 'jpeg', 'png', 'webp'}.contains(ext) ? ext : 'jpg';
    final ref = storage.ref(
        'brands/$brandId/logo_${DateTime.now().millisecondsSinceEpoch}.$safe');
    await ref.putData(
        bytes,
        SettableMetadata(
            contentType: 'image/${safe == 'jpg' ? 'jpeg' : safe}'));
    return ref.getDownloadURL();
  }

  @override
  Future<void> deleteBrandPhoto(String url) async {
    try {
      await storage.refFromURL(url).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }

  @override
  Future<void> upsertStaff(Staff staff) => db
      .collection('staff')
      .doc(staff.id)
      .set(staff.toMap(), SetOptions(merge: true));

  @override
  Future<void> upsertProduct(Product product, {Stock? initialStock}) async {
    await db
        .collection('products')
        .doc(product.id)
        .set(product.toMap(), SetOptions(merge: true));
    if (initialStock != null) {
      await db.collection('stock').doc(product.id).set(initialStock.toMap());
    }
  }

  @override
  Future<void> deleteProduct(String productId) async {
    await db.collection('products').doc(productId).delete();
    await db.collection('stock').doc(productId).delete();
  }

  @override
  Future<void> upsertBranch(Branch branch) => db
      .collection('branches')
      .doc(branch.id)
      .set(branch.toMap(), SetOptions(merge: true));

  @override
  Future<void> upsertSupplier(Supplier supplier) => db
      .collection('suppliers')
      .doc(supplier.id)
      .set(supplier.toMap(), SetOptions(merge: true));

  @override
  Future<void> deleteSupplier(String supplierId) =>
      db.collection('suppliers').doc(supplierId).delete();

  @override
  Future<void> upsertBatch(Batch batch) => db
      .collection('batches')
      .doc(batch.id)
      .set(batch.toMap(), SetOptions(merge: true));

  @override
  Future<void> setStock(Stock stock) =>
      db.collection('stock').doc(stock.productId).set(stock.toMap());

  @override
  Future<void> addStockLog(StockLog log) =>
      db.collection('stockLogs').doc(log.id).set(log.toMap());

  @override
  Future<void> upsertCustomer(Customer customer) => db
      .collection('customers')
      .doc(customer.id)
      .set(customer.toMap(), SetOptions(merge: true));

  @override
  Future<void> addLedgerEntry(
      String customerId, LedgerEntry entry, double newOutstanding) async {
    final custRef = db.collection('customers').doc(customerId);
    final batch = db.batch();
    batch.set(custRef.collection('ledgerEntries').doc(), entry.toMap());
    batch.update(custRef, {'outstandingBalance': newOutstanding});
    await batch.commit();
  }

  @override
  Future<void> saveSettings(AppSettings settings) =>
      db.doc('meta/settings').set(settings.toMap(), SetOptions(merge: true));
}
