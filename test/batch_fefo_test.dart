// Unit tests for the batch/expiry/FEFO architecture: Stock In creating/
// topping-up real batches, FEFO sale allocation (skipping expired batches,
// splitting across batches), insufficient-stock rejection, void/partial
// return crediting back the exact batch sold, and branch transfer.
import 'package:flutter_test/flutter_test.dart';

import 'package:pend_point/data/memory_repository.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/state/app_state.dart';

Future<AppState> _bootedApp() async {
  final app = AppState(InMemoryRepository());
  await app.bootstrap();
  while (app.historyLoading) {
    await Future.delayed(Duration.zero);
  }
  return app;
}

/// A brand-new product with no pre-existing batches (the seeded catalogue's
/// products all already carry sample batches — see seed_data.dart — which
/// would interfere with a test asserting an exact FEFO allocation), scoped
/// to [branchId] so Stock In/POS can use it immediately.
Future<String> _freshProduct(AppState app, String branchId) async {
  final p = await app.saveProduct(
      brandId: app.brands.first.id,
      name: 'Test Product',
      nameMr: 'चाचणी उत्पादन',
      bagWeightKg: 50,
      fullBagPrice: 1000,
      perKgPrice: 20);
  final idx = app.products.indexWhere((x) => x.id == p.id);
  app.products[idx] = app.products[idx].copyWith(branchIds: [branchId]);
  return p.id;
}

void main() {
  test('stockIn creates a new batch, then tops up the same batch no.', () async {
    final app = await _bootedApp();
    final branch = app.branches.first.id;
    final supplier = app.suppliers.first.id;
    final productId = app.products.first.id;
    final before = app.batches.where((b) => b.productId == productId).length;

    await app.stockIn(
        branchId: branch,
        productId: productId,
        supplierId: supplier,
        batchNo: 'TEST-001',
        expiry: DateTime.now().add(const Duration(days: 100)),
        bags: 10,
        cost: 500);
    expect(app.batches.where((b) => b.productId == productId).length, before + 1);
    final batch = app.batches.firstWhere((b) => b.batchNo == 'TEST-001');
    expect(batch.bagsAvailable, 10);

    // Same branch/product/batch no. tops up rather than duplicating.
    await app.stockIn(
        branchId: branch,
        productId: productId,
        supplierId: supplier,
        batchNo: 'TEST-001',
        expiry: DateTime.now().add(const Duration(days: 100)),
        bags: 5,
        cost: 520);
    expect(app.batches.where((b) => b.productId == productId).length, before + 1);
    final topped = app.batches.firstWhere((b) => b.batchNo == 'TEST-001');
    expect(topped.bagsAvailable, 15);
    expect(topped.unitCost, 520); // latest cost wins
  });

  test('FEFO allocates the nearest-expiry batch first, splitting across batches',
      () async {
    final app = await _bootedApp();
    final branch = app.branches.first.id;
    final supplier = app.suppliers.first.id;
    final productId = await _freshProduct(app, branch);
    // Two batches: A expires sooner (20 bags), B later (50 bags).
    await app.stockIn(
        branchId: branch,
        productId: productId,
        supplierId: supplier,
        batchNo: 'FEFO-A',
        expiry: DateTime.now().add(const Duration(days: 10)),
        bags: 20,
        cost: 100);
    await app.stockIn(
        branchId: branch,
        productId: productId,
        supplierId: supplier,
        batchNo: 'FEFO-B',
        expiry: DateTime.now().add(const Duration(days: 200)),
        bags: 50,
        cost: 100);

    app.setActiveBranch(branch);
    app.addToCart(productId, SaleType.bag, 30);
    final res = await app.finalizeSale();
    expect(res.ok, isTrue);
    // 20 from A (fully depleted) + 10 from B.
    final lines = res.bill!.items.where((i) => i.productId == productId).toList();
    expect(lines.length, 2);
    final fromA = lines.firstWhere((l) => l.batchNo == 'FEFO-A');
    final fromB = lines.firstWhere((l) => l.batchNo == 'FEFO-B');
    expect(fromA.qty, 20);
    expect(fromB.qty, 10);

    final batchA = app.batches.firstWhere((b) => b.batchNo == 'FEFO-A');
    final batchB = app.batches.firstWhere((b) => b.batchNo == 'FEFO-B');
    expect(batchA.bagsAvailable, 0);
    expect(batchB.bagsAvailable, 40);
  });

  test('An expired batch is never allocated; sale fails if remaining stock is insufficient',
      () async {
    final app = await _bootedApp();
    final branch = app.branches.first.id;
    final supplier = app.suppliers.first.id;
    final productId = await _freshProduct(app, branch);
    await app.stockIn(
        branchId: branch,
        productId: productId,
        supplierId: supplier,
        batchNo: 'OLD',
        expiry: DateTime.now().subtract(const Duration(days: 5)), // already expired
        bags: 100,
        cost: 100);
    await app.stockIn(
        branchId: branch,
        productId: productId,
        supplierId: supplier,
        batchNo: 'FRESH',
        expiry: DateTime.now().add(const Duration(days: 30)),
        bags: 5,
        cost: 100);

    app.setActiveBranch(branch);
    app.addToCart(productId, SaleType.bag, 5);
    final ok = await app.finalizeSale();
    expect(ok.ok, isTrue);
    expect(ok.bill!.items.single.batchNo, 'FRESH'); // never the expired one

    // Now try to oversell beyond the one remaining sellable batch.
    app.addToCart(productId, SaleType.bag, 1);
    final fail = await app.finalizeSale();
    expect(fail.ok, isFalse);
    expect(fail.error, contains('अपुरा साठा'));
  });

  test('Voiding a bill credits stock back to the exact batch it was sold from',
      () async {
    final app = await _bootedApp();
    final branch = app.branches.first.id;
    final supplier = app.suppliers.first.id;
    final productId = app.products[3].id;
    await app.stockIn(
        branchId: branch,
        productId: productId,
        supplierId: supplier,
        batchNo: 'V1',
        expiry: DateTime.now().add(const Duration(days: 30)),
        bags: 10,
        cost: 100);
    app.setActiveBranch(branch);
    app.addToCart(productId, SaleType.bag, 4);
    final res = await app.finalizeSale();
    final batchBeforeVoid = app.batches.firstWhere((b) => b.batchNo == 'V1');
    expect(batchBeforeVoid.bagsAvailable, 6);

    await app.voidBill(res.bill!.id);
    final batchAfterVoid = app.batches.firstWhere((b) => b.batchNo == 'V1');
    expect(batchAfterVoid.bagsAvailable, 10);
  });

  test('Partial return credits the batch and cannot exceed the original sale qty',
      () async {
    final app = await _bootedApp();
    final branch = app.branches.first.id;
    final supplier = app.suppliers.first.id;
    final productId = app.products[4].id;
    await app.stockIn(
        branchId: branch,
        productId: productId,
        supplierId: supplier,
        batchNo: 'R1',
        expiry: DateTime.now().add(const Duration(days: 30)),
        bags: 10,
        cost: 100);
    app.setActiveBranch(branch);
    app.addToCart(productId, SaleType.bag, 5);
    final res = await app.finalizeSale();
    final item = res.bill!.items.single;

    final err1 = await app.returnSaleLine(res.bill!, item, 2);
    expect(err1, isNull);
    expect(app.batches.firstWhere((b) => b.batchNo == 'R1').bagsAvailable, 7);

    // Returning more than what's left of the original 5 sold (2 already
    // returned) must be rejected.
    final err2 = await app.returnSaleLine(res.bill!, item, 4);
    expect(err2, isNotNull);
    expect(app.batches.firstWhere((b) => b.batchNo == 'R1').bagsAvailable, 7);
  });

  test('Branch transfer preserves batch identity and cannot exceed available qty',
      () async {
    final app = await _bootedApp();
    final branchA = app.branches.first.id;
    final branchB = app.branches.length > 1 ? app.branches[1].id : branchA;
    final supplier = app.suppliers.first.id;
    final productId = app.products[5].id;
    await app.stockIn(
        branchId: branchA,
        productId: productId,
        supplierId: supplier,
        batchNo: 'TR1',
        expiry: DateTime.now().add(const Duration(days: 30)),
        bags: 10,
        cost: 100);
    final source = app.batches.firstWhere((b) => b.batchNo == 'TR1');

    final tooMuch = await app.transferStock(source.id, branchB, bags: 999);
    expect(tooMuch, isNotNull);

    final ok = await app.transferStock(source.id, branchB, bags: 4);
    expect(ok, isNull);
    expect(source.bagsAvailable, 6);
    final dest = app.batches
        .firstWhere((b) => b.sourceBatchId == source.id && b.branchId == branchB);
    expect(dest.batchNo, 'TR1');
    expect(dest.bagsAvailable, 4);
  });
}
