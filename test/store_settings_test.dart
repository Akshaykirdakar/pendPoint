// Every store has its own settings (stores/{id}/meta/settings): changing
// one store's never touches another's; staff cannot change them; the super
// admin edits any store's from the Stores tab and that store's devices
// update live; each change is audited per setting.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/models/app_settings.dart';
import 'package:pend_point/models/store.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/ui/screens/home_screen.dart';
import 'package:pend_point/ui/screens/settings_screen.dart';
import 'package:pend_point/ui/screens/store_settings_screen.dart';
import 'package:pend_point/utils/lang.dart';
import 'package:pend_point/utils/theme.dart';

import 'multistore_support.dart';

Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<AppState> _login(String uid, FakeFirebaseFirestore db) async {
  signedInUid = uid;
  final app = AppState(repoFor(db));
  await app.startSession();
  while (app.historyLoading) {
    await Future<void>.delayed(Duration.zero);
  }
  await _settle();
  return app;
}

Future<Map<String, dynamic>> _doc(FakeFirebaseFirestore db, String sid) async =>
    (await db.doc('stores/$sid/meta/settings').get()).data()!;

void main() {
  tearDown(() => appLang = AppLang.both);

  test('a store admin changes only their own store\'s settings', () async {
    final db = await twoStores();
    final a = await _login('adminA', db);
    expect(a.canEditSettings, isTrue);
    await a.updateSettings((s) => s
      ..shop = 'Akshay Traders'
      ..lang = AppLang.en
      ..lowDefaultBags = 9);
    expect((await _doc(db, storeA))['shop'], 'Akshay Traders');
    expect((await _doc(db, storeA))['lowDefaultBags'], 9);
    final b = await _doc(db, storeB);
    expect(b['shop'], 'Shop $storeB');
    expect(b['lang'], 'both');
    expect(b.containsKey('lowDefaultBags'), isFalse);

    final adminB = await _login('adminB', db);
    expect(adminB.settings.shop, 'Shop $storeB');
    expect(adminB.settings.lang, AppLang.both);

    final audits = (await db.collection('auditLogs').get()).docs
        .map((d) => d.data())
        .where((a) => a['action'] == 'SETTING_CHANGED')
        .toList();
    final shop = audits.singleWhere((x) => x['field'] == 'shop');
    expect(shop['storeId'], storeA);
    expect(shop['oldValue'], 'Shop $storeA');
    expect(shop['newValue'], 'Akshay Traders');
    expect(audits.every((x) => x['storeId'] == storeA), isTrue);
  });

  test('staff cannot change store settings', () async {
    final db = await twoStores();
    final s = await _login('staffA', db);
    expect(s.canEditSettings, isFalse);
    await expectLater(s.updateSettings((x) => x.shop = 'Staff edit'),
        throwsA(isA<StoreContextException>()));
    expect((await _doc(db, storeA))['shop'], 'Shop $storeA');
  });

  test('super admin edits one store from outside; its devices update live', () async {
    final db = await twoStores();
    final staffB = await _login('staffB', db);
    expect(staffB.settings.shop, 'Shop $storeB');

    final sa = await _login('super1', db);
    final before = await sa.platform.storeSettings(storeB);
    final after = before.copy()
      ..shop = 'Sangli Feeds'
      ..gateOverridePct = 12;
    expect(await sa.platform.saveStoreSettings(storeB, before, after), isNull);
    await _settle();

    expect((await _doc(db, storeB))['shop'], 'Sangli Feeds');
    expect((await _doc(db, storeA))['shop'], 'Shop $storeA');
    expect(staffB.settings.shop, 'Sangli Feeds', reason: 'live, no reload');
    expect(staffB.settings.gateOverridePct, 12);
  });

  test('a store admin cannot save another store\'s settings', () async {
    final db = await twoStores();
    final a = await _login('adminA', db);
    final b = AppSettings()..shop = 'hijack';
    expect(await a.platform.saveStoreSettings(storeB, AppSettings(), b), isNotNull);
    expect((await _doc(db, storeB))['shop'], 'Shop $storeB');
    expect(() => a.platform.storeSettings(storeB), throwsA(isA<StoreContextException>()));
  });

  group('one shop name', () {
    Future<(String, String)> names(FakeFirebaseFirestore db, String sid) async => (
          (await db.doc('stores/$sid').get()).get('storeName') as String,
          (await _doc(db, sid))['shop'] as String,
        );

    test('Settings shop name renames the store too', () async {
      final db = await twoStores();
      final a = await _login('adminA', db);
      await a.updateSettings((s) => s.shop = 'Akshay Traders');
      expect(await names(db, storeA), ('Akshay Traders', 'Akshay Traders'));
      expect(a.shopName, 'Akshay Traders');
      expect(await names(db, storeB), ('Store $storeB', 'Shop $storeB'));
    });

    test('Store details / super admin Edit store / Store settings keep both equal', () async {
      final db = await twoStores();
      final a = await _login('adminA', db);
      expect(await a.updateMyStore(a.store!.copyWith(storeName: 'Akshay Traders')), isNull);
      expect(await names(db, storeA), ('Akshay Traders', 'Akshay Traders'));

      final sa = await _login('super1', db);
      final b = (await sa.repo.loadStore(storeB))!;
      expect(await sa.updateStore(b.copyWith(storeName: 'Sangli Feeds')), isNull);
      expect(await names(db, storeB), ('Sangli Feeds', 'Sangli Feeds'));

      final before = await sa.platform.storeSettings(storeB);
      expect(await sa.platform.saveStoreSettings(storeB, before, before.copy()..shop = 'Sangli Agro'),
          isNull);
      expect(await names(db, storeB), ('Sangli Agro', 'Sangli Agro'));
      expect(await names(db, storeA), ('Akshay Traders', 'Akshay Traders'));
    });

    test('an old mismatch shows the store\'s name everywhere', () async {
      final db = await twoStores(); // store "Store STR-A", settings "Shop STR-A"
      final s = await _login('staffA', db);
      expect(s.shopName, 'Store $storeA');
    });

    testWidgets('Home shows the shop name big, also in Marathi', (tester) async {
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = (await tester.runAsync(twoStores))!;
      final app = (await tester.runAsync(() => _login('adminA', db)))!;
      appLang = AppLang.mr;
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(theme: buildTheme(Brightness.light), home: const HomeScreen())));
      await tester.pumpAndSettle();
      final t = tester.widget<Text>(find.byKey(const ValueKey('home-shop-name')));
      expect(t.data, 'Store $storeA');
      expect(t.style!.fontSize, 22);
      expect(tester.takeException(), isNull);
    });
  });

  group('screens', () {
    Future<AppState> pump(WidgetTester tester, String uid, Widget Function(AppState) screen,
        FakeFirebaseFirestore db) async {
      tester.view.physicalSize = const Size(720, 1600); // 360 wide
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = (await tester.runAsync(() => _login(uid, db)))!;
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(theme: buildTheme(Brightness.light), home: screen(app))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '360px');
      return app;
    }

    testWidgets('super admin: a store\'s own settings screen saves that store only',
        (tester) async {
      final db = (await tester.runAsync(twoStores))!;
      final st = (await tester.runAsync(() => repoFor(db).loadStore(storeB)))!;
      await pump(tester, 'super1', (_) => StoreSettingsScreen(store: st), db);
      expect(find.byKey(const ValueKey('ss-scope')), findsOneWidget);
      expect(find.textContaining('Store $storeB ($storeB)'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('ss-shop')), 'Sangli Feeds');
      await tester.ensureVisible(find.byKey(const ValueKey('ss-save')));
      await tester.tap(find.byKey(const ValueKey('ss-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ss-error')), findsNothing);
      expect((await tester.runAsync(() => _doc(db, storeB)))!['shop'], 'Sangli Feeds');
      expect((await tester.runAsync(() => _doc(db, storeA)))!['shop'], 'Shop $storeA');
    });

    testWidgets('store Settings says which store; staff are told it is read-only',
        (tester) async {
      final db = (await tester.runAsync(twoStores))!;
      await pump(tester, 'adminA', (_) => const SettingsScreen(), db);
      expect(find.textContaining('apply only to Store $storeA ($storeA)'), findsOneWidget);
      await pump(tester, 'staffA', (_) => const SettingsScreen(), db);
      expect(find.textContaining('only the store admin can change them'), findsOneWidget);
    });
  });
}
