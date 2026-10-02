// A product with no sellable stock can't be sold: it can't be added to a
// bill, and a bill asking for more than is in stock can't go to Payment.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/models/enums.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/ui/screens/bill_screen.dart';
import 'package:pend_point/ui/screens/product_detail_screen.dart';
import 'package:pend_point/ui/screens/sales_entry_screen.dart';
import 'package:pend_point/utils/theme.dart';

import 'test_support.dart';

void main() {
  test('an out-of-stock product cannot be added or swapped into a bill',
      () async {
    final app = await bootedApp();
    final empty = await freshProduct(app, name: 'Empty Feed');
    expect(app.hasSellableStock(empty), isFalse);

    expect(app.addToCart(empty, SaleType.bag, 1), AppState.outOfStockMessage);
    expect(app.addToCart(empty, SaleType.kg, 2), AppState.outOfStockMessage);
    expect(app.cart, isEmpty);

    expect(app.addToCart('p1', SaleType.bag, 1), isNull);
    expect(app.replaceLineProduct(0, empty), AppState.outOfStockMessage);
    expect(app.cart.single.productId, 'p1');
  });

  test('more than the stock left: the line is short and the sale fails',
      () async {
    final app = await bootedApp();
    final left = app.sellableQty('p1', SaleType.bag);
    final stock = app.stockOf('p1').bags;
    app.addToCart('p1', SaleType.bag, left);
    expect(app.shortLines, isEmpty);
    app.setLineQty(0, left + 1);
    expect(app.shortLines, [0]);
    final res = await app.finalizeSale();
    expect(res.ok, isFalse);
    expect(app.stockOf('p1').bags, stock);
  });

  Future<AppState> pump(WidgetTester tester, Widget Function(AppState) home,
      {Future<void> Function(AppState)? prep}) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = (await tester.runAsync(bootedApp))!;
    if (prep != null) await tester.runAsync(() => prep(app));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: home(app)),
    ));
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('bill entry: picker marks it, adding it is refused',
      (tester) async {
    late String empty;
    final app = await pump(tester, (_) => const SalesEntryScreen(),
        prep: (app) async => empty = await freshProduct(app, name: 'Empty Feed'));

    await tester.tap(find.byKey(const ValueKey('sales-next-product')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('picker-search')), 'Empty Feed');
    await tester.pumpAndSettle();
    expect(find.textContaining('साठा नाही'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('picker-option-0')));
    await tester.pumpAndSettle();

    expect(app.cart.where((l) => l.productId == empty), isEmpty);
    expect(find.textContaining('Out of stock'), findsOneWidget);
    expect(find.byKey(const ValueKey('sales-row-0')), findsNothing);
  });

  testWidgets('sale bill: Finalize is blocked while a line is over stock',
      (tester) async {
    final app = await pump(tester, (_) => const SalesEntryScreen());
    app.addToCart('p1', SaleType.bag, 1);
    app.setLineQty(0, app.sellableQty('p1', SaleType.bag) + 5);
    await tester.pumpAndSettle();
    expect(find.textContaining('sellable'), findsOneWidget);
    final bills = app.bills.length;

    await tester.tap(find.byKey(const ValueKey('sales-finalize')));
    await tester.pumpAndSettle();
    expect(find.byType(BillScreen), findsNothing);
    expect(find.textContaining('Not enough stock'), findsOneWidget);
    expect(app.bills, hasLength(bills));

    app.setLineQty(0, 1);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sales-finalize')));
    await tester.pumpAndSettle();
    expect(find.byType(BillScreen), findsOneWidget);
    expect(app.bills, hasLength(bills + 1));
  });

  testWidgets('sale bill: entering more than the stock is refused at Add Item',
      (tester) async {
    final app = await pump(tester, (_) => const SalesEntryScreen());
    final left = app.sellableQty('p1', SaleType.bag).floor();
    await tester.tap(find.byKey(const ValueKey('sales-next-product')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('picker-search')), 'milk');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('picker-option-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('sale-entry-qty')), '${left + 2}');
    await tester.tap(find.byKey(const ValueKey('sale-add-item')));
    await tester.pumpAndSettle();
    expect(app.cart, isEmpty);
    expect(find.textContaining('Only $left bags in stock'), findsOneWidget);
  });

  testWidgets('product page (QR): no stock → no way to add it',
      (tester) async {
    late String empty;
    final app = await pump(
        tester, (app) => ProductDetailScreen(productId: empty),
        prep: (app) async => empty = await freshProduct(app, name: 'Empty Feed'));
    expect(find.byKey(const ValueKey('product-out-of-stock')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('product-add-bag')));
    await tester.tap(find.byKey(const ValueKey('product-add-kg')));
    await tester.pumpAndSettle();
    expect(find.textContaining('किती'), findsNothing, reason: 'no qty sheet');
    expect(app.cart, isEmpty);
  });

  testWidgets('product page (QR): cannot add more bags than in stock',
      (tester) async {
    final app = await pump(tester, (_) => const ProductDetailScreen(productId: 'p1'));
    final left = app.sellableQty('p1', SaleType.bag).floor();
    await tester.tap(find.byKey(const ValueKey('product-add-bag')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '${left + 3}');
    await tester.tap(find.textContaining('Add to bill'));
    await tester.pumpAndSettle();
    expect(app.cart, isEmpty);
    expect(find.textContaining('Only $left bags in stock'), findsOneWidget);
  });
}
