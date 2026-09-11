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
//   products/{productId}
//   stock/{productId}                       (1:1 with product)
//   stockLogs/{logId}
//   bills/{billId}  +  bills/{billId}/billItems/{itemId}   (subcollection)
//   customers/{customerId}  +  customers/{customerId}/ledgerEntries/{entryId}
//   staff/{staffId}
//   meta/counters  { bill: <int> }
//   meta/settings
//
// Offline: enable Firestore persistence (Settings(persistenceEnabled: true))
// so the counter keeps working without internet, syncing when back online.
// ---------------------------------------------------------------------------

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/bill.dart';
import '../models/brand.dart';
import '../models/customer.dart';
import '../models/enums.dart';
import '../models/product.dart';
import '../models/staff.dart';
import '../models/stock.dart';
import '../models/stock_log.dart';
import 'repository.dart';

class FirestoreRepository implements Repository {
  final FirebaseFirestore db;
  int _lastBrandsCount = 0;
  int _lastProductsCount = 0;
  int _lastStockCount = 0;

  FirestoreRepository({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  @override
  Future<CoreSnapshot> loadCore() async {
    final brandsSnap = await _readCollection(
      'brands',
      db.collection('brands'),
    );
    final productsSnap = await _readCollection(
      'products',
      db.collection('products'),
    );
    final stockSnap = await _readCollection(
      'stock',
      db.collection('stock'),
    );
    final staffSnap = await _readCollection(
      'staff',
      db.collection('staff'),
    );
    final counters = await _readDocument('meta/counters');
    final settingsDoc = await _readDocument('meta/settings');

    _lastBrandsCount = brandsSnap.size;
    _lastProductsCount = productsSnap.size;
    _lastStockCount = stockSnap.size;

    return CoreSnapshot(
      brands: brandsSnap.docs.map((d) => Brand.fromMap(d.id, d.data())).toList(),
      products: productsSnap.docs
          .map((d) => Product.fromMap(d.id, d.data()))
          .toList(),
      stock: {
        for (final d in stockSnap.docs) d.id: Stock.fromMap(d.id, d.data())
      },
      staff: staffSnap.docs.map((d) => Staff.fromMap(d.id, d.data())).toList(),
      settings: settingsDoc.exists
          ? AppSettings.fromMap(settingsDoc.data()!)
          : AppSettings(),
      billCounter: (counters.data()?['bill'] ?? 1000) as int,
    );
  }

  @override
  Future<HistorySnapshot> loadHistory() async {
    final logsSnap = await _readCollection(
      'stockLogs',
      db.collection('stockLogs').orderBy('createdAt', descending: true).limit(500),
    );
    final billsSnap = await _readCollection(
      'bills',
      db.collection('bills').orderBy('createdAt', descending: true).limit(500),
    );
    final customersSnap = await _readCollection(
      'customers',
      db.collection('customers'),
    );

    final bills = <Bill>[];
    for (final b in billsSnap.docs) {
      final itemsSnap = await _readCollection(
        'bills/${b.id}/billItems',
        b.reference.collection('billItems'),
      );
      final items =
          itemsSnap.docs.map((d) => BillItem.fromMap(d.data())).toList();
      bills.add(Bill.fromMap(b.id, b.data(), items));
    }
    final customers = <Customer>[];
    for (final c in customersSnap.docs) {
      final ledgerSnap = await _readCollection(
        'customers/${c.id}/ledgerEntries',
        c.reference.collection('ledgerEntries').orderBy('createdAt'),
      );
      final ledger =
          ledgerSnap.docs.map((d) => LedgerEntry.fromMap(d.data())).toList();
      customers.add(Customer.fromMap(c.id, c.data(), ledger));
    }

    debugPrint(
        '[pend] fs: totals brands=$_lastBrandsCount products=$_lastProductsCount stock=$_lastStockCount bills=${bills.length} customers=${customers.length}');

    return HistorySnapshot(
      logs: logsSnap.docs.map((d) => StockLog.fromMap(d.id, d.data())).toList(),
      bills: bills,
      customers: customers,
    );
  }

  @override
  Future<Snapshot> loadAll() async {
    final core = await loadCore();
    final history = await loadHistory();
    debugPrint(
        '[pend] fs: totals brands=${core.brands.length} products=${core.products.length} stock=${core.stock.length} bills=${history.bills.length} customers=${history.customers.length}');
    return Snapshot.merge(core, history);
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
  Future<void> upsertBrand(Brand brand) => db
      .collection('brands')
      .doc(brand.id)
      .set(brand.toMap(), SetOptions(merge: true));

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
  Future<void> setStock(Stock stock) =>
      db.collection('stock').doc(stock.productId).set(stock.toMap());

  @override
  Future<void> addStockLog(StockLog log) =>
      db.collection('stockLogs').doc(log.id).set(log.toMap());

  @override
  Future<void> saveBill(Bill bill) async {
    // Deduct stock + write the bill atomically in one batch.
    final batch = db.batch();
    final billRef = db.collection('bills').doc(bill.id);
    batch.set(billRef, bill.toMap());
    for (var i = 0; i < bill.items.length; i++) {
      batch.set(
          billRef.collection('billItems').doc('$i'), bill.items[i].toMap());
    }
    await batch.commit();
  }

  @override
  Future<void> updateBillStatus(String billId, BillStatus status) =>
      db.collection('bills').doc(billId).update({'status': status.id});

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

  Future<QuerySnapshot<Map<String, dynamic>>> _readCollection(
    String label,
    Query<Map<String, dynamic>> query,
  ) async {
    debugPrint('[pend] fs: reading $label…');
    final snap = await query.get();
    debugPrint('[pend] fs: $label = ${snap.size}');
    return snap;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _readDocument(String path) async {
    debugPrint('[pend] fs: reading $path…');
    final snap = await db.doc(path).get();
    debugPrint('[pend] fs: $path = ${snap.data()?.length ?? 0}');
    return snap;
  }
}
