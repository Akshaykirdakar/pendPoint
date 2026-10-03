// Multi-store, end to end through AppState + FirestoreRepository (fake
// Firestore): login routing by role/store, Store A ⇄ Store B isolation in
// everything the app shows, per-store bill ids, audit trail, sign-out
// clearing, and the super admin's store management.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/main.dart';
import 'package:pend_point/models/app_settings.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/models/staff.dart';
import 'package:pend_point/models/store.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/state/report_query.dart';
import 'package:pend_point/ui/screens/super_admin_screens.dart';
import 'package:pend_point/utils/lang.dart';
import 'package:pend_point/utils/theme.dart';

import 'multistore_support.dart';

Future<(AppState, FakeFirebaseFirestore)> _login(String uid,
    [FakeFirebaseFirestore? existing]) async {
  final db = existing ?? await twoStores();
  signedInUid = uid;
  final app = AppState(repoFor(db));
  await app.startSession();
  while (app.historyLoading) {
    await Future<void>.delayed(Duration.zero);
  }
  return (app, db);
}

double _revenue(AppState app) => buildReport(
        bills: app.finalBills,
        products: app.products,
        filter: ReportFilter.preset(DateRangePresetKind.last30))
    .revenue;

void main() {
  tearDown(() => appLang = AppLang.both);

  group('login routing', () {
    test('store user → their store only', () async {
      final (app, _) = await _login('staffA');
      expect(app.session, SessionState.store);
      expect(app.storeId, storeA);
      expect(app.store!.storeName, 'Store $storeA');
      expect(app.isSuperAdmin, isFalse);
      expect(app.products.map((p) => p.id), ['pA']);
      expect(app.settings.shop, 'Shop $storeA');
    });

    test('disabled user, no profile, no store, inactive store: no data',
        () async {
      for (final (uid, state) in [
        ('disabledA', SessionState.disabled),
        ('ghost', SessionState.noProfile),
        ('noStore', SessionState.noStore),
        ('offStaff', SessionState.storeInactive),
      ]) {
        final (app, _) = await _login(uid);
        expect(app.session, state, reason: uid);
        expect(app.products, isEmpty, reason: uid);
        expect(app.storeId, isNull, reason: uid);
      }
    });

    test('super admin → dashboard, no store data until a store is opened',
        () async {
      final (app, _) = await _login('super1');
      expect(app.session, SessionState.superAdmin);
      expect(app.isSuperAdmin, isTrue);
      expect(app.storeId, isNull);
      expect(app.products, isEmpty);
    });
  });

  group('Store A ⇄ Store B isolation', () {
    test('products, customers, bills, stock, drafts, purchases, khata, reports',
        () async {
      final (a, db) = await _login('staffA');
      expect(a.customers.map((c) => c.id), ['cA']);
      expect(a.bills.map((b) => b.id), ['BILLA']);
      expect(a.batches.map((b) => b.id), ['btA']);
      expect(a.stock.keys, ['pA']);
      expect(a.drafts.map((d) => d.id), ['DRAFTA']);
      expect(a.purchases.map((p) => p.id), ['PURA']);
      expect(a.totalOutstanding, 100);
      expect(_revenue(a), 500);
      expect(a.staff.every((s) => s.storeId == storeA), isTrue);

      final (b, _) = await _login('staffB', db);
      expect(b.products.map((p) => p.id), ['pB']);
      expect(b.customers.map((c) => c.id), ['cB']);
      expect(b.bills.map((x) => x.id), ['BILLB']);
      expect(b.drafts.map((d) => d.id), ['DRAFTB']);
      expect(b.totalOutstanding, 900);
      expect(b.productOf('pA'), isNull,
          reason: 'A\'s product id means nothing in B');
    });

    test(
        'a sale in A: per-store bill id, store-stamped, audited; invisible to B',
        () async {
      final (a, db) = await _login('staffA');
      a.setCartCustomer('cA');
      expect(a.addToCart('pA', SaleType.bag, 2), isNull);
      final res = await a.finalizeSale();
      expect(res.ok, isTrue, reason: res.error);
      final bill = res.bill!;
      expect(bill.id, '${storeA}_BILL1001');
      expect(bill.billNumber, 1001);
      final saved = await db.doc('bills/${bill.id}').get();
      expect(saved.get('storeId'), storeA);
      final audits = await db.collection('auditLogs').get();
      expect(
          audits.docs.map((d) => d.get('action')), contains('BILL_FINALIZED'));
      expect(audits.docs.every((d) => d.get('storeId') == storeA), isTrue);
      expect((await db.doc('batches/btA').get()).get('bagsAvailable'), 8);

      final (b, _) = await _login('staffB', db);
      expect(b.bills.any((x) => x.id == bill.id), isFalse);
      expect(b.batches.single.bagsAvailable, 10);
      // B's own numbering starts at its own counter.
      b.addToCart('pB', SaleType.bag, 1);
      expect((await b.finalizeSale()).bill!.id, '${storeB}_BILL1001');
    });

    test('a draft saved in A never shows in B', () async {
      final (a, db) = await _login('staffA');
      a.addToCart('pA', SaleType.bag, 1);
      final d = (await a.saveDraft()).draft!;
      expect(d.id, '${storeA}_DRAFT1001');
      expect((await db.doc('draftBills/${d.id}').get()).get('storeId'), storeA);
      final (b, _) = await _login('staffB', db);
      expect(b.drafts.map((x) => x.id), ['DRAFTB']);
    });

    test('sign-out clears every trace of the store', () async {
      final (a, _) = await _login('staffA');
      a.setCartCustomer('cA');
      a.addToCart('pA', SaleType.bag, 1);
      a.clearSession();
      expect(a.session, SessionState.none);
      expect(a.storeContext, isNull);
      for (final list in [
        a.products,
        a.customers,
        a.bills,
        a.batches,
        a.drafts,
        a.purchases,
        a.staff,
        a.cart
      ]) {
        expect(list, isEmpty);
      }
      expect(a.stock, isEmpty);
      expect(a.cartCustomerId, isNull);
    });

    test('store users cannot save a super admin or another store', () async {
      final (a, _) = await _login('adminA');
      await expectLater(
          a.saveStaff(const Staff(id: 'x', name: 'x', role: Roles.superAdmin)),
          throwsA(isA<StoreContextException>()));
      await a.saveStaff(const Staff(
          id: 'newStaff', name: 'New', role: Roles.staff, storeId: storeB));
      expect(a.staff.firstWhere((s) => s.id == 'newStaff').storeId, storeA,
          reason: 'saved into the store being worked in, whatever was passed');
      await expectLater(a.createStore(code: 'STR9', name: 'x'),
          throwsA(isA<StoreContextException>()));
    });
  });

  test('new store codes follow the stores so far', () {
    expect(AppState.storeCodeAfter(['STORE001', 'STR002']), 'STR003');
    expect(AppState.storeCodeAfter(['STORE001']), 'STR002');
    expect(AppState.storeCodeAfter([]), 'STR001');
    // A gap or an odd code never makes a code that is already used.
    expect(AppState.storeCodeAfter(['STORE001', 'STR005']), 'STR006');
    expect(AppState.storeCodeAfter(['STORE001', 'KOLHAPUR', 'STR003']),
        'STR004');
  });

  group('super admin', () {
    test('creates a store + admin, deactivates it, opens a store', () async {
      final (app, db) = await _login('super1');
      expect(await app.createStore(code: 'bad code', name: 'x'), isNotNull);
      expect(await app.createStore(code: storeA, name: 'dup'),
          contains('already'));
      expect(
          await app.createStore(
              code: 'STR003', name: 'Kolhapur', city: 'Kolhapur'),
          isNull);
      final st = (await app.repo.loadStore('STR003'))!;
      expect(st.isActive, isTrue);
      expect((await db.doc('stores/STR003/meta/counters').get()).get('bill'),
          1000);
      expect((await db.doc('stores/STR003/meta/settings').get()).get('shop'),
          'Kolhapur');

      // A store admin for it (login creation is replaced in tests).
      final users = (await app.repo.listUsers(storeId: 'STR003'));
      expect(users, isEmpty);
      expect(
          await app.updateStoreUser(
              const Staff(id: 'x', name: 'x', role: Roles.superAdmin)),
          isNotNull);

      expect(await app.updateStore(st.copyWith(status: StoreStatus.inactive)),
          isNull);
      expect((await app.repo.loadStore('STR003'))!.isActive, isFalse);
      final audits = await db.collection('auditLogs').get();
      expect(audits.docs.map((d) => d.get('action')),
          containsAll(['STORE_CREATED', 'STORE_DISABLED']));

      // Open Store B: B's data only, owner rights, still a super admin.
      await app.openStore((await app.repo.loadStore(storeB))!);
      while (app.historyLoading) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(app.session, SessionState.store);
      expect(app.isSuperAdmin, isTrue);
      expect(app.hasOwnerRights, isTrue);
      expect(app.products.map((p) => p.id), ['pB']);
      expect(app.bills.map((b) => b.id), ['BILLB']);
      app.closeStore();
      expect(app.session, SessionState.superAdmin);
      expect(app.products, isEmpty);
      expect(app.storeId, isNull);
    });
  });

  group('screens', () {
    Future<AppState> pump(WidgetTester tester, String uid,
        {FakeFirebaseFirestore? db}) async {
      tester.view.physicalSize = const Size(720, 2400); // 360 wide
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (app, _) = (await tester.runAsync(() => _login(uid, db)))!;
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            theme: buildTheme(Brightness.light), home: const SessionScreen()),
      ));
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('store user lands in their store; store name shown',
        (tester) async {
      await pump(tester, 'staffA');
      expect(find.byKey(const ValueKey('store-badge-name')), findsOneWidget);
      expect(find.text('🏪 Store $storeA · $storeA'), findsOneWidget);
      expect(find.byKey(const ValueKey('store-badge-back')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('inactive store: the message, no data', (tester) async {
      await pump(tester, 'offStaff');
      expect(find.byKey(const ValueKey('store-inactive')), findsOneWidget);
      expect(find.textContaining('This store is currently inactive'),
          findsOneWidget);
    });

    testWidgets('disabled account: the message', (tester) async {
      await pump(tester, 'disabledA');
      expect(find.textContaining('Your account has been disabled'),
          findsOneWidget);
    });

    testWidgets('super admin dashboard: totals, stores, open a store',
        (tester) async {
      final app = await pump(tester, 'super1');
      await tester.pumpAndSettle();
      expect(find.byType(SuperAdminHome), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sa-tab-stores')));
      await tester.pumpAndSettle();
      for (final s in [storeA, storeB, storeOff]) {
        expect(find.byKey(ValueKey('sa-store-$s')), findsOneWidget);
      }
      expect(find.textContaining('Inactive'), findsWidgets);
      expect(tester.takeException(), isNull, reason: '360px');

      await tester.ensureVisible(find.byKey(const ValueKey('sa-open-$storeB')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sa-open-$storeB')));
      await tester.runAsync(() async {
        while (app.loading || app.historyLoading) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('🏪 Store $storeB · $storeB'), findsOneWidget);
      expect(find.byKey(const ValueKey('store-badge-back')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('store-badge-back')));
      await tester.pumpAndSettle();
      expect(find.byType(SuperAdminHome), findsOneWidget);
    });

    testWidgets('super admin creates a store from the form', (tester) async {
      final app = await pump(tester, 'super1');
      await tester.tap(find.byKey(const ValueKey('sa-tab-stores')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sa-create-store')));
      await tester.pumpAndSettle();
      // The code is given automatically: 3 stores so far → STR004.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      final codeField = tester.widget<TextField>(
          find.byKey(const ValueKey('store-form-code')));
      expect(codeField.controller!.text, 'STR004');
      expect(codeField.enabled, isFalse);
      await tester.enterText(
          find.byKey(const ValueKey('store-form-name')), 'Sangli');
      await tester.ensureVisible(find.byKey(const ValueKey('store-form-save')));
      await tester.tap(find.byKey(const ValueKey('store-form-save')));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      final st = (await tester.runAsync(() => app.repo.loadStore('STR004')))!;
      expect(st.storeName, 'Sangli');
    });

    testWidgets('sign-out / All stores close the screens opened on top',
        (tester) async {
      tester.view.physicalSize = const Size(720, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (app, _) = (await tester.runAsync(() => _login('super1')))!;
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: const SessionNavigator(child: SessionScreen())),
      ));
      await tester.pumpAndSettle();
      Future<void> pushSettings() async {
        Navigator.of(tester.element(find.byType(SessionScreen))).push(
            MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('on top'))));
        await tester.pumpAndSettle();
        expect(find.text('on top'), findsOneWidget);
      }

      // Super admin in a store, a screen open, then "All stores".
      await tester.runAsync(() async {
        await app.openStore((await app.repo.loadStore(storeA))!);
        while (app.historyLoading) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pumpAndSettle();
      await pushSettings();
      app.closeStore();
      await tester.pumpAndSettle();
      expect(find.text('on top'), findsNothing);
      expect(find.byType(SuperAdminHome), findsOneWidget);

      // A screen open, then sign-out.
      await pushSettings();
      app.clearSession();
      // (the auth gate then shows sign-in; here the splash spins, so no settle)
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('on top'), findsNothing);
      expect(find.byType(SessionScreen), findsOneWidget);
    });
  });
}
