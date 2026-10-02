// The one-screen New Sale Bill: Customer → Cash/Credit → Product → Qty →
// Rate → Amount → + Add Item → Total → Finalize, the dedicated "New Sale
// Bill" buttons (always a fresh bill), and the after-sale actions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/models/app_settings.dart';
import 'package:pend_point/models/bill.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/models/party.dart';
import 'package:pend_point/services/sms_service.dart';
import 'package:pend_point/services/whatsapp_service.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/ui/root_shell.dart';
import 'package:pend_point/ui/screens/bill_screen.dart';
import 'package:pend_point/ui/screens/home_screen.dart';
import 'package:pend_point/ui/screens/returns_screen.dart';
import 'package:pend_point/ui/screens/sales_entry_screen.dart';
import 'package:pend_point/ui/screens/sell_screen.dart';
import 'package:pend_point/utils/formatters.dart';
import 'package:pend_point/utils/lang.dart';
import 'package:pend_point/utils/theme.dart';

import 'test_support.dart';

Future<AppState> _pump(WidgetTester tester, Widget home,
    {AppLang lang = AppLang.both,
    Size size = const Size(360, 1400),
    Future<void> Function(AppState)? prep}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final app = (await tester.runAsync(bootedApp))!;
  await tester.runAsync(() => app.updateSettings((s) => s.lang = lang));
  if (prep != null) await tester.runAsync(() => prep(app));
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: app,
    child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
  ));
  await tester.pumpAndSettle();
  return app;
}

String _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

/// Opens a search combo, checks the list shows before typing, then types
/// [query] and picks the first match.
Future<void> _pick(WidgetTester tester, String field, String query) async {
  await tester.ensureVisible(find.byKey(ValueKey(field)));
  await tester.tap(find.byKey(ValueKey(field)));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('picker-option-0')), findsOneWidget);
  await tester.enterText(find.byKey(const ValueKey('picker-search')), query);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('picker-option-0')));
  await tester.pumpAndSettle();
}

/// Product → qty (→ rate) → + Add Item, through the screen.
Future<void> _addItem(WidgetTester tester, String product, String qty,
    {String? rate}) async {
  await _pick(tester, 'sales-next-product', product);
  await tester.enterText(find.byKey(const ValueKey('sale-entry-qty')), qty);
  if (rate != null) {
    await tester.enterText(find.byKey(const ValueKey('sale-entry-rate')), rate);
  }
  await tester.pump();
  await tester.ensureVisible(find.byKey(const ValueKey('sale-add-item')));
  await tester.tap(find.byKey(const ValueKey('sale-add-item')));
  await tester.pumpAndSettle();
}

Future<void> _finalize(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('sales-finalize')));
  await tester.pumpAndSettle();
}

void _expectEmptyScreen(WidgetTester tester, AppState app) {
  expect(find.byType(SalesEntryScreen), findsOneWidget);
  expect(app.cart, isEmpty);
  expect(app.cartCustomerId, isNull);
  expect(app.payments, isEmpty);
  expect(app.currentDraftId, isNull);
  expect(find.byKey(const ValueKey('sales-row-0')), findsNothing);
  expect(find.byKey(const ValueKey('sale-entry-qty')), findsNothing);
  expect(find.byKey(const ValueKey('sales-draft-banner')), findsNothing);
  expect(
      tester.widget<Text>(find.byKey(const ValueKey('sales-grand-total'))).data,
      '₹0');
}

void main() {
  tearDown(() => appLang = AppLang.both);

  group('customer search', () {
    test('2-5. code first, then mobile, then name', () async {
      final app = await bootedApp();
      final parties = app.salesParties;
      expect(searchParties(parties, '').length, parties.length,
          reason: 'the whole list shows before typing');
      expect(searchParties(parties, '2').first.id, 'c2'); // exact code
      expect(searchParties(parties, '90280').first.id, 'c2'); // mobile
      expect(searchParties(parties, 'सुनिल').first.id, 'c2'); // name
      expect(searchParties(parties, 'रमेश').first.id, 'c1');
    });

    testWidgets('combo opens with the list; picking shows name + code',
        (tester) async {
      final app = await _pump(tester, const SalesEntryScreen());
      await _pick(tester, 'sales-party', '98220');
      expect(app.cartCustomerId, 'c1');
      expect(find.text('रमेश पाटील'), findsOneWidget);
      final info = tester
          .widget<Text>(find.byKey(const ValueKey('sale-customer-info')))
          .data!;
      expect(info, contains('1'));
      expect(info, contains('98220 11223'));
      // Walk-in drops the customer again.
      await tester.tap(find.byKey(const ValueKey('sale-walkin')));
      await tester.pumpAndSettle();
      expect(app.cartCustomerId, isNull);
    });
  });

  group('product search', () {
    testWidgets('9-13. list on open; name, code, brand filter, All Brands',
        (tester) async {
      await _pump(tester, const SalesEntryScreen());
      Future<List<String>> options(String query) async {
        await tester.tap(find.byKey(const ValueKey('sales-next-product')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('picker-option-0')), findsOneWidget);
        await tester.enterText(
            find.byKey(const ValueKey('picker-search')), query);
        await tester.pumpAndSettle();
        final texts = [
          for (final e in find
              .descendant(
                  of: find.byType(ListTile), matching: find.byType(Text))
              .evaluate())
            (e.widget as Text).data ?? ''
        ];
        await tester.tapAt(const Offset(10, 10)); // close
        await tester.pumpAndSettle();
        return texts;
      }

      expect((await options('milk')).join(), contains('Milk Booster'));
      expect((await options('PEND-P3')).join(), contains('Kargil Gold'));
      expect(
          (await options('PEND-P3')).join(), isNot(contains('Milk Booster')));

      // Brand: only that brand's products.
      await tester.tap(find.byKey(const ValueKey('sales-brand-filter')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('picker-search')), 'Kargil');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-option-0')).last);
      await tester.pumpAndSettle();
      final kargil = (await options('')).join();
      expect(kargil, contains('Kargil Gold'));
      expect(kargil, isNot(contains('Milk Booster')));

      // All Brands again (×).
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('sales-brand-filter')),
          matching: find.byIcon(Icons.close_rounded)));
      await tester.pumpAndSettle();
      expect(find.text(allBrandsLabel()), findsOneWidget);
      expect((await options('')).join(), contains('Milk Booster'));
    });
  });

  group('item entry', () {
    testWidgets(
        '14-21. qty × master rate = amount; amount → rate; add, remove, total',
        (tester) async {
      final app = await _pump(tester, const SalesEntryScreen());
      final price = app.productOf('p1')!.fullBagPrice;
      await _pick(tester, 'sales-next-product', 'milk');
      // 7. focus lands on the quantity, prefilled with 1.
      expect(_field(tester, 'sale-entry-qty'), '1');
      expect(_field(tester, 'sale-entry-rate'), price.toStringAsFixed(0));
      expect(_field(tester, 'sale-entry-amount'), price.toStringAsFixed(0));

      await tester.enterText(find.byKey(const ValueKey('sale-entry-qty')), '2');
      await tester.pump();
      expect(
          _field(tester, 'sale-entry-amount'), (2 * price).toStringAsFixed(0));

      // 9. Amount typed directly → the rate follows (bill-only).
      await tester.enterText(find.byKey(const ValueKey('sale-entry-amount')),
          '${2 * price - 100}');
      await tester.pump();
      expect(
          _field(tester, 'sale-entry-rate'), (price - 50).toStringAsFixed(0));
      await tester.tap(find.byKey(const ValueKey('sale-add-item')));
      await tester.pumpAndSettle();
      expect(app.cart.single.rate, price - 50);
      expect(app.cart.single.catalogRate, price);
      expect(app.productOf('p1')!.fullBagPrice, price, reason: 'master kept');
      expect(
          find.byKey(const ValueKey('sales-row-0-bill-rate')), findsOneWidget);
      // The entry is empty again, ready for the next product.
      expect(find.byKey(const ValueKey('sale-entry-qty')), findsNothing);

      await _addItem(tester, 'kargil', '1');
      await _addItem(tester, 'PEND-P2', '1');
      expect(app.cart, hasLength(3));
      final total = app.cart.fold(0.0, (s, l) => s + l.lineTotal);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('sales-grand-total')))
              .data,
          money(total));

      final removed = app.cart[1].lineTotal;
      await tester.tap(find.byKey(const ValueKey('sales-row-1-remove')));
      await tester.pumpAndSettle();
      expect(app.cart, hasLength(2));
      expect(app.cartTotal, total - removed);

      // Tapping an item brings it back into the entry to change it.
      await tester.tap(find.byKey(const ValueKey('sales-row-0')));
      await tester.pumpAndSettle();
      expect(app.cart, hasLength(1));
      expect(_field(tester, 'sale-entry-qty'), '2');
      await tester.enterText(find.byKey(const ValueKey('sale-entry-qty')), '3');
      await tester.tap(find.byKey(const ValueKey('sale-add-item')));
      await tester.pumpAndSettle();
      expect(app.cart.where((l) => l.productId == 'p1').single.qty, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('invalid quantity / rate is refused with a reason',
        (tester) async {
      final app = await _pump(tester, const SalesEntryScreen());
      await _pick(tester, 'sales-next-product', 'milk');
      await tester.enterText(find.byKey(const ValueKey('sale-entry-qty')), '0');
      await tester.tap(find.byKey(const ValueKey('sale-add-item')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sale-entry-error')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('sale-entry-qty')), '1');
      await tester.enterText(
          find.byKey(const ValueKey('sale-entry-rate')), '0');
      await tester.tap(find.byKey(const ValueKey('sale-add-item')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sale-entry-error')), findsOneWidget);
      expect(app.cart, isEmpty);
    });

    testWidgets('an item filled in but not added is included on Finalize',
        (tester) async {
      final app = await _pump(tester, const HomeScreen());
      await tester.tap(find.byKey(const ValueKey('home-new-bill')));
      await tester.pumpAndSettle();
      await _pick(tester, 'sales-next-product', 'milk');
      await tester.enterText(find.byKey(const ValueKey('sale-entry-qty')), '2');
      await _finalize(tester);
      expect(find.byType(BillScreen), findsOneWidget);
      expect(app.bills.first.items.fold(0.0, (s, i) => s + i.qty), 2);
    });
  });

  group('payment', () {
    testWidgets('6. cash sale (walk-in)', (tester) async {
      final app = await _pump(tester, const HomeScreen());
      await tester.tap(find.byKey(const ValueKey('home-new-bill')));
      await tester.pumpAndSettle();
      await _addItem(tester, 'milk', '1');
      final total = app.cartTotal;
      await _finalize(tester);
      final bill = app.bills.first;
      expect(bill.customerId, isNull);
      expect(bill.payments.map((p) => (p.mode, p.amount)),
          [(PayMode.cash, total)]);
    });

    testWidgets('7-8. credit needs a customer; then saves to khata',
        (tester) async {
      final app = await _pump(tester, const HomeScreen());
      await tester.tap(find.byKey(const ValueKey('home-new-bill')));
      await tester.pumpAndSettle();
      await _addItem(tester, 'milk', '1');
      await tester.tap(find.byKey(const ValueKey('sale-pay-credit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sale-credit-needs-customer')),
          findsOneWidget);
      final bills = app.bills.length;
      await _finalize(tester);
      expect(find.byType(BillScreen), findsNothing);
      expect(app.bills, hasLength(bills), reason: 'no credit without customer');

      final before = app.customers.firstWhere((c) => c.id == 'c1').outstanding;
      await _pick(tester, 'sales-party', 'रमेश');
      expect(find.byKey(const ValueKey('sale-credit-needs-customer')),
          findsNothing);
      final total = app.cartTotal;
      await _finalize(tester);
      final bill = app.bills.first;
      expect(bill.customerId, 'c1');
      expect(bill.creditAmount, total);
      expect(app.customers.firstWhere((c) => c.id == 'c1').outstanding,
          before + total);
    });

    testWidgets('29. split payment only when asked; cash + credit saved',
        (tester) async {
      final app = await _pump(tester, const HomeScreen());
      await tester.tap(find.byKey(const ValueKey('home-new-bill')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pay-add')), findsNothing);
      await _pick(tester, 'sales-party', 'रमेश');
      await _addItem(tester, 'milk', '2');
      final total = app.cartTotal;
      await tester.tap(find.byKey(const ValueKey('sale-split')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pay-row-1-amount')), findsOneWidget);
      app.setPayment(1, mode: PayMode.credit);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('pay-row-1-amount')), '500');
      await tester.pumpAndSettle();
      // Adding an item keeps the split summing to the new total.
      await _addItem(tester, 'kargil', '1');
      expect(app.payments.fold(0.0, (s, p) => s + p.amount), app.cartTotal);
      await _finalize(tester);
      final bill = app.bills.first;
      expect(bill.creditAmount, 500);
      expect(bill.payments.firstWhere((p) => p.mode == PayMode.cash).amount,
          app.bills.first.total - 500);
      expect(bill.total, greaterThan(total));
    });
  });

  group('New Sale Bill buttons — always a fresh bill', () {
    /// A finished bill, a draft with credit + a bill-only rate, and an
    /// unfinished bill on screen — none of it may leak into New Sale Bill.
    Future<void> leaveTracesBehind(AppState app) async {
      app.addToCart('p1', SaleType.bag, 1);
      await app.finalizeSale();
      app.setCartCustomer('c1');
      app.addToCart('p1', SaleType.bag, 2);
      app.setLineRate(0, app.cart[0].catalogRate - 30);
      app.setSaleMode(PayMode.credit);
      await app.saveDraft();
      app.startNewBill();
      app.setCartCustomer('c2');
      app.addToCart('p3', SaleType.bag, 1);
      await app.saveDraft();
      app.startNewBill();
    }

    for (final (name, home, key) in [
      ('Home', const HomeScreen() as Widget, 'home-new-bill'),
      ('Sales tab', const SellScreen() as Widget, 'sell-bill-entry'),
      ('Bills screen', const ReturnsScreen() as Widget, 'bills-new-bill'),
    ]) {
      testWidgets('1-12. $name → New Sale Bill → empty; drafts untouched',
          (tester) async {
        final app = await _pump(tester, home, prep: leaveTracesBehind);
        final drafts = [for (final d in app.drafts) (d.id, d.version, d.total)];
        final bills = [for (final b in app.bills) (b.id, b.total, b.status)];
        final price = app.productOf('p1')!.fullBagPrice;

        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        _expectEmptyScreen(tester, app);
        expect(app.saleMode, PayMode.cash, reason: 'Cash by default');

        expect(
            [for (final d in app.drafts) (d.id, d.version, d.total)], drafts);
        expect([for (final b in app.bills) (b.id, b.total, b.status)], bills);
        expect(app.productOf('p1')!.fullBagPrice, price);
        // A product picked now starts at the master price, not the
        // earlier bill-only rate.
        await _pick(tester, 'sales-next-product', 'milk');
        expect(_field(tester, 'sale-entry-rate'), price.toStringAsFixed(0));
      });
    }

    testWidgets('14. after a finalized bill: New Sale Bill → empty',
        (tester) async {
      final app = await _pump(tester, const HomeScreen());
      await tester.tap(find.byKey(const ValueKey('home-new-bill')));
      await tester.pumpAndSettle();
      await _pick(tester, 'sales-party', 'रमेश');
      await _addItem(tester, 'milk', '1');
      await _finalize(tester);
      final bill = app.bills.first;
      await tester.ensureVisible(find.byKey(const ValueKey('bill-new-sale')));
      await tester.tap(find.byKey(const ValueKey('bill-new-sale')));
      await tester.pumpAndSettle();
      _expectEmptyScreen(tester, app);
      expect(app.bills.first.id, bill.id);
      expect(app.bills.first.status, BillStatus.finalized);
    });
  });

  group('after the sale', () {
    late String billId;
    Future<void> sale(AppState app) async {
      app.setCartCustomer('c1');
      app.addToCart('p1', SaleType.bag, 2);
      app.addSplitPayment();
      app.setPayment(1, mode: PayMode.credit);
      app.setPayment(1, amount: 100);
      billId = (await app.finalizeSale()).bill!.id;
    }

    testWidgets('25-28. Print / WhatsApp / SMS / Share + Bill Link off',
        (tester) async {
      await _pump(tester, const SizedBox(), prep: sale);
      final app = Provider.of<AppState>(tester.element(find.byType(SizedBox)),
          listen: false);
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
              theme: buildTheme(Brightness.light),
              home: BillScreen(billId: billId, justSaved: true))));
      await tester.pumpAndSettle();
      for (final k in [
        'bill-new-sale',
        'bill-print',
        'bill-whatsapp',
        'bill-sms',
        'bill-share'
      ]) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      // No secure hosted bill page → the link button is shown but off.
      final link = tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('bill-link')));
      expect(link.onPressed, isNull);

      // Print without a paired printer says what to do.
      await tester.ensureVisible(find.byKey(const ValueKey('bill-print')));
      await tester.tap(find.byKey(const ValueKey('bill-print')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pair a printer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('WhatsApp / SMS carry the bill, number and payment type', () async {
      final app = await bootedApp();
      await sale(app);
      final bill = app.bills.firstWhere((b) => b.id == billId);
      final msg = WhatsAppService.billMessage(
          shopName: 'Shop', bill: bill, productLabel: (id) => id);
      expect(msg, contains('#${bill.billNumber}'));
      expect(msg, contains('रमेश पाटील'));
      expect(msg, contains('Cash'));
      expect(msg, contains('Credit'));
      expect(msg, contains(money(bill.total)));

      final wa = WhatsAppService.whatsAppUri('98220 11223', msg);
      expect(wa.host, 'wa.me');
      expect(wa.path, '/919822011223');
      expect(wa.queryParameters['text'], msg);

      final sms = SmsService.smsUri('98220 11223', msg)!;
      expect(sms.scheme, 'sms');
      expect(sms.toString(), startsWith('sms:+919822011223?body='));
      expect(Uri.decodeComponent(sms.query.substring('body='.length)), msg);
      expect(SmsService.smsUri('', msg), isNull);
    });

    testWidgets('SMS with no customer mobile says so (never silent)',
        (tester) async {
      late String id;
      final app = await _pump(tester, const SizedBox(), prep: (app) async {
        app.addToCart('p1', SaleType.bag, 1);
        id = (await app.finalizeSale()).bill!.id; // walk-in: no mobile
      });
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
              theme: buildTheme(Brightness.light),
              home: BillScreen(billId: id, justSaved: true))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('bill-sms')));
      await tester.tap(find.byKey(const ValueKey('bill-sms')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Customer mobile number is not available'),
          findsOneWidget);
    });
  });

  group('30-33. 360px in every language', () {
    for (final lang in AppLang.values) {
      testWidgets('[${lang.name}] sale screen with entry, items, split',
          (tester) async {
        final app = await _pump(tester, const SalesEntryScreen(),
            lang: lang, size: const Size(360, 2400));
        await _pick(tester, 'sales-party', 'रमेश');
        await _addItem(tester, 'milk', '1');
        await _pick(tester, 'sales-next-product', 'kargil');
        await tester.tap(find.byKey(const ValueKey('sale-pay-credit')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'no overflow at 360px');
        final title = switch (lang) {
          AppLang.mr => 'नवीन विक्री बिल',
          AppLang.en => 'New Sale Bill',
          AppLang.both => 'नवीन विक्री बिल',
        };
        expect(find.text(title), findsOneWidget);
        if (lang == AppLang.mr) expect(find.text('Cash'), findsNothing);
        if (lang == AppLang.en) {
          expect(find.textContaining('रोख'), findsNothing);
        }
        await tester.tap(find.byKey(const ValueKey('sale-split')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(app.isSplitPayment, isTrue);

        app.closeBill();
        await tester.pumpWidget(ChangeNotifierProvider.value(
            value: app,
            child: MaterialApp(
                theme: buildTheme(Brightness.light), home: const RootShell())));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Home at 360px');
      });
    }
  });
}
