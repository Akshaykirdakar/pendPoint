// Draft bills: a bill can be left unfinished, a New Bill is always empty,
// many drafts can exist at once, and only finalizing touches stock,
// payments, khata and reports.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/data/memory_repository.dart';
import 'package:pend_point/data/stock_commit.dart';
import 'package:pend_point/models/app_settings.dart';
import 'package:pend_point/models/bill.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/state/report_query.dart';
import 'package:pend_point/ui/screens/checkout_screen.dart';
import 'package:pend_point/ui/screens/draft_bills_screen.dart';
import 'package:pend_point/ui/screens/home_screen.dart';
import 'package:pend_point/ui/screens/returns_screen.dart';
import 'package:pend_point/ui/screens/sales_entry_screen.dart';
import 'package:pend_point/ui/screens/sell_screen.dart';
import 'package:pend_point/utils/lang.dart';
import 'package:pend_point/utils/theme.dart';

import 'test_support.dart';

/// Rejects every sale commit (as Firestore does when it can't commit) but
/// keeps drafts like the normal repository.
class _FailingSaleRepo extends InMemoryRepository {
  @override
  Future<void> commitStock(StockCommit commit) async =>
      throw const StockCommitException('network: sale not saved');
}

/// Everything a draft must NOT change.
typedef _Books = ({
  int bills,
  int logs,
  double revenue,
  String payments, // "cash=…,upi=…,credit=…" (comparable, unlike a Map)
  double credit,
  double outstanding,
  int ledger,
  int bags,
  double batchBags,
  double productPrice,
});

_Books _books(AppState app) {
  final report = buildReport(
      bills: app.finalBills,
      products: app.products,
      filter: ReportFilter.preset(DateRangePresetKind.last30));
  final c1 = app.customers.firstWhere((c) => c.id == 'c1');
  return (
    bills: app.bills.length,
    logs: app.logs.length,
    revenue: report.revenue,
    payments: [
      for (final e in report.paymentTotals.entries) '${e.key.name}=${e.value}'
    ].join(','),
    credit: report.paymentTotals[PayMode.credit] ?? 0,
    outstanding: c1.outstanding,
    ledger: c1.ledger.length,
    bags: app.stockOf('p1').bags,
    batchBags: app
        .batchesOf('p1')
        .fold(0.0, (s, b) => s + b.bagsAvailable + b.looseKgAvailable),
    productPrice: app.productOf('p1')!.fullBagPrice,
  );
}

/// Party c1, 2 bags of p1 at a bill-only rate ₹40 under the product
/// price, and a cash + credit split.
void _fillBill(AppState app) {
  app.setCartCustomer('c1');
  app.addToCart('p1', SaleType.bag, 2);
  app.setLineRate(0, app.cart[0].catalogRate - 40);
  app.addToCart('p2', SaleType.kg, 3.5);
  app.ensurePayments();
  app.addSplitPayment(); // cash + upi
  app.setPayment(1, mode: PayMode.credit);
  app.setPayment(1, amount: 5);
}

void _expectFresh(AppState app) {
  expect(app.cart, isEmpty);
  expect(app.cartCustomerId, isNull);
  expect(app.payments, isEmpty);
  expect(app.cartTotal, 0);
  expect(app.cartDiscount, 0);
  expect(app.currentDraftId, isNull);
  expect(app.editingBillId, isNull);
  expect(app.hasUnsavedBill, isFalse);
}

void main() {
  tearDown(() => appLang = AppLang.both);

  group('draft bill logic', () {
    test('1-3. new bill is empty; Save Draft keeps every field as D…',
        () async {
      final repo = RecordingRepository();
      final app = await bootedApp(repo);
      app.startNewBill();
      _expectFresh(app);

      _fillBill(app);
      expect(app.hasUnsavedBill, isTrue);
      final total = app.cartTotal;
      final r = await app.saveDraft();
      expect(r.ok, isTrue, reason: r.error);
      final d = r.draft!;
      expect(d.label, 'D1001');
      expect(d.customerId, 'c1');
      expect(d.lines, hasLength(2));
      expect(d.total, total);
      expect(d.payments.map((p) => (p.mode, p.amount)),
          [(PayMode.cash, total - 5), (PayMode.credit, 5)]);
      expect(app.drafts.single.id, d.id);
      expect(repo.drafts.keys, [d.id]);
      expect(app.currentDraftId, d.id);
      expect(app.cartDirty, isFalse);
      expect(repo.commits, isEmpty, reason: 'a draft commits nothing');
    });

    test('4-7. continue restores all fields; New Bill beside drafts is empty',
        () async {
      final app = await bootedApp();
      _fillBill(app);
      final lines = [
        for (final l in app.cart)
          (l.productId, l.saleType, l.qty, l.catalogRate, l.rate)
      ];
      final pays = [for (final p in app.payments) (p.mode, p.amount)];
      final a = (await app.saveDraft()).draft!;

      // Customer B: a completely fresh bill while Draft A exists.
      app.startNewBill();
      _expectFresh(app);
      expect(app.drafts, hasLength(1));
      app.setCartCustomer('c2');
      app.addToCart('p3', SaleType.bag, 1);
      final b = (await app.saveDraft()).draft!;
      app.startNewBill();
      _expectFresh(app);
      app.addToCart('p1', SaleType.bag, 1);
      final c = (await app.saveDraft()).draft!;
      app.startNewBill();
      _expectFresh(app);

      expect({a.label, b.label, c.label}, {'D1001', 'D1002', 'D1003'});
      expect(app.drafts, hasLength(3));

      expect(app.openDraft(a.id), isNull);
      expect(app.currentDraftId, a.id);
      expect(app.cartCustomerId, 'c1');
      expect([
        for (final l in app.cart)
          (l.productId, l.saleType, l.qty, l.catalogRate, l.rate)
      ], lines);
      expect([for (final p in app.payments) (p.mode, p.amount)], pays);
      expect(app.hasUnsavedBill, isFalse);
    });

    test('8-11, 13. drafts never touch stock, revenue, khata or payments',
        () async {
      final repo = RecordingRepository();
      final app = await bootedApp(repo);
      final before = _books(app);
      _fillBill(app);
      await app.saveDraft();
      app.setLineQty(0, 5);
      await app.saveDraft();
      app.startNewBill();
      app.addToCart('p1', SaleType.bag, 1);
      final second = (await app.saveDraft()).draft!;
      expect(_books(app), before);

      expect(await app.deleteDraft(second.id), isNull);
      expect(app.drafts, hasLength(1));
      expect(_books(app), before);
      expect(repo.commits, isEmpty);
    });

    test(
        '12. a bill-only rate stays on the draft and the bill, not the product',
        () async {
      final app = await bootedApp();
      final price = app.productOf('p1')!.fullBagPrice;
      _fillBill(app);
      final d = (await app.saveDraft()).draft!;
      expect(d.lines.first.rate, price - 40);
      expect(d.lines.first.catalogRate, price);
      expect(app.productOf('p1')!.fullBagPrice, price);

      // Deleted draft: the temporary price goes with it.
      app.startNewBill();
      await app.deleteDraft(d.id);
      app.addToCart('p1', SaleType.bag, 1);
      expect(app.cart.single.rate, price);
      app.closeBill();

      // Finalized draft: the bill keeps the bill rate, the product doesn't.
      _fillBill(app);
      final d2 = (await app.saveDraft()).draft!;
      app.startNewBill();
      app.openDraft(d2.id);
      final res = await app.finalizeSale();
      expect(res.ok, isTrue, reason: res.error);
      final item = res.bill!.items.firstWhere((i) => i.productId == 'p1');
      expect(item.rate, price - 40);
      expect(item.catalogRate, price);
      expect(app.productOf('p1')!.fullBagPrice, price);
    });

    test('15, 17, 18, 21. finalize = the normal sale; draft removed; bill no.',
        () async {
      final repo = RecordingRepository();
      final app = await bootedApp(repo);
      final before = _books(app);
      final lastNo =
          app.bills.map((b) => b.billNumber).reduce((a, b) => a > b ? a : b);
      _fillBill(app);
      final total = app.cartTotal;
      final d = (await app.saveDraft()).draft!;
      // Other drafts don't use up bill numbers.
      app.startNewBill();
      app.addToCart('p3', SaleType.bag, 1);
      final other = (await app.saveDraft()).draft!;
      app.startNewBill();

      app.openDraft(d.id);
      final res = await app.finalizeSale();
      expect(res.ok, isTrue, reason: res.error);
      final bill = res.bill!;
      expect(bill.billNumber, lastNo + 1);
      expect(bill.status, BillStatus.finalized);
      expect(bill.total, total);
      expect(bill.payments.map((p) => (p.mode, p.amount)),
          [(PayMode.cash, total - 5), (PayMode.credit, 5)]);
      // The one commit carried the sale AND the draft removal.
      expect(repo.commits, hasLength(1));
      expect(repo.commits.single.finalizedDraftId, d.id);
      expect(repo.commits.single.newBills.single.id, bill.id);
      expect(app.drafts.map((x) => x.id), [other.id]);
      _expectFresh(app);

      final after = _books(app);
      expect(after.bags, before.bags - 2);
      expect(after.revenue, closeTo(before.revenue + total, 0.001));
      expect(after.outstanding, closeTo(before.outstanding + 5, 0.001));
      expect(after.ledger, before.ledger + 1);
      expect(after.credit - before.credit, closeTo(5, 0.001));
    });

    test('16. a failed finalize keeps the draft (and stock) for a retry',
        () async {
      final repo = _FailingSaleRepo();
      final app = await bootedApp(repo);
      final before = _books(app);
      _fillBill(app);
      final d = (await app.saveDraft()).draft!;
      final res = await app.finalizeSale();
      expect(res.ok, isFalse);
      expect(res.error, contains('network'));
      expect(app.drafts.single.id, d.id);
      expect(repo.drafts.keys, [d.id]);
      expect(app.currentDraftId, d.id, reason: 'still open to retry');
      expect(app.cart, hasLength(2));
      expect(_books(app), before);
    });

    test('9. a draft holds no stock; finalize warns when stock ran out',
        () async {
      final app = await bootedApp();
      final bags = app.sellableQty('p1', SaleType.bag);
      final stock = app.stockOf('p1').bags;
      app.addToCart('p1', SaleType.bag, bags);
      await app.saveDraft();
      expect(app.stockOf('p1').bags, stock, reason: 'nothing reserved');
      app.setLineQty(0, bags + 1); // more than is left now
      final res = await app.finalizeSale();
      expect(res.ok, isFalse);
      expect(res.error, contains('उपलब्ध साठा बदलला आहे'));
      expect(res.error, contains('Available stock has changed'));
      expect(app.drafts, hasLength(1));
    });

    test(
        'another phone: stale saves and finalizes are refused, not overwritten',
        () async {
      final repo = InMemoryRepository();
      final phoneA = await bootedApp(repo);
      final phoneB = await bootedApp(repo);
      phoneA.addToCart('p1', SaleType.bag, 1);
      final d = (await phoneA.saveDraft()).draft!;

      await phoneB.refreshDrafts();
      expect(phoneB.drafts.single.id, d.id);
      phoneB.openDraft(d.id);
      phoneB.setLineQty(0, 4);
      expect((await phoneB.saveDraft()).ok, isTrue);
      expect(repo.drafts[d.id]!.version, 2);

      // Phone A still holds version 1.
      phoneA.setLineQty(0, 9);
      final stale = await phoneA.saveDraft();
      expect(stale.ok, isFalse);
      expect(stale.error, contains('another phone'));
      expect(repo.drafts[d.id]!.lines.single.qty, 4, reason: 'not overwritten');
      expect(phoneA.currentDraftId, isNull, reason: 'kept on screen, unlinked');
      expect(phoneA.cart.single.qty, 9);
      // Saving again keeps phone A's work as a NEW draft.
      final mine = (await phoneA.saveDraft()).draft!;
      expect(mine.id, isNot(d.id));

      // Phone A opens the old copy, phone B changes it again, A finalizes.
      await phoneA.refreshDrafts();
      phoneA.openDraft(d.id);
      phoneB.setLineQty(0, 5);
      await phoneB.saveDraft();
      final res = await phoneA.finalizeSale();
      expect(res.ok, isFalse);
      expect(res.error, contains('changed on another phone'));
      expect(repo.drafts.containsKey(d.id), isTrue);

      // B finalizes; A's later attempt finds it gone — never two bills.
      final okB = await phoneB.finalizeSale();
      expect(okB.ok, isTrue, reason: okB.error);
      phoneA.closeBill();
      await phoneA.refreshDrafts();
      expect(phoneA.drafts.map((x) => x.id), [mine.id]);
    });

    test('4. changes to a saved draft save themselves, once per pause',
        () async {
      final repo = InMemoryRepository();
      final app = await bootedApp(repo);
      app.addToCart('p1', SaleType.bag, 1);
      final d = (await app.saveDraft()).draft!;
      for (final q in [2.0, 3.0, 4.0, 5.0, 6.0]) {
        app.setLineQty(0, q); // like typing, one keystroke at a time
      }
      expect(repo.drafts[d.id]!.version, 1, reason: 'no write per keystroke');
      await Future<void>.delayed(
          AppState.autosaveDelay + const Duration(milliseconds: 300));
      await app.draftSavesSettled;
      expect(repo.drafts[d.id]!.version, 2, reason: 'one debounced write');
      expect(repo.drafts[d.id]!.lines.single.qty, 6);
      expect(app.cartDirty, isFalse);
      app.closeBill();
    });

    test('New Bill / opening a draft keeps an unsaved bill as a draft',
        () async {
      final app = await bootedApp();
      app.addToCart('p1', SaleType.bag, 1);
      app.startNewBill(); // not saved by hand
      _expectFresh(app);
      await app.draftSavesSettled;
      expect(app.drafts, hasLength(1));
      expect(app.drafts.single.lines.single.productId, 'p1');
    });

    test('19-20. finalized bills keep the revision workflow and Void',
        () async {
      final app = await bootedApp();
      app.addToCart('p1', SaleType.bag, 1);
      final bill = (await app.finalizeSale()).bill!;
      app.addToCart('p2', SaleType.bag, 1);
      expect((await app.saveDraft()).ok, isTrue);

      expect(app.beginEditBill(bill.id), isNull);
      expect(app.currentDraftId, isNull, reason: 'edit is not a draft');
      expect(app.drafts, hasLength(1), reason: 'the draft is untouched');
      app.setLineQty(0, 2);
      expect(app.hasUnsavedBill, isFalse);
      expect((await app.saveDraft()).ok, isFalse);
      app.fitPayments(); // as Checkout does for a changed total
      final rev = await app.finalizeSale();
      expect(rev.ok, isTrue, reason: rev.error);
      expect(rev.bill!.revision, 1);
      expect(rev.bill!.billNumber, bill.billNumber);
      expect(app.drafts, hasLength(1));

      expect(await app.voidBill(rev.bill!.id), isNull);
      expect(app.bills.firstWhere((b) => b.id == rev.bill!.id).status,
          BillStatus.voided);
      expect(app.drafts, hasLength(1));
    });
  });

  group('draft bill screens', () {
    Future<AppState> pump(WidgetTester tester, Widget home,
        {AppLang lang = AppLang.both,
        Size size = const Size(360, 780),
        void Function(AppState)? prep}) async {
      tester.view.physicalSize = size * 2;
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

    Future<void> saveDraftOf(WidgetTester tester, AppState app, String party,
        String pid, double qty) async {
      app.startNewBill();
      app.setCartCustomer(party);
      app.addToCart(pid, SaleType.bag, qty);
      await tester.runAsync(app.saveDraft);
      app.startNewBill();
    }

    testWidgets('Home New Bill opens an EMPTY bill while drafts exist (360px)',
        (tester) async {
      final app = await pump(tester, const HomeScreen());
      await saveDraftOf(tester, app, 'c1', 'p1', 2);
      await tester.pumpAndSettle();
      expect(find.text('📝 1'), findsOneWidget); // Draft Bills tile badge

      await tester.tap(find.byKey(const ValueKey('home-new-bill')));
      await tester.pumpAndSettle();
      expect(find.byType(SalesEntryScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('sales-row-0')), findsNothing);
      expect(find.byKey(const ValueKey('sales-draft-banner')), findsNothing);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('sales-grand-total')))
              .data,
          '₹0');
      expect(app.drafts, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('14. Back with unsaved changes: Continue / Discard / Save',
        (tester) async {
      final app = await pump(tester, const HomeScreen());
      Future<void> openAndFill() async {
        await tester.tap(find.byKey(const ValueKey('home-new-bill')));
        await tester.pumpAndSettle();
        app.addToCart('p1', SaleType.bag, 2);
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('leave-save')), findsOneWidget);
        expect(find.byKey(const ValueKey('leave-discard')), findsOneWidget);
        expect(find.byKey(const ValueKey('leave-stay')), findsOneWidget);
      }

      await openAndFill();
      await tester.tap(find.byKey(const ValueKey('leave-stay')));
      await tester.pumpAndSettle();
      expect(find.byType(SalesEntryScreen), findsOneWidget);
      expect(app.cart, hasLength(1));

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('leave-discard')));
      await tester.pumpAndSettle();
      expect(find.byType(SalesEntryScreen), findsNothing);
      expect(app.cart, isEmpty);
      expect(app.drafts, isEmpty);

      await openAndFill();
      await tester.tap(find.byKey(const ValueKey('leave-save')));
      await tester.pumpAndSettle();
      expect(find.byType(SalesEntryScreen), findsNothing);
      expect(app.drafts, hasLength(1));
      expect(find.textContaining('ड्राफ्ट सेव्ह झाला'), findsOneWidget);
      expect(app.cart, isEmpty);

      // Nothing unsaved: Back simply returns.
      await tester.tap(find.byKey(const ValueKey('home-new-bill')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SalesEntryScreen), findsNothing);
    });

    testWidgets('Save Draft → Continue Draft / New Sale Bill; Checkout Save Draft',
        (tester) async {
      final app = await pump(tester, const HomeScreen());
      await tester.tap(find.byKey(const ValueKey('home-new-bill')));
      await tester.pumpAndSettle();
      app.addToCart('p1', SaleType.bag, 1);
      app.setSaleMode(PayMode.credit);
      app.setCartCustomer('c1');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sales-save-draft')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('draft-saved-title')), findsOneWidget);
      expect(find.textContaining('#D1001'), findsWidgets);
      for (final k in ['draft-saved-continue', 'draft-saved-new', 'draft-saved-list']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      // Continue Draft: same bill, now marked as a draft.
      await tester.tap(find.byKey(const ValueKey('draft-saved-continue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sales-draft-banner')), findsOneWidget);
      expect(find.textContaining('हे बिल अजून पूर्ण झालेले नाही'), findsOneWidget);
      expect(app.cart, hasLength(1));

      // + New Sale Bill: a fresh, empty bill; the draft stays.
      await tester.tap(find.byKey(const ValueKey('sales-save-draft')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('draft-saved-new')));
      await tester.pumpAndSettle();
      expect(find.byType(SalesEntryScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('sales-draft-banner')), findsNothing);
      expect(
          tester.widget<Text>(find.byKey(const ValueKey('sales-grand-total'))).data,
          '₹0');
      _expectFresh(app);
      expect(app.drafts.single.payments.single.mode, PayMode.credit);

      // The QR / cart route's Checkout can also keep a bill as a draft.
      app.addToCart('p1', SaleType.bag, 1);
      Navigator.of(tester.element(find.byType(SalesEntryScreen)))
          .push(MaterialPageRoute<void>(builder: (_) => const CheckoutScreen()));
      await tester.pumpAndSettle();
      expect(find.text(tr('✅ बिल पूर्ण करा · Finalize Bill')), findsOneWidget);
      app.addSplitPayment();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('checkout-save-draft')));
      await tester.tap(find.byKey(const ValueKey('checkout-save-draft')));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(app.drafts, hasLength(2));
      expect(app.draftsNewestFirst.first.payments, hasLength(2));
      _expectFresh(app);
    });

    testWidgets('Draft Bills: Continue restores the bill, Delete removes it',
        (tester) async {
      late String a;
      final app = await pump(tester, const DraftBillsScreen());
      await saveDraftOf(tester, app, 'c1', 'p1', 3);
      await saveDraftOf(tester, app, 'c2', 'p3', 1);
      a = app.drafts.first.id;
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('draft-card-$a')), findsOneWidget);
      expect(find.byKey(const ValueKey('draft-pill')), findsNWidgets(2));
      expect(find.text('#D1001'), findsOneWidget);
      expect(find.text('#D1002'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(ValueKey('draft-continue-$a')));
      await tester.pumpAndSettle();
      expect(find.byType(SalesEntryScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('sales-draft-banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('sales-row-0')), findsOneWidget);
      expect(app.cartCustomerId, 'c1');
      expect(app.cart.single.qty, 3);

      await tester.pageBack(); // no changes: straight back
      await tester.pumpAndSettle();
      expect(find.byType(DraftBillsScreen), findsOneWidget);

      final stock = app.stockOf('p1').bags;
      await tester.tap(find.byKey(ValueKey('draft-delete-$a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('draft-delete-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('draft-card-$a')), findsNothing);
      expect(app.drafts, hasLength(1));
      expect(app.stockOf('p1').bags, stock);
    });

    testWidgets('16. Bills screen: drafts and final bills are separate',
        (tester) async {
      final app = await pump(tester, const ReturnsScreen());
      await saveDraftOf(tester, app, 'c1', 'p1', 1);
      await tester.pumpAndSettle();
      expect(find.textContaining('ड्राफ्ट बिले'), findsWidgets);
      expect(find.textContaining('पूर्ण बिले'), findsOneWidget);
      expect(find.byKey(const ValueKey('draft-pill')), findsOneWidget);
      expect(find.textContaining('✅ पूर्ण'), findsWidgets);
      // A draft is never listed among the final bills.
      expect(app.bills.any((b) => b.id.startsWith('DRAFT')), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Sell screen shows the draft count', (tester) async {
      final app = await pump(tester, const SellScreen());
      await saveDraftOf(tester, app, 'c1', 'p1', 1);
      await saveDraftOf(tester, app, 'c2', 'p1', 1);
      await tester.pumpAndSettle();
      expect(find.text('📝 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final lang in AppLang.values) {
      testWidgets('22-25. [${lang.name}] draft screens at 360px',
          (tester) async {
        final app = await pump(tester, const DraftBillsScreen(), lang: lang);
        await saveDraftOf(tester, app, 'c1', 'p1', 2);
        await tester.pumpAndSettle();
        final pill = switch (lang) {
          AppLang.mr => '📝 ड्राफ्ट',
          AppLang.en => '📝 Draft',
          AppLang.both => '📝 ड्राफ्ट · Draft',
        };
        expect(find.text(pill), findsOneWidget);
        expect(find.text(tr('▶ पुढे सुरू करा · Continue')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'no overflow at 360px');

        await tester.tap(
            find.byKey(ValueKey('draft-continue-${app.drafts.single.id}')));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const ValueKey('sales-draft-banner')), findsOneWidget);
        expect(find.text(pill), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'no overflow at 360px');
      });
    }
  });
}
