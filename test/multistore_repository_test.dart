// FirestoreRepository store scoping: every read is limited to, and every
// write stamped with, the current store; no store context = no data.
import 'package:flutter_test/flutter_test.dart';

import 'package:pend_point/data/firestore_repository.dart';
import 'package:pend_point/data/stock_commit.dart';
import 'package:pend_point/models/app_settings.dart';
import 'package:pend_point/models/bill.dart';
import 'package:pend_point/models/customer.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/models/product.dart';
import 'package:pend_point/models/stock_log.dart';
import 'package:pend_point/models/store.dart';

import 'multistore_support.dart';

void main() {
  test('Store A loads only Store A data (core + history + drafts)', () async {
    final db = await twoStores();
    final repo = repoFor(db)..useContext(ctxFor(storeA));
    final core = await repo.loadCore();
    expect(core.products.map((p) => p.id), ['pA']);
    expect(core.brands.map((b) => b.id), ['bA']);
    expect(core.branches.map((b) => b.id), ['brA']);
    expect(core.suppliers.map((s) => s.id), ['supA']);
    expect(core.stock.keys, ['pA']);
    expect(
        core.staff.map((s) => s.id).toSet(), {'adminA', 'staffA', 'disabledA'});
    expect(core.settings.shop, 'Shop $storeA');

    final h = await repo.loadHistory();
    expect(h.bills.map((b) => b.id), ['BILLA']);
    expect(h.bills.single.items.single.productId, 'pA');
    expect(h.customers.map((c) => c.id), ['cA']);
    expect(h.customers.single.outstanding, 100);
    expect(h.customers.single.ledger, hasLength(1));
    expect(h.batches.map((b) => b.id), ['btA']);
    expect(h.purchases.map((p) => p.id), ['PURA']);
    expect(h.logs.map((l) => l.id), ['logA']);
    expect((await repo.loadDrafts()).map((d) => d.id), ['DRAFTA']);

    // Store B sees the mirror image.
    repo.useContext(ctxFor(storeB, uid: 'staffB'));
    expect((await repo.loadCore()).products.map((p) => p.id), ['pB']);
    expect((await repo.loadHistory()).bills.map((b) => b.id), ['BILLB']);
  });

  test('no store context: StoreContextException, never "all stores"', () async {
    final db = await twoStores();
    final repo = repoFor(db);
    await expectLater(repo.loadCore(), throwsA(isA<StoreContextException>()));
    await expectLater(
        repo.loadHistory(), throwsA(isA<StoreContextException>()));
    await expectLater(repo.loadDrafts(), throwsA(isA<StoreContextException>()));
    await expectLater(
        repo.nextBillNumber(), throwsA(isA<StoreContextException>()));
    expect(() => repo.upsertProduct(Product.fromMap('pX', const {})),
        throwsA(isA<StoreContextException>()));
    // A super admin on the dashboard (no store opened) is no different.
    repo.useContext(const StoreContext(uid: 'super1', role: Roles.superAdmin));
    await expectLater(repo.loadCore(), throwsA(isA<StoreContextException>()));
  });

  test('writes are stamped with the current store (never from the caller)',
      () async {
    final db = await twoStores();
    final repo = repoFor(db)..useContext(ctxFor(storeA));
    await repo.upsertProduct(Product.fromMap('pNew', const {'name': 'New'}));
    expect((await db.doc('products/pNew').get()).get('storeId'), storeA);
    await repo.upsertCustomer(Customer(id: 'cNew', name: 'New customer'));
    expect((await db.doc('customers/cNew').get()).get('storeId'), storeA);
    await repo.addLedgerEntry('cA',
        LedgerEntry(type: 'repayment', amount: 10, at: DateTime.now()), 90);
    final entries = await db.collection('customers/cA/ledgerEntries').get();
    expect(entries.docs.every((d) => d.get('storeId') == storeA), isTrue);
    await repo.addStockLog(StockLog(
        id: 'lNew',
        productId: 'pA',
        type: StockLogType.adjustment,
        bagsDelta: 1,
        looseKgDelta: 0,
        at: DateTime.now()));
    expect((await db.doc('stockLogs/lNew').get()).get('storeId'), storeA);
  });

  test('bill / purchase / draft counters run per store', () async {
    final db = await twoStores();
    final repo = repoFor(db)..useContext(ctxFor(storeA));
    expect(await repo.nextBillNumber(), 1001);
    expect(await repo.nextBillNumber(), 1002);
    repo.useContext(ctxFor(storeB, uid: 'staffB'));
    expect(await repo.nextBillNumber(), 1001, reason: 'B has its own numbers');
    expect(await repo.nextDraftNumber(), 1001);
    expect(
        (await db.doc('stores/$storeA/meta/counters').get()).get('bill'), 1002);
  });

  test('a sale commit writes every document with the store', () async {
    final db = await twoStores();
    final repo = repoFor(db)..useContext(ctxFor(storeA));
    final now = DateTime.now();
    final c = StockCommit(now);
    c.batch('btA', 'pA')
      ..bagsAvailable = -2
      ..bagsSold = 2;
    c.newBills.add(Bill(
        id: 'STR-A_BILL1001',
        billNumber: 1001,
        customerId: 'cA',
        items: const [
          BillItem(
              productId: 'pA',
              saleType: SaleType.bag,
              qty: 2,
              catalogRate: 1000,
              rate: 1000,
              lineTotal: 2000,
              batchId: 'btA')
        ],
        subtotal: 2000,
        discountTotal: 0,
        total: 2000,
        payments: const [Payment(PayMode.credit, 2000)],
        at: now));
    c.logs.add(StockLog(
        id: 'sale1',
        productId: 'pA',
        type: StockLogType.sale,
        bagsDelta: -2,
        looseKgDelta: 0,
        at: now));
    c.ledger.add(LedgerChange(
        'cA', LedgerEntry(type: 'credit-sale', amount: 2000, at: now), 2000));
    c.audits.add(AuditEntry(
        storeId: storeA,
        userId: 'staffA',
        role: 'staff',
        action: 'BILL_FINALIZED',
        entityType: 'BILL',
        entityId: 'STR-A_BILL1001',
        at: now));
    await repo.commitStock(c);

    expect((await db.doc('bills/STR-A_BILL1001').get()).get('storeId'), storeA);
    expect(
        (await db.doc('bills/STR-A_BILL1001/billItems/0').get()).get('storeId'),
        storeA);
    final batch = await db.doc('batches/btA').get();
    expect(batch.get('storeId'), storeA);
    expect(batch.get('bagsAvailable'), 8);
    expect((await db.doc('stock/pA').get()).get('storeId'), storeA);
    expect((await db.doc('stockLogs/sale1').get()).get('storeId'), storeA);
    expect(
        (await db.doc('customers/cA').get()).get('outstandingBalance'), 2100);
    final audit = await db.collection('auditLogs').get();
    expect(audit.docs.single.get('storeId'), storeA);
    // Store B untouched.
    expect((await db.doc('batches/btB').get()).get('bagsAvailable'), 10);
    expect((await db.doc('customers/cB').get()).get('outstandingBalance'), 900);
  });

  test('a Store A commit touching Store B data is refused; nothing written',
      () async {
    final db = await twoStores();
    final repo = repoFor(db)..useContext(ctxFor(storeA));
    final c = StockCommit(DateTime.now());
    c.batch('btB', 'pB').bagsAvailable = -1; // B's batch, by id
    c.logs.add(StockLog(
        id: 'evil',
        productId: 'pB',
        type: StockLogType.sale,
        bagsDelta: -1,
        looseKgDelta: 0,
        at: DateTime.now()));
    await expectLater(
        repo.commitStock(c), throwsA(isA<StockCommitException>()));
    expect((await db.doc('batches/btB').get()).get('bagsAvailable'), 10);
    expect((await db.doc('stockLogs/evil').get()).exists, isFalse);

    final c2 = StockCommit(DateTime.now());
    c2.ledger.add(LedgerChange('cB',
        LedgerEntry(type: 'repayment', amount: 900, at: DateTime.now()), -900));
    await expectLater(
        repo.commitStock(c2), throwsA(isA<StockCommitException>()));
    expect((await db.doc('customers/cB').get()).get('outstandingBalance'), 900);
  });

  test('deletes only within the store, even knowing the other id', () async {
    final db = await twoStores();
    final repo = repoFor(db)
      ..useContext(ctxFor(storeA, uid: 'adminA', role: Roles.storeAdmin));
    await expectLater(
        repo.deleteProduct('pB'), throwsA(isA<StoreContextException>()));
    expect((await db.doc('products/pB').get()).exists, isTrue);
    await expectLater(
        repo.deleteDraft('DRAFTB'), throwsA(isA<StoreContextException>()));
    expect((await db.doc('draftBills/DRAFTB').get()).exists, isTrue);
    await expectLater(
        repo.deleteBrand('bB'), throwsA(isA<StoreContextException>()));
    await repo.deleteDraft('DRAFTA');
    expect((await db.doc('draftBills/DRAFTA').get()).exists, isFalse);
  });

  test('stores: code is unique; users listed per store', () async {
    final db = await twoStores();
    final repo = repoFor(db)
      ..useContext(const StoreContext(uid: 'super1', role: Roles.superAdmin));
    final now = DateTime.now();
    await expectLater(
        repo.createStore(
            Store(id: storeA, storeName: 'dup', createdAt: now, updatedAt: now),
            AppSettings()..shop = 'dup'),
        throwsA(isA<StoreExistsException>()));
    await repo.createStore(
        Store(
            id: 'STR003',
            storeName: 'Kolhapur',
            createdAt: now,
            updatedAt: now),
        AppSettings()..shop = 'Kolhapur');
    expect(
        (await db.doc('stores/STR003/meta/counters').get()).get('bill'), 1000);
    expect((await db.doc('stores/STR003/meta/settings').get()).get('shop'),
        'Kolhapur');
    expect((await repo.listStores()).map((s) => s.id), contains('STR003'));
    expect((await repo.listUsers(storeId: storeB)).map((u) => u.id).toSet(),
        {'adminB', 'staffB'});
  });
}
