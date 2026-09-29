// Purchase entry: one/many lines, totals + other charges, stock/batch
// update, purchase rate vs selling price, void/edit reversal, and that
// everything goes through the repository commit (transaction) layer.
import 'package:flutter_test/flutter_test.dart';

import 'package:pend_point/models/enums.dart';
import 'package:pend_point/state/purchase_draft.dart';

import 'test_support.dart';

void main() {
  test(
      'Purchase with one item creates a batch, updates stock and keeps the purchase rate',
      () async {
    final repo = RecordingRepository();
    final app = await bootedApp(repo);
    final pid = await freshProduct(app, sellPrice: 1450);
    final supplier = app.suppliers.first;

    final res = await app.savePurchase(
      supplierId: supplier.id,
      supplierBillNo: 'INV-77',
      purchaseDate: DateTime(2026, 9, 20),
      lines: [
        PurchaseLineInput(
            productId: pid,
            bags: 10,
            rate: 1200,
            batchNo: 'P-1',
            expiry: inDays(90)),
        const PurchaseLineInput(), // the always-present empty row
      ],
    );
    expect(res.ok, isTrue, reason: res.error);
    final p = res.purchase!;
    expect(p.items, hasLength(1));
    expect(p.supplierId, supplier.id);
    expect(p.supplierName, supplier.name);
    expect(p.supplierBillNo, 'INV-77');
    expect(p.purchaseDate, DateTime(2026, 9, 20));
    expect(p.subtotal, 12000);
    expect(p.otherCharges, 0);
    expect(p.total, 12000);

    final batch = app.batchOf(p.items.single.batchId)!;
    expect(batch.batchNo, 'P-1');
    expect(batch.bagsAvailable, 10);
    expect(batch.unitCost, 1200); // purchase rate on the batch
    expect(batch.supplierId, supplier.id);
    expect(app.stockOf(pid).bags, 10);

    // Selling price stays the product's own — never the purchase rate.
    expect(app.productOf(pid)!.fullBagPrice, 1450);
    expect(p.items.single.rate, 1200);
    expect(p.items.single.sellingRateAtPurchase, 1450);

    // Persisted through the repository in one commit.
    final commit = repo.commits.last;
    expect(commit.newPurchases.single.id, p.id);
    expect(commit.batches.values.single.create, isNotNull);
    expect(commit.batches.values.single.bagsAvailable, 10);
    expect(commit.logs.single.type, StockLogType.purchase);
    expect(app.purchases.first.id, p.id);
  });

  test('Purchase with multiple items, other charges and grand total', () async {
    final app = await bootedApp();
    final a = await freshProduct(app, name: 'A');
    final b = await freshProduct(app, name: 'B');
    final c = await freshProduct(app, name: 'C');
    final lines = [
      PurchaseLineInput(
          productId: a,
          bags: 10,
          rate: 1000,
          batchNo: 'A1',
          expiry: inDays(60)),
      PurchaseLineInput(
          productId: b,
          bags: 5,
          rate: 900.5,
          batchNo: 'B1',
          expiry: inDays(60)),
      PurchaseLineInput(
          productId: c, bags: 8, rate: 750, batchNo: 'C1', expiry: inDays(60)),
      const PurchaseLineInput(),
    ];
    final totals = PurchaseTotals.of(lines, otherCharges: 350);
    expect(totals.subtotal, 10000 + 4502.5 + 6000);
    expect(totals.bags, 23);
    expect(totals.grandTotal, 20502.5 + 350);

    final res = await app.savePurchase(
        supplierId: app.suppliers.first.id, lines: lines, otherCharges: 350);
    expect(res.ok, isTrue, reason: res.error);
    expect(res.purchase!.items, hasLength(3));
    expect(res.purchase!.subtotal, 20502.5);
    expect(res.purchase!.otherCharges, 350);
    expect(res.purchase!.total, 20852.5);
    expect(app.stockOf(a).bags, 10);
    expect(app.stockOf(b).bags, 5);
    expect(app.stockOf(c).bags, 8);
  });

  test('Other charges default to 0 and cannot be negative', () async {
    final app = await bootedApp();
    final a = await freshProduct(app);
    final line = PurchaseLineInput(
        productId: a, bags: 1, rate: 100, batchNo: 'Z', expiry: inDays(30));
    expect(PurchaseTotals.of([line]).grandTotal, 100);
    final bad = await app.savePurchase(
        supplierId: app.suppliers.first.id, lines: [line], otherCharges: -5);
    expect(bad.ok, isFalse);
  });

  test(
      'Purchase validation: party, product, bags, purchase rate, batch, expiry',
      () async {
    final app = await bootedApp();
    final a = await freshProduct(app);
    final sup = app.suppliers.first.id;
    Future<String?> err(String? s, PurchaseLineInput l) async =>
        (await app.savePurchase(supplierId: s, lines: [l])).error;

    final ok = PurchaseLineInput(
        productId: a, bags: 2, rate: 10, batchNo: 'B', expiry: inDays(9));
    expect(await err(null, ok), contains('पार्टी'));
    expect(await err(sup, const PurchaseLineInput()), contains('उत्पादन'));
    expect(
        await err(
            sup,
            PurchaseLineInput(
                productId: a, rate: 10, batchNo: 'B', expiry: inDays(9))),
        contains('bags'));
    expect(
        await err(
            sup,
            PurchaseLineInput(
                productId: a, bags: 2, batchNo: 'B', expiry: inDays(9))),
        contains('purchase rate'));
    expect(
        await err(
            sup,
            PurchaseLineInput(
                productId: a, bags: 2, rate: 10, expiry: inDays(9))),
        contains('batch'));
    expect(
        await err(sup,
            PurchaseLineInput(productId: a, bags: 2, rate: 10, batchNo: 'B')),
        contains('expiry'));
    expect(app.purchases, isEmpty);
  });

  test('Two lines with the same product + batch no. go into one batch',
      () async {
    final app = await bootedApp();
    final a = await freshProduct(app);
    final res =
        await app.savePurchase(supplierId: app.suppliers.first.id, lines: [
      PurchaseLineInput(
          productId: a, bags: 4, rate: 100, batchNo: 'S', expiry: inDays(40)),
      PurchaseLineInput(
          productId: a, bags: 6, rate: 110, batchNo: 'S', expiry: inDays(40)),
    ]);
    expect(res.ok, isTrue, reason: res.error);
    final ids = res.purchase!.items.map((i) => i.batchId).toSet();
    expect(ids, hasLength(1));
    final batch = app.batchOf(ids.single)!;
    expect(batch.bagsAvailable, 10);
    expect(batch.bagsReceived, 10);
    expect(batch.unitCost, 110); // latest purchase cost wins
  });

  test('Voiding a purchase takes its bags back out; refused once they are sold',
      () async {
    final app = await bootedApp();
    final a = await freshProduct(app);
    final sup = app.suppliers.first.id;
    final first = (await app.savePurchase(supplierId: sup, lines: [
      PurchaseLineInput(
          productId: a, bags: 5, rate: 100, batchNo: 'V1', expiry: inDays(40)),
    ]))
        .purchase!;
    expect(await app.voidPurchase(first.id), isNull);
    expect(app.stockOf(a).bags, 0);
    expect(app.purchaseOf(first.id)!.status, BillStatus.voided);
    expect(await app.voidPurchase(first.id), isNotNull); // already void

    final second = (await app.savePurchase(supplierId: sup, lines: [
      PurchaseLineInput(
          productId: a, bags: 5, rate: 100, batchNo: 'V2', expiry: inDays(40)),
    ]))
        .purchase!;
    app.addToCart(a, SaleType.bag, 3);
    expect((await app.finalizeSale()).ok, isTrue);
    final err = await app.voidPurchase(second.id);
    expect(err, contains('already sold'));
    expect(app.stockOf(a).bags, 2); // untouched
    expect(app.purchaseOf(second.id)!.status, BillStatus.finalized);
  });

  test('Editing a purchase applies only the net change and keeps the number',
      () async {
    final app = await bootedApp();
    final a = await freshProduct(app);
    final b = await freshProduct(app, name: 'B');
    final sup = app.suppliers.first.id;
    final orig = (await app.savePurchase(supplierId: sup, lines: [
      PurchaseLineInput(
          productId: a, bags: 10, rate: 100, batchNo: 'E1', expiry: inDays(40)),
    ]))
        .purchase!;
    // 4 of those bags are sold before the correction.
    app.addToCart(a, SaleType.bag, 4);
    expect((await app.finalizeSale()).ok, isTrue);

    final res = await app.savePurchase(
      supplierId: sup,
      editingPurchaseId: orig.id,
      lines: [
        PurchaseLineInput(
            productId: a, bags: 8, rate: 95, batchNo: 'E1', expiry: inDays(40)),
        PurchaseLineInput(
            productId: b, bags: 3, rate: 50, batchNo: 'E2', expiry: inDays(40)),
      ],
      otherCharges: 20,
    );
    expect(res.ok, isTrue, reason: res.error);
    final rev = res.purchase!;
    expect(rev.purchaseNumber, orig.purchaseNumber);
    expect(rev.revision, 1);
    expect(rev.originalPurchaseId, orig.id);
    expect(rev.total, 8 * 95 + 3 * 50 + 20);
    expect(app.purchaseOf(orig.id)!.status, BillStatus.voided);
    expect(app.purchaseOf(orig.id)!.replacedByPurchaseId, rev.id);
    expect(app.stockOf(a).bags, 4); // 10 - 4 sold - 2 corrected away
    expect(app.stockOf(b).bags, 3);

    // Cutting it below what was already sold is refused and changes nothing.
    final tooFew = await app.savePurchase(
      supplierId: sup,
      editingPurchaseId: rev.id,
      lines: [
        PurchaseLineInput(
            productId: a, bags: 2, rate: 95, batchNo: 'E1', expiry: inDays(40)),
      ],
    );
    expect(tooFew.ok, isFalse);
    expect(app.stockOf(a).bags, 4);
    expect(app.purchaseOf(rev.id)!.status, BillStatus.finalized);
  });

  test('A rejected transaction leaves stock and purchases untouched', () async {
    final app = await bootedApp(RejectingRepository());
    final a = await freshProduct(app);
    final batchesBefore = app.batches.length;
    final res =
        await app.savePurchase(supplierId: app.suppliers.first.id, lines: [
      PurchaseLineInput(
          productId: a, bags: 5, rate: 100, batchNo: 'X', expiry: inDays(40)),
    ]);
    expect(res.ok, isFalse);
    expect(res.error, contains('conflict'));
    expect(app.purchases, isEmpty);
    expect(app.batches.length, batchesBefore);
    expect(app.stockOf(a).bags, 0);
  });

  test('Only the owner may void or edit a purchase', () async {
    final app = await bootedApp(StaffLoginRepository());
    expect(app.hasOwnerRights, isFalse);
    final a = await freshProduct(app);
    final p =
        (await app.savePurchase(supplierId: app.suppliers.first.id, lines: [
      PurchaseLineInput(
          productId: a, bags: 5, rate: 100, batchNo: 'O', expiry: inDays(40)),
    ]))
            .purchase!;
    expect(await app.voidPurchase(p.id), contains('owner'));
    expect(app.stockOf(a).bags, 5);
  });
}
