// Selling to a customer who already owes money: the previous due shows on
// the sale screen, and — when the customer pays it now — it can be added
// to the bill. The old-due money is a khata payment (same commit), never a
// sale: bill totals, payments and reports stay this bill's items only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/models/app_settings.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/services/whatsapp_service.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/state/report_query.dart';
import 'package:pend_point/ui/screens/bill_screen.dart';
import 'package:pend_point/ui/screens/sales_entry_screen.dart';
import 'package:pend_point/utils/formatters.dart';
import 'package:pend_point/utils/lang.dart';
import 'package:pend_point/utils/theme.dart';

import 'test_support.dart';

double _due(AppState app, [String id = 'c1']) =>
    app.customers.firstWhere((c) => c.id == id).outstanding;

double _revenue(AppState app) => buildReport(
        bills: app.finalBills,
        products: app.products,
        filter: ReportFilter.preset(DateRangePresetKind.last30))
    .revenue;

/// c1 (owes ₹2,380) buys one bag of p1.
void _sellToC1(AppState app) {
  app.setCartCustomer('c1');
  app.addToCart('p1', SaleType.bag, 1);
}

void main() {
  tearDown(() => appLang = AppLang.both);

  group('logic', () {
    test('full previous due paid with a cash bill', () async {
      final repo = RecordingRepository();
      final app = await bootedApp(repo);
      final before = _due(app);
      final revenue = _revenue(app);
      _sellToC1(app);
      expect(app.cartPreviousDue, before);
      app.setDueCollect(before);
      final bill = app.cartTotal;
      expect(app.cartPayable, bill + before);

      final res = await app.finalizeSale();
      expect(res.ok, isTrue, reason: res.error);
      final b = res.bill!;
      expect(b.total, bill, reason: 'the sale is only this bill');
      expect(b.payments.map((p) => (p.mode, p.amount)), [(PayMode.cash, bill)]);
      expect(b.previousDue, before);
      expect(b.dueCollected, before);
      expect(b.balanceAfter, 0);
      expect(_due(app), 0);
      final paid = app.customers
          .firstWhere((c) => c.id == 'c1')
          .ledger
          .where((e) => e.billId == b.id);
      expect(paid.single.isRepayment, isTrue);
      expect(paid.single.amount, before);
      // One atomic commit: the sale and the khata payment together.
      expect(repo.commits, hasLength(1));
      expect(repo.commits.single.ledger.single.outstandingDelta, -before);
      expect(_revenue(app), closeTo(revenue + bill, 0.001),
          reason: 'reports count the bill, not the old due');
    });

    test('part of the due; capped at what is owed; not ticked = unchanged',
        () async {
      final app = await bootedApp();
      final before = _due(app);
      _sellToC1(app);
      app.setDueCollect(99999);
      expect(app.cartDueCollect, before, reason: 'never more than owed');
      app.setDueCollect(1000);
      final b = (await app.finalizeSale()).bill!;
      expect(b.dueCollected, 1000);
      expect(_due(app), before - 1000);
      expect(b.balanceAfter, before - 1000);

      // Not added: the previous due is printed, nothing is collected.
      _sellToC1(app);
      final b2 = (await app.finalizeSale()).bill!;
      expect(b2.previousDue, before - 1000);
      expect(b2.dueCollected, 0);
      expect(_due(app), before - 1000);
    });

    test('credit-only bill cannot collect the old due; nothing saved',
        () async {
      final app = await bootedApp();
      final before = _due(app);
      final bills = app.bills.length;
      _sellToC1(app);
      app.setSaleMode(PayMode.credit);
      app.setDueCollect(500);
      final res = await app.finalizeSale();
      expect(res.ok, isFalse);
      expect(res.error, contains('Cash or UPI'));
      expect(app.bills, hasLength(bills));
      expect(_due(app), before);
    });

    test('split: part of this bill on credit + old due paid', () async {
      final app = await bootedApp();
      final before = _due(app);
      _sellToC1(app);
      app.addSplitPayment();
      app.setPayment(1, mode: PayMode.credit);
      app.setPayment(1, amount: 400);
      app.setDueCollect(1000);
      final b = (await app.finalizeSale()).bill!;
      expect(b.creditAmount, 400);
      expect(_due(app), before - 1000 + 400);
      expect(b.balanceAfter, before - 1000 + 400);
    });

    test('changing the customer or starting a new bill clears it', () async {
      final app = await bootedApp();
      _sellToC1(app);
      app.setDueCollect(500);
      app.setCartCustomer('c3');
      expect(app.cartDueCollect, 0);
      app.setDueCollect(100);
      app.startNewBill();
      expect(app.cartDueCollect, 0);
      expect(app.cartPayable, 0);
    });

    test('void puts the old due back; edit keeps it as recorded', () async {
      final app = await bootedApp();
      final before = _due(app);
      _sellToC1(app);
      app.setDueCollect(1000);
      final b = (await app.finalizeSale()).bill!;
      expect(_due(app), before - 1000);

      // Edit (revision): the collection is not repeated or lost.
      expect(app.beginEditBill(b.id), isNull);
      app.setLineQty(0, 2);
      app.fitPayments();
      final rev = (await app.finalizeSale()).bill!;
      expect(rev.dueCollected, 1000);
      expect(_due(app), before - 1000);

      expect(await app.voidBill(rev.id), isNull);
      expect(_due(app), before);
    });

    test('a draft remembers it', () async {
      final app = await bootedApp();
      _sellToC1(app);
      app.setDueCollect(700);
      final d = (await app.saveDraft()).draft!;
      expect(d.dueCollect, 700);
      app.startNewBill();
      app.openDraft(d.id);
      expect(app.cartDueCollect, 700);
    });

    test('WhatsApp / SMS message shows previous due and balance', () async {
      final app = await bootedApp();
      _sellToC1(app);
      app.setDueCollect(1000);
      final b = (await app.finalizeSale()).bill!;
      final m = WhatsAppService.billMessage(
          shopName: 'Shop', bill: b, productLabel: (id) => id);
      expect(m, contains('Previous due: ${money(b.previousDue)}'));
      expect(m, contains('Old due paid: -${money(1000)}'));
      expect(m, contains('Balance now: ${money(b.balanceAfter)}'));
    });
  });

  group('sale screen', () {
    Future<AppState> pump(WidgetTester tester, Widget home,
        {AppLang lang = AppLang.both, void Function(AppState)? prep}) async {
      tester.view.physicalSize = const Size(720, 3200); // 360 wide
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = (await tester.runAsync(bootedApp))!;
      await tester.runAsync(() => app.updateSettings((s) => s.lang = lang));
      prep?.call(app);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
      ));
      await tester.pumpAndSettle();
      return app;
    }

    String text(WidgetTester tester, String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;

    testWidgets('shows the due; tick adds it; bill screen shows it',
        (tester) async {
      final app = await pump(tester, const SalesEntryScreen(), prep: _sellToC1);
      final due = _due(app);
      expect(text(tester, 'sale-prev-due-amount'), money(due));
      final bill = app.cartTotal;
      expect(text(tester, 'sales-grand-total'), money(bill));

      await tester.tap(find.byKey(const ValueKey('sale-add-due')));
      await tester.pumpAndSettle();
      expect(text(tester, 'sales-grand-total'), money(bill + due));
      expect(find.textContaining('Total payable'), findsWidgets);

      // Paying only part of it.
      await tester.enterText(
          find.byKey(const ValueKey('sale-due-amount')), '1000');
      await tester.pumpAndSettle();
      expect(text(tester, 'sales-grand-total'), money(bill + 1000));

      await tester.tap(find.byKey(const ValueKey('sales-finalize')));
      await tester.pumpAndSettle();
      expect(find.byType(BillScreen), findsOneWidget);
      expect(find.textContaining('Old due paid'), findsWidgets);
      expect(find.textContaining('Balance now'), findsOneWidget);
      expect(_due(app), due - 1000);
      expect(tester.takeException(), isNull);
    });

    testWidgets('credit + added due warns; walk-in shows no due card',
        (tester) async {
      final app = await pump(tester, const SalesEntryScreen(), prep: _sellToC1);
      await tester.tap(find.byKey(const ValueKey('sale-add-due')));
      await tester.tap(find.byKey(const ValueKey('sale-pay-credit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sale-due-needs-cash')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sale-walkin')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sale-prev-due')), findsNothing);
      expect(app.cartDueCollect, 0);
    });

    for (final lang in AppLang.values) {
      testWidgets('[${lang.name}] due card fits 360px', (tester) async {
        await pump(tester, const SalesEntryScreen(),
            lang: lang, prep: _sellToC1);
        await tester.tap(find.byKey(const ValueKey('sale-add-due')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (lang == AppLang.en) {
          expect(find.textContaining('मागील'), findsNothing);
        }
        if (lang == AppLang.mr) {
          expect(find.textContaining('Previous due'), findsNothing);
        }
      });
    }
  });
}
