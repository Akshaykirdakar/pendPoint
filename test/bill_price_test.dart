// Selling price edits are BILL-SCOPED: changing the rate on a bill (new or
// being edited) changes only that bill's line — never the product master,
// other/future bills, batch purchase cost, or historical bills.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/models/bill.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/state/purchase_draft.dart';
import 'package:pend_point/ui/screens/sales_entry_screen.dart';
import 'package:pend_point/utils/theme.dart';

import 'test_support.dart';

/// Samruddhi 25kg — default selling price ₹42/kg (₹1,050 a bag).
Future<String> _samruddhi(AppState app) async {
  final id = await freshProduct(app, name: 'Samruddhi 25kg', sellPrice: 1050);
  final i = app.products.indexWhere((p) => p.id == id);
  app.products[i] = app.products[i].copyWith(perKgPrice: 42, minPriceFloor: 0);
  final res =
      await app.savePurchase(supplierId: app.suppliers.first.id, lines: [
    PurchaseLineInput(
        productId: id, bags: 20, rate: 800, batchNo: 'S1', expiry: inDays(90))
  ]);
  expect(res.ok, isTrue, reason: res.error);
  return id;
}

void _cash(AppState app) => app.payments
  ..clear()
  ..add(Payment(PayMode.cash, app.cartTotal));

void main() {
  late AppState app;
  late String pid;

  setUp(() async {
    app = await bootedApp();
    app.settings.gateOverride = false; // no PIN prompt for these discounts
    pid = await _samruddhi(app);
  });

  test(
      '1+2+4: price changed on Bill A → only Bill A; master and Bill B keep ₹42',
      () async {
    final masterBefore = app.productOf(pid)!;

    // Bill A: 25 kg at ₹40/kg instead of ₹42.
    app.addToCart(pid, SaleType.kg, 25);
    expect(app.cart.single.rate, 42);
    app.setLineRate(0, 40);
    _cash(app);
    final a = (await app.finalizeSale()).bill!;
    expect(a.items.fold(0.0, (s, i) => s + i.qty), 25);
    expect(a.items.every((i) => i.rate == 40), isTrue);
    expect(a.items.every((i) => i.catalogRate == 42), isTrue);
    expect(a.total, 1000);

    // Product master untouched — every price field.
    final master = app.productOf(pid)!;
    expect(master.perKgPrice, 42);
    expect(master.fullBagPrice, masterBefore.fullBagPrice);
    expect(master.costPrice, masterBefore.costPrice);
    expect(master.minPriceFloor, masterBefore.minPriceFloor);

    // Bill B defaults to the ORIGINAL price.
    app.addToCart(pid, SaleType.kg, 25);
    expect(app.cart.single.rate, 42);
    expect(app.cart.single.catalogRate, 42);
    _cash(app);
    final b = (await app.finalizeSale()).bill!;
    expect(b.items.every((i) => i.rate == 42), isTrue);
    expect(b.total, 1050);
  });

  test('3+5: editing Bill A changes only its revision; history stays',
      () async {
    app.addToCart(pid, SaleType.kg, 25);
    app.setLineRate(0, 40);
    _cash(app);
    final a = (await app.finalizeSale()).bill!;

    // Correct Bill A: the edit loads the bill's OWN rate (₹40), not ₹42.
    expect(app.beginEditBill(a.id), isNull);
    expect(app.cart.single.rate, 40);
    expect(app.cart.single.catalogRate, 42);
    app.setLineRate(0, 41);
    _cash(app);
    final rev = (await app.finalizeSale()).bill!;
    expect(rev.revision, 1);
    expect(rev.items.every((i) => i.rate == 41), isTrue);
    expect(rev.total, 1025);

    // The original revision still shows the rate actually used on it.
    final original = app.bills.firstWhere((x) => x.id == a.id);
    expect(original.status, BillStatus.voided);
    expect(original.items.every((i) => i.rate == 40), isTrue);
    expect(original.total, 1000);
    // …and the master is still ₹42.
    expect(app.productOf(pid)!.perKgPrice, 42);
  });

  test('5: historical bills keep their rate when the master price changes',
      () async {
    app.addToCart(pid, SaleType.bag, 1);
    _cash(app);
    final old = (await app.finalizeSale()).bill!;
    expect(old.items.single.rate, 1050);

    final p = app.productOf(pid)!;
    await app.saveProduct(
        id: pid,
        brandId: p.brandId,
        name: p.name,
        nameMr: p.nameMr,
        bagWeightKg: p.bagWeightKg,
        fullBagPrice: 1100,
        perKgPrice: 44);
    final stored = app.bills.firstWhere((b) => b.id == old.id);
    expect(stored.items.single.rate, 1050);
    expect(stored.total, 1050);
  });

  test('6: a bill rate only changes billing totals — never stock or cost',
      () async {
    final batch = app.batchesOf(pid).single;
    final unitCost = batch.unitCost;
    final batchBags = batch.bagsAvailable; // Batch is updated in place
    final bagsBefore = app.stockOf(pid).bags;

    app.addToCart(pid, SaleType.bag, 2);
    app.setLineRate(0, 900); // well below catalogue
    _cash(app);
    final bill = (await app.finalizeSale()).bill!;
    expect(bill.total, 1800);

    // Same stock movement as at the catalogue price; purchase cost intact.
    expect(app.stockOf(pid).bags, bagsBefore - 2);
    final after = app.batchOf(batch.id)!;
    expect(after.unitCost, unitCost);
    expect(after.bagsAvailable, batchBags - 2);
    expect(app.productOf(pid)!.costPrice, 1050 * 0.8);
  });

  testWidgets(
      'UI: a changed rate is marked "for this bill" with the master price',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final a = (await tester.runAsync(bootedApp))!;
    a.settings.gateOverride = false;
    final id = (await tester.runAsync(() => _samruddhi(a)))!;
    a.addToCart(id, SaleType.kg, 25);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: a,
        child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: const SalesEntryScreen())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sales-row-0-bill-rate')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sales-row-0-rate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rate-sheet-bill-only')), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '40');
    await tester.tap(find.textContaining('लागू करा'));
    await tester.pumpAndSettle();

    expect(a.cart.single.rate, 40);
    expect(a.productOf(id)!.perKgPrice, 42);
    final note = tester
        .widget<Text>(find.byKey(const ValueKey('sales-row-0-bill-rate')))
        .data!;
    expect(note, contains('₹40'));
    expect(note, contains('₹42'));
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('sales-row-0-amount')))
            .data,
        '₹1,000');
    expect(tester.takeException(), isNull);
  });
}
