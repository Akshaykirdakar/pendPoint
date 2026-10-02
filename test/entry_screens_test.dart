// Widget tests for the new entry screens: searchable party/product pickers,
// the always-present next row, running totals, save confirmation, and the
// visible Edit / Void / WhatsApp actions on a saved bill.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/models/enums.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/ui/screens/bill_screen.dart';
import 'package:pend_point/ui/screens/party_master_screen.dart';
import 'package:pend_point/ui/screens/purchase_entry_screen.dart';
import 'package:pend_point/ui/screens/sales_entry_screen.dart';
import 'package:pend_point/utils/theme.dart';

import 'test_support.dart';

Future<AppState> _pump(WidgetTester tester, Widget home,
    {Size size = const Size(420, 2000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final app = (await tester.runAsync(bootedApp))!;
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: app,
    child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
  ));
  await tester.pumpAndSettle();
  return app;
}

/// Opens a searchable picker, types [query] and picks the first match.
Future<void> _pick(WidgetTester tester, Key field, String query) async {
  await tester.tap(find.byKey(field));
  await tester.pumpAndSettle();
  // The full list is visible before typing anything.
  expect(find.byKey(const ValueKey('picker-option-0')), findsOneWidget);
  await tester.enterText(find.byKey(const ValueKey('picker-search')), query);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('picker-option-0')));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

void main() {
  testWidgets('Purchase entry: party search, rows auto-extend, totals, save',
      (tester) async {
    final app = await _pump(tester, const PurchaseEntryScreen());
    final before = app.stockOf('p1').bags;

    await _pick(tester, const ValueKey('purchase-party'), '11'); // by code
    expect(find.textContaining('ABC Traders'), findsOneWidget);

    await _pick(tester, const ValueKey('purchase-row-0-product'), 'milk');
    // Picking a product in the empty row adds the next empty row.
    expect(
        find.byKey(const ValueKey('purchase-row-1-product')), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('purchase-row-0-bags')), '10');
    await tester.enterText(
        find.byKey(const ValueKey('purchase-row-0-rate')), '1200');
    await tester.enterText(
        find.byKey(const ValueKey('purchase-row-0-batch')), 'W-1');
    await tester.pump();
    expect(_text(tester, const ValueKey('purchase-row-0-amount')), '₹12,000');
    expect(_text(tester, const ValueKey('purchase-grand-total')), '₹12,000');

    await tester.enterText(
        find.byKey(const ValueKey('purchase-other-charges')), '300');
    await tester.pump();
    expect(_text(tester, const ValueKey('purchase-grand-total')), '₹12,300');

    // Expiry (required for this product).
    await tester.tap(find.text('निवडा · Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('purchase-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Purchase saved'), findsOneWidget);
    expect(app.purchases, hasLength(1));
    expect(app.purchases.single.total, 12300);
    expect(app.stockOf('p1').bags, before + 10);
  });

  testWidgets('New Sale Bill: customer → product → qty → Add → Finalize → Bill saved',
      (tester) async {
    final app = await _pump(tester, const SalesEntryScreen());

    await _pick(tester, const ValueKey('sales-party'), '9822011'); // by mobile
    expect(app.cartCustomerId, 'c1');
    expect(find.byKey(const ValueKey('sale-customer-info')), findsOneWidget);

    // Product goes into the entry (not the bill) until "+ Add Item".
    await _pick(tester, const ValueKey('sales-next-product'), 'milk');
    expect(app.cart, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('sale-entry-qty')), '3');
    await tester.pump();
    final rate = app.productOf('p1')!.fullBagPrice;
    expect(tester.widget<TextField>(find.byKey(const ValueKey('sale-entry-rate'))).controller!.text,
        rate.toStringAsFixed(0));
    expect(tester.widget<TextField>(find.byKey(const ValueKey('sale-entry-amount'))).controller!.text,
        (3 * rate).toStringAsFixed(0));
    await tester.tap(find.byKey(const ValueKey('sale-add-item')));
    await tester.pumpAndSettle();
    expect(app.cart.single.qty, 3);
    expect(app.cartTotal, 3 * rate);
    expect(find.byKey(const ValueKey('sales-row-0')), findsOneWidget);

    await _pick(tester, const ValueKey('sales-next-product'), 'kargil');
    await tester.tap(find.byKey(const ValueKey('sale-add-item')));
    await tester.pumpAndSettle();
    expect(app.cart, hasLength(2));
    await tester.tap(find.byKey(const ValueKey('sales-row-1-remove')));
    await tester.pumpAndSettle();
    expect(app.cart, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('sales-finalize')));
    await tester.pumpAndSettle();

    expect(find.textContaining('बिल सेव्ह झाले'), findsOneWidget);
    expect(find.textContaining('Bill saved successfully'), findsOneWidget);
    final bill = app.bills.first;
    expect(find.text('#${bill.billNumber}'), findsOneWidget);
    expect(find.text('रमेश पाटील'), findsOneWidget);
    for (final k in [
      'bill-new-sale',
      'bill-print',
      'bill-whatsapp',
      'bill-sms',
      'bill-share',
      'bill-edit',
      'bill-void'
    ]) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }

    // Edit is right there — opens the bill in the sale screen.
    await tester.ensureVisible(find.byKey(const ValueKey('bill-edit')));
    await tester.tap(find.byKey(const ValueKey('bill-edit')));
    await tester.pumpAndSettle();
    expect(app.editingBillId, bill.id);
    expect(find.textContaining('Editing bill #${bill.billNumber}'),
        findsOneWidget);
  });

  testWidgets('Voided bill hides Edit/Void and says so', (tester) async {
    final app = (await tester.runAsync(bootedApp))!;
    app.addToCart('p1', SaleType.bag, 1);
    final bill = (await app.finalizeSale()).bill!;
    await app.voidBill(bill.id);
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: BillScreen(billId: bill.id)),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('VOID'), findsOneWidget);
    expect(find.byKey(const ValueKey('bill-edit')), findsNothing);
    expect(find.byKey(const ValueKey('bill-void')), findsNothing);
    expect(find.byKey(const ValueKey('bill-whatsapp')), findsOneWidget);
  });

  testWidgets('Party Master search by code, name and mobile', (tester) async {
    await _pump(tester, const PartyMasterScreen());
    expect(find.text('ABC Traders'), findsOneWidget);
    expect(find.text('रमेश पाटील'), findsOneWidget);

    Future<void> search(String q) async {
      await tester.enterText(find.byKey(const ValueKey('party-search')), q);
      await tester.pumpAndSettle();
    }

    await search('13'); // supplier code
    expect(find.text('Godrej Distributor'), findsOneWidget);
    expect(find.text('ABC Traders'), findsNothing);

    await search('सुनिल'); // name
    expect(find.text('सुनिल जाधव'), findsOneWidget);
    expect(find.text('रमेश पाटील'), findsNothing);

    await search('70301'); // mobile
    expect(find.text('Dnyaneshwar F.'), findsOneWidget);
    expect(find.text('ABC Traders'), findsNothing);
  });

  testWidgets('Both entry grids fit a 360px-wide phone without overflow',
      (tester) async {
    final app = await _pump(tester, const SalesEntryScreen(),
        size: const Size(360, 2000));
    app.setCartCustomer('c1');
    app.addToCart('p1', SaleType.bag, 12);
    app.addToCart('p2', SaleType.kg, 7.5);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const PurchaseEntryScreen(productId: 'p1')),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('purchase-row-0-bags')), '100');
    await tester.enterText(
        find.byKey(const ValueKey('purchase-row-0-rate')), '123456');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
