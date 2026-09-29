// Sales bills: many products in one bill, FEFO/FIFO batch consumption,
// selling vs purchase rate, bill edit (stock reversal + re-apply, khata),
// void (incl. after a partial return), permissions, and rejected commits.
import 'package:flutter_test/flutter_test.dart';

import 'package:pend_point/models/bill.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/state/purchase_draft.dart';

import 'test_support.dart';

Future<void> _buy(AppState app, String productId, int bags,
    {String batchNo = '', DateTime? expiry, double rate = 700}) async {
  final res =
      await app.savePurchase(supplierId: app.suppliers.first.id, lines: [
    PurchaseLineInput(
        productId: productId,
        bags: bags,
        rate: rate,
        batchNo: batchNo,
        expiry: expiry)
  ]);
  expect(res.ok, isTrue, reason: res.error);
}

void _cashFor(AppState app) {
  app.payments
    ..clear()
    ..add(Payment(PayMode.cash, app.cartTotal));
}

void main() {
  test('One sales bill with multiple products deducts each product', () async {
    final app = await bootedApp();
    final a = await freshProduct(app, name: 'A', sellPrice: 1000);
    final b = await freshProduct(app, name: 'B', sellPrice: 1200);
    final c = await freshProduct(app, name: 'C', sellPrice: 800);
    await _buy(app, a, 10, batchNo: 'A', expiry: inDays(50));
    await _buy(app, b, 10, batchNo: 'B', expiry: inDays(50));
    await _buy(app, c, 10, batchNo: 'C', expiry: inDays(50));

    app.addToCart(a, SaleType.bag, 2);
    app.addToCart(b, SaleType.bag, 3);
    app.addToCart(c, SaleType.bag, 4);
    app.addToCart(a, SaleType.kg, 5); // loose kg still sells alongside bags
    final res = await app.finalizeSale();
    expect(res.ok, isTrue, reason: res.error);
    final bill = res.bill!;
    expect(bill.items.map((i) => i.productId).toSet(), {a, b, c});
    expect(bill.total, 2 * 1000 + 3 * 1200 + 4 * 800 + 5 * 25);
    expect(app.stockOf(b).bags, 7);
    expect(app.stockOf(c).bags, 6);
    // 2 bags + one bag opened for 5 kg → 7 full bags and 45 kg loose left.
    expect(app.stockOf(a).bags, 7);
    expect(app.stockOf(a).looseKg, 45);
    expect(app.cart, isEmpty);
  });

  test('Selling rate is the product price, never the batch purchase rate',
      () async {
    final app = await bootedApp();
    final a = await freshProduct(app, sellPrice: 1450);
    await _buy(app, a, 5, batchNo: 'R', expiry: inDays(50), rate: 1111);
    app.addToCart(a, SaleType.bag, 1);
    expect(app.cart.single.rate, 1450);
    final bill = (await app.finalizeSale()).bill!;
    expect(bill.items.single.rate, 1450);
    expect(bill.items.single.catalogRate, 1450);
    expect(app.batchOf(bill.items.single.batchId!)!.unitCost, 1111);
  });

  test('FIFO without expiry: the bags that came in first are sold first',
      () async {
    final app = await bootedApp();
    final a =
        await freshProduct(app, batchTracking: false, expiryTracking: false);
    await _buy(app, a, 3, batchNo: 'OLD');
    await _buy(app, a, 10, batchNo: 'NEW');

    app.addToCart(a, SaleType.bag, 5);
    final bill = (await app.finalizeSale()).bill!;
    final byBatch = {for (final i in bill.items) i.batchNo: i.qty};
    expect(byBatch, {'OLD': 3, 'NEW': 2}); // exhausts OLD, then moves on
    expect(app.nextSaleBatch(a)!.batchNo, 'NEW');
  });

  test(
      'FEFO stays authoritative: an earlier expiry goes first even if it arrived later',
      () async {
    final app = await bootedApp();
    final a = await freshProduct(app);
    await _buy(app, a, 5, batchNo: 'FIRST-IN', expiry: inDays(200));
    await _buy(app, a, 5, batchNo: 'SOON', expiry: inDays(20));
    // Same expiry as SOON but arrived after it → FIFO breaks the tie.
    await _buy(app, a, 5, batchNo: 'SOON-2', expiry: inDays(20));

    app.addToCart(a, SaleType.bag, 7);
    final bill = (await app.finalizeSale()).bill!;
    final byBatch = {for (final i in bill.items) i.batchNo: i.qty};
    expect(byBatch, {'SOON': 5, 'SOON-2': 2});
  });

  test('Editing a bill restores the original stock and applies the correction',
      () async {
    final app = await bootedApp();
    final a = await freshProduct(app, name: 'A', sellPrice: 1000);
    final b = await freshProduct(app, name: 'B', sellPrice: 500);
    await _buy(app, a, 5, batchNo: 'A', expiry: inDays(50));
    await _buy(app, b, 5, batchNo: 'B', expiry: inDays(50));
    final cust = app.customers.first;
    final dueBefore = cust.outstanding;

    // Original: all 5 bags of A, on credit.
    app.addToCart(a, SaleType.bag, 5);
    app.setCartCustomer(cust.id);
    app.payments
      ..clear()
      ..add(Payment(PayMode.credit, 5000));
    final orig = (await app.finalizeSale()).bill!;
    expect(app.stockOf(a).bags, 0);
    expect(cust.outstanding, dueBefore + 5000);

    // Correct it: 3 of A + 2 of B, paid 1000 cash + rest credit.
    expect(app.beginEditBill(orig.id), isNull);
    expect(app.editingBillId, orig.id);
    expect(app.cart.single.qty, 5);
    app.setLineQty(0, 3);
    app.addToCart(b, SaleType.bag, 2);
    app.payments
      ..clear()
      ..add(const Payment(PayMode.cash, 1000))
      ..add(Payment(PayMode.credit, app.cartTotal - 1000));
    final res = await app.finalizeSale();
    expect(res.ok, isTrue, reason: res.error);
    final rev = res.bill!;

    expect(rev.billNumber, orig.billNumber);
    expect(rev.revision, 1);
    expect(rev.originalBillId, orig.id);
    expect(rev.at, orig.at);
    expect(rev.total, 3 * 1000 + 2 * 500);
    final old = app.bills.firstWhere((x) => x.id == orig.id);
    expect(old.status, BillStatus.voided);
    expect(old.replacedByBillId, rev.id);
    expect(app.finalBills.where((x) => x.billNumber == orig.billNumber),
        [rev]); // reports count only the corrected version

    expect(app.stockOf(a).bags, 2); // 2 bags came back
    expect(app.stockOf(b).bags, 3);
    expect(cust.outstanding, dueBefore + 3000); // 5000 reversed, 3000 applied
    expect(app.editingBillId, isNull);
    expect(app.cart, isEmpty);

    // The replaced version can't be edited or voided again.
    expect(app.beginEditBill(orig.id), isNotNull);
    expect(await app.voidBill(orig.id), isNotNull);
  });

  test('An edit may reuse the stock its own reversal gives back', () async {
    final app = await bootedApp();
    final a = await freshProduct(app);
    await _buy(app, a, 4, batchNo: 'ONLY', expiry: inDays(50));
    app.addToCart(a, SaleType.bag, 4);
    final orig = (await app.finalizeSale()).bill!;
    expect(app.stockOf(a).bags, 0);

    app.beginEditBill(orig.id);
    app.setLineRate(0, app.cart.single.rate - 10); // price correction only
    _cashFor(app);
    final res = await app.finalizeSale();
    expect(res.ok, isTrue, reason: res.error);
    expect(app.stockOf(a).bags, 0);
    expect(res.bill!.items.single.qty, 4);
  });

  test('Cancelling an edit leaves the original bill untouched', () async {
    final app = await bootedApp();
    final a = await freshProduct(app);
    await _buy(app, a, 4, batchNo: 'C', expiry: inDays(50));
    app.addToCart(a, SaleType.bag, 1);
    final orig = (await app.finalizeSale()).bill!;
    app.beginEditBill(orig.id);
    app.setLineQty(0, 3);
    app.cancelEditBill();
    expect(app.cart, isEmpty);
    expect(app.editingBillId, isNull);
    expect(app.bills.firstWhere((b) => b.id == orig.id).status,
        BillStatus.finalized);
    expect(app.stockOf(a).bags, 3);
  });

  test('Void restores stock; after a partial return only the rest comes back',
      () async {
    final app = await bootedApp();
    final a = await freshProduct(app);
    await _buy(app, a, 10, batchNo: 'VR', expiry: inDays(50));
    app.addToCart(a, SaleType.bag, 6);
    final bill = (await app.finalizeSale()).bill!;
    expect(app.stockOf(a).bags, 4);

    expect(await app.returnSaleLine(bill, bill.items.single, 2), isNull);
    expect(app.stockOf(a).bags, 6);
    // Edit is blocked once a return exists (would double-count it)…
    expect(app.whyBillNotEditable(bill), isNotNull);
    expect(app.beginEditBill(bill.id), isNotNull);

    // …but void works and credits only the 4 not yet returned.
    expect(await app.voidBill(bill.id), isNull);
    expect(app.stockOf(a).bags, 10);
    expect(
        app.bills.firstWhere((b) => b.id == bill.id).status, BillStatus.voided);
    expect(await app.voidBill(bill.id), isNotNull); // no double void
    expect(app.stockOf(a).bags, 10);
  });

  test('Non-owner logins cannot edit or void bills', () async {
    final app = await bootedApp(StaffLoginRepository());
    final a = await freshProduct(app);
    await _buy(app, a, 3, batchNo: 'S', expiry: inDays(50));
    app.addToCart(a, SaleType.bag, 1);
    final bill = (await app.finalizeSale()).bill!; // staff can still sell
    expect(app.beginEditBill(bill.id), contains('owner'));
    expect(await app.voidBill(bill.id), contains('owner'));
    expect(app.stockOf(a).bags, 2);
  });

  test('A rejected sale commit changes nothing and keeps the cart', () async {
    final app = await bootedApp(RejectingRepository());
    final pid = app.products.first.id; // seeded product with seeded batches
    final before = app.stockOf(pid).bags;
    final billsBefore = app.bills.length;
    app.addToCart(pid, SaleType.bag, 1);
    final res = await app.finalizeSale();
    expect(res.ok, isFalse);
    expect(res.error, contains('conflict'));
    expect(app.stockOf(pid).bags, before);
    expect(app.bills.length, billsBefore);
    expect(app.cart, hasLength(1));
  });

  test(
      'Sale commit carries batch deltas (not absolute stock) to the repository',
      () async {
    final repo = RecordingRepository();
    final app = await bootedApp(repo);
    final a = await freshProduct(app);
    await _buy(app, a, 10, batchNo: 'D', expiry: inDays(50));
    app.addToCart(a, SaleType.bag, 3);
    final bill = (await app.finalizeSale()).bill!;
    final commit = repo.commits.last;
    expect(commit.newBills.single.id, bill.id);
    final d = commit.batches.values.single;
    expect(d.create, isNull);
    expect(d.bagsAvailable, -3);
    expect(d.bagsSold, 3);
    expect(commit.rollupDeltas[a], (-3, 0.0));
  });
}
