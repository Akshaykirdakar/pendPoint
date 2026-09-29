// Split payment at Checkout: the shopkeeper types one amount and the other
// row is worked out, so the rows always add up to the bill and never go
// over it. Amounts are exact to the paisa.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/models/app_settings.dart';
import 'package:pend_point/models/bill.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/state/payment_split.dart';
import 'package:pend_point/state/purchase_draft.dart';
import 'package:pend_point/ui/screens/checkout_screen.dart';
import 'package:pend_point/utils/lang.dart';
import 'package:pend_point/utils/theme.dart';

import 'test_support.dart';

List<(PayMode, double)> _rows(List<Payment> ps) =>
    [for (final p in ps) (p.mode, p.amount)];

const _cash = PayMode.cash, _upi = PayMode.upi, _credit = PayMode.credit;

/// A cart worth exactly ₹1,800 (with stock to sell), party c1 for credit.
Future<AppState> _cart1800() async {
  final app = await bootedApp();
  final id = await freshProduct(app, name: 'Pay Test', sellPrice: 900);
  final res =
      await app.savePurchase(supplierId: app.suppliers.first.id, lines: [
    PurchaseLineInput(
        productId: id, bags: 10, rate: 700, batchNo: 'P1', expiry: inDays(90))
  ]);
  expect(res.ok, isTrue, reason: res.error);
  app.addToCart(id, SaleType.bag, 2);
  app.setCartCustomer('c1');
  expect(app.cartTotal, 1800);
  app.payments
    ..clear()
    ..add(const Payment(PayMode.cash, 1800));
  return app;
}

void main() {
  group('PaymentSplit (₹1,800 due)', () {
    const due = 1800.0;

    test('1: single cash row = full amount', () {
      final ps = PaymentSplit.fit([const Payment(_cash, 0)], due);
      expect(_rows(ps), [(_cash, 1800.0)]);
      expect(PaymentSplit.isComplete(ps, due), isTrue);
    });

    test('5: Cash 1800 + add Credit, type ₹5 → Cash 1795', () {
      var ps = PaymentSplit.addRow([const Payment(_cash, 1800)], due);
      expect(_rows(ps), [(_cash, 1800.0), (_credit, 0.0)]);
      ps = PaymentSplit.setAmount(ps, due, 1, 5);
      expect(_rows(ps), [(_cash, 1795.0), (_credit, 5.0)]);
      expect(PaymentSplit.entered(ps), 1800);
      expect(PaymentSplit.excess(ps, due), 0);
    });

    test('2+6: Credit ₹500 typed → Cash ₹1,300 (the typed row is kept)', () {
      var ps = PaymentSplit.addRow([const Payment(_cash, 1800)], due);
      ps = PaymentSplit.setAmount(ps, due, 1, 500);
      expect(_rows(ps), [(_cash, 1300.0), (_credit, 500.0)]);
    });

    test('3: Cash + UPI', () {
      var ps =
          PaymentSplit.setAmount([const Payment(_cash, 1800)], due, 0, 1000);
      expect(PaymentSplit.remaining(ps, due), 800);
      ps = PaymentSplit.setMode(PaymentSplit.addRow(ps, due), due, 1, _upi);
      expect(_rows(ps), [(_cash, 1000.0), (_upi, 800.0)]);
      ps = PaymentSplit.setAmount(ps, due, 1, 500);
      expect(_rows(ps), [(_cash, 1300.0), (_upi, 500.0)]);
    });

    test(
        '4: Cash + UPI + Credit adds up; typing cash gives the rest to the last row',
        () {
      var ps = [const Payment(_cash, 1000), const Payment(_upi, 500)];
      ps = PaymentSplit.addRow(ps, due);
      expect(_rows(ps), [(_cash, 1000.0), (_upi, 500.0), (_credit, 300.0)]);
      expect(PaymentSplit.isComplete(ps, due), isTrue);
      ps = PaymentSplit.setAmount(ps, due, 0, 900);
      expect(_rows(ps), [(_cash, 900.0), (_upi, 500.0), (_credit, 400.0)]);
    });

    test('7: removing Credit gives its amount back to Cash', () {
      final ps = PaymentSplit.removeRow(
          [const Payment(_cash, 1300), const Payment(_credit, 500)], due, 1);
      expect(_rows(ps), [(_cash, 1800.0)]);
    });

    test('8: total can never exceed the bill', () {
      var ps = [const Payment(_cash, 1800), const Payment(_credit, 0)];
      ps = PaymentSplit.setAmount(ps, due, 1, 5000); // more than the bill
      expect(_rows(ps), [(_cash, 0.0), (_credit, 1800.0)]);
      // Three rows: fixed rows are trimmed so the typed one still fits.
      var three = [
        const Payment(_cash, 1000),
        const Payment(_upi, 700),
        const Payment(_credit, 100)
      ];
      three = PaymentSplit.setAmount(three, due, 2, 1500);
      expect(PaymentSplit.entered(three), 1800);
      expect(three[2].amount, 1500);
      expect(PaymentSplit.excess(three, due), 0);
    });

    test('no duplicate modes: picking a used mode merges the rows', () {
      final ps = PaymentSplit.setMode(
          [const Payment(_cash, 500), const Payment(_upi, 300)], 800, 1, _cash);
      expect(_rows(ps), [(_cash, 800.0)]);
      expect(
          PaymentSplit.freeModes([const Payment(_cash, 1)]), [_upi, _credit]);
      final all = [
        const Payment(_cash, 1),
        const Payment(_upi, 1),
        const Payment(_credit, 1)
      ];
      expect(PaymentSplit.addRow(all, 3), same(all)); // nothing left to add
    });

    test('rounding: paise-exact, no float drift', () {
      // ₹537.50 bill; ₹0.10 + ₹0.20 style values that drift in doubles.
      var ps = PaymentSplit.addRow([const Payment(_cash, 537.5)], 537.5);
      ps = PaymentSplit.setAmount(ps, 537.5, 1, 0.3);
      expect(ps[0].amount, 537.2);
      expect(PaymentSplit.isComplete(ps, 537.5), isTrue);
      ps = PaymentSplit.setAmount(ps, 537.5, 1, 100.1);
      expect(ps[0].amount, 437.4);
      expect(PaymentSplit.entered(ps), 537.5);
    });
  });

  group('AppState save rules', () {
    test('9: exactly equal saves; 10: short payment is blocked with the rest',
        () async {
      final app = await _cart1800();
      app.addSplitPayment();
      app.setPayment(1, amount: 5);
      expect(_rows(app.payments), [(_cash, 1795.0), (_credit, 5.0)]);

      // Short: shop rules need the full bill covered (credit is how dues
      // are recorded), so saving is refused and says what is left.
      app.payments[0] = const Payment(_cash, 1495);
      final short = await app.finalizeSale();
      expect(short.ok, isFalse);
      expect(short.error, contains('300'));

      app.setPayment(1, amount: 5);
      final ok = await app.finalizeSale();
      expect(ok.ok, isTrue, reason: ok.error);
      expect(_rows(ok.bill!.payments), [(_cash, 1795.0), (_credit, 5.0)]);
      expect(ok.bill!.creditAmount, 5);
    });

    test('8: an over-allocated payment is never saved', () async {
      final app = await _cart1800();
      final before = app.bills.length;
      app.payments
        ..clear()
        ..addAll(const [Payment(_cash, 1800), Payment(_credit, 5)]);
      final res = await app.finalizeSale();
      expect(res.ok, isFalse);
      expect(res.error, contains('cannot exceed the bill total'));
      expect(app.bills.length, before);
    });

    test('11+12: editing a bill loads its split; recalculated after revision',
        () async {
      final app = await _cart1800();
      app.addSplitPayment();
      app.setPayment(1, amount: 500);
      final bill = (await app.finalizeSale()).bill!;
      expect(_rows(bill.payments), [(_cash, 1300.0), (_credit, 500.0)]);
      final creditBefore =
          app.customers.firstWhere((c) => c.id == 'c1').outstanding;

      expect(app.beginEditBill(bill.id), isNull);
      expect(_rows(app.payments), [(_cash, 1300.0), (_credit, 500.0)]);
      // Remove one bag → ₹900 due; the split is re-fitted (credit kept).
      app.setLineQty(0, 1);
      app.fitPayments();
      expect(_rows(app.payments), [(_cash, 400.0), (_credit, 500.0)]);
      app.setPayment(1, amount: 200);
      expect(_rows(app.payments), [(_cash, 700.0), (_credit, 200.0)]);
      final rev = (await app.finalizeSale()).bill!;
      expect(rev.revision, 1);
      expect(rev.total, 900);
      expect(_rows(rev.payments), [(_cash, 700.0), (_credit, 200.0)]);
      // Khata: old ₹500 reversed, new ₹200 applied — existing ledger logic.
      expect(app.customers.firstWhere((c) => c.id == 'c1').outstanding,
          creditBefore - 500 + 200);
    });

    test('15: a plain single-payment bill works as before', () async {
      final app = await _cart1800();
      final res = await app.finalizeSale();
      expect(res.ok, isTrue, reason: res.error);
      expect(_rows(res.bill!.payments), [(_cash, 1800.0)]);
    });
  });

  group('Checkout screen', () {
    Future<AppState> pump(WidgetTester tester, AppLang lang,
        {double width = 360}) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = (await tester.runAsync(_cart1800))!;
      app.settings.lang = lang;
      appLang = lang;
      addTearDown(() => appLang = AppLang.both);
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
              theme: buildTheme(Brightness.light),
              home: const CheckoutScreen())));
      await tester.pumpAndSettle();
      return app;
    }

    String text(WidgetTester t, String key) =>
        t
            .widget<Text>(find.descendant(
                of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
            .data ??
        '';

    testWidgets(
        '5+14: add Credit ₹5 → Cash ₹1,795 on screen, 360px, no overflow',
        (tester) async {
      final app = await pump(tester, AppLang.both);
      expect(text(tester, 'pay-status'), contains('पूर्ण रक्कम · Full Amount'));

      await tester.tap(find.byKey(const ValueKey('pay-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('pay-row-1-amount')), '5');
      await tester.pumpAndSettle();
      expect(_rows(app.payments), [(_cash, 1795.0), (_credit, 5.0)]);
      final cashField = tester
          .widget<TextField>(find.byKey(const ValueKey('pay-row-0-amount')));
      expect(cashField.controller!.text, '1795');
      expect(
          tester.widget<Text>(find.byKey(const ValueKey('pay-entered'))).data,
          '₹1,800 / ₹1,800');

      // Typing more than the bill is capped on the spot.
      await tester.enterText(
          find.byKey(const ValueKey('pay-row-1-amount')), '99999');
      await tester.pumpAndSettle();
      expect(_rows(app.payments), [(_cash, 0.0), (_credit, 1800.0)]);
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('pay-row-1-amount')))
              .controller!
              .text,
          '1800');

      // 7: remove the credit row → cash takes the full amount back.
      await tester.tap(find.byKey(const ValueKey('pay-row-1-remove')));
      await tester.pumpAndSettle();
      expect(_rows(app.payments), [(_cash, 1800.0)]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('13: labels follow the language — Marathi', (tester) async {
      await pump(tester, AppLang.mr);
      expect(text(tester, 'pay-status'), '✅ पूर्ण रक्कम');
    });

    testWidgets('13: labels follow the language — English', (tester) async {
      final app = await pump(tester, AppLang.en);
      expect(text(tester, 'pay-status'), '✅ Full Amount');
      app.setPayment(0, amount: 1500);
      await tester.pumpAndSettle();
      expect(text(tester, 'pay-status'), 'Remaining ₹300');
    });

    testWidgets('13: labels follow the language — Both', (tester) async {
      await pump(tester, AppLang.both);
      expect(text(tester, 'pay-status'), '✅ पूर्ण रक्कम · Full Amount');
    });

    testWidgets('8: Save is blocked if rows somehow exceed the bill',
        (tester) async {
      final app = await pump(tester, AppLang.en);
      final before = app.bills.length;
      app.payments.add(const Payment(_credit, 5)); // programmatic, no rebalance
      app.setCartCustomer('c1'); // notify
      await tester.pumpAndSettle();
      expect(text(tester, 'pay-status'),
          '❌ Payment amount cannot exceed the bill total.');
      final save = find.byKey(const ValueKey('checkout-save'));
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(app.bills.length, before);
    });
  });

  test('settings round-trip keeps font/theme defaults for old documents', () {
    final s = AppSettings.fromMap({'lang': 'mr'});
    expect(s.fontSize, AppFontSize.medium);
    expect(s.colorTheme, AppColorTheme.green);
  });
}
