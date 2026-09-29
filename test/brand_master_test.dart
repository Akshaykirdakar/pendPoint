// Brand master: delete only when every product has no stock and no
// history (otherwise "Make Inactive"), active / inactive, proper names,
// and the optional brand photo.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/data/memory_repository.dart';
import 'package:pend_point/models/bill.dart';
import 'package:pend_point/models/brand.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/state/purchase_draft.dart';
import 'package:pend_point/ui/screens/brand_edit_screen.dart';
import 'package:pend_point/ui/screens/catalogue_screen.dart';
import 'package:pend_point/ui/screens/purchase_entry_screen.dart';
import 'package:pend_point/utils/theme.dart';

import 'test_support.dart';

/// Records brand deletes (what goes to Firestore in one batch).
class _Repo extends InMemoryRepository {
  final deletes = <(String, List<String>)>[];
  @override
  Future<void> deleteBrand(String brandId,
      {List<String> productIds = const []}) async {
    deletes.add((brandId, List.of(productIds)));
  }
}

// A real 1×1 PNG so the preview can decode it.
final _png = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

Future<String> _brand(AppState app, String name) async =>
    (await app.createBrand(name: name)).value!.id;

Future<void> _buy(AppState app, String pid, int bags) async {
  final r = await app.savePurchase(supplierId: app.suppliers.first.id, lines: [
    PurchaseLineInput(
        productId: pid, bags: bags, rate: 800, batchNo: 'X', expiry: inDays(90))
  ]);
  expect(r.ok, isTrue, reason: r.error);
}

void main() {
  group('delete rules', () {
    test('a brand with no products can be deleted', () async {
      final repo = _Repo();
      final app = await bootedApp(repo);
      final id = await _brand(app, 'Samruddhi');
      expect(app.whyBrandNotDeletable(id), isNull);
      expect(await app.deleteBrand(id), isNull);
      expect(app.brandOf(id), isNull);
      expect(repo.deletes.single.$1, id);
      expect(repo.deletes.single.$2, isEmpty);
    });

    test('zero-stock products that were never used are deleted with it',
        () async {
      final repo = _Repo();
      final app = await bootedApp(repo);
      final id = await _brand(app, 'Samruddhi');
      final pid = await freshProduct(app, name: 'Samruddhi 25kg', brandId: id);
      expect(app.whyBrandNotDeletable(id), isNull);
      expect(await app.deleteBrand(id), isNull);
      expect(app.productOf(pid), isNull, reason: 'no orphan product left');
      expect(repo.deletes.single.$2, [pid]); // same atomic write
    });

    test('products with stock block delete → make inactive instead', () async {
      final app = await bootedApp(_Repo());
      final id = await _brand(app, 'Samruddhi');
      final pid = await freshProduct(app, brandId: id);
      await _buy(app, pid, 3);
      final why = app.whyBrandNotDeletable(id)!;
      expect(why, contains('still have stock'));
      expect(await app.deleteBrand(id), why);
      expect(app.brandOf(id), isNotNull);
      expect(app.productOf(pid), isNotNull);
    });

    test('zero stock but past bills/purchases → protected (history kept)',
        () async {
      final app = await bootedApp(_Repo());
      final id = await _brand(app, 'Samruddhi');
      final pid = await freshProduct(app, brandId: id);
      await _buy(app, pid, 2);
      app.addToCart(pid, SaleType.bag, 2);
      app.payments
        ..clear()
        ..add(Payment(PayMode.cash, app.cartTotal));
      expect((await app.finalizeSale()).ok, isTrue);
      expect(app.stockOf(pid).bags, 0);

      expect(app.whyBrandNotDeletable(id), contains('past bills'));
      expect(await app.deleteBrand(id), isNotNull);
      expect(app.productOf(pid), isNotNull);
      // Inactive is the way out, and it keeps everything.
      final r = await app.updateBrand(id,
          name: 'Samruddhi', nameMr: 'समृद्धी', active: false);
      expect(r.ok, isTrue, reason: r.error);
      expect(
          app.bills.any((b) => b.items.any((i) => i.productId == pid)), isTrue);
    });

    test('staff cannot delete or edit brands', () async {
      final app = await bootedApp(StaffLoginRepository());
      expect(app.whyBrandNotDeletable('b3'), contains('Only the owner'));
      expect(await app.deleteBrand('b3'), isNotNull);
      expect(app.brandOf('b3'), isNotNull);
      final r =
          await app.updateBrand('b3', name: 'X', nameMr: 'X', active: false);
      expect(r.ok, isFalse);
    });
  });

  group('active / inactive', () {
    test('inactive brand is hidden from new sales/purchases, nothing else',
        () async {
      final app = await bootedApp();
      final kargil = app.products.where((p) => p.brandId == 'b2').toList();
      final stockBefore = {
        for (final p in kargil) p.id: app.stockOf(p.id).bags
      };
      final r = await app.updateBrand('b2',
          name: 'Kargil', nameMr: 'कारगिल', active: false);
      expect(r.ok, isTrue, reason: r.error);
      expect(app.activeBrands.map((b) => b.id), isNot(contains('b2')));
      for (final p in kargil) {
        expect(app.isProductSelectable(p), isFalse);
        expect(app.stockOf(p.id).bags, stockBefore[p.id]); // stock untouched
        expect(app.productOf(p.id), isNotNull);
      }
      // Re-activate.
      await app.updateBrand('b2',
          name: 'Kargil', nameMr: 'कारगिल', active: true);
      expect(app.isProductSelectable(kargil.first), isTrue);
    });

    test('a new brand named like an inactive one says so', () async {
      final app = await bootedApp();
      await app.updateBrand('b2',
          name: 'Kargil', nameMr: 'कारगिल', active: false);
      final r = await app.createBrand(name: 'kargil');
      expect(r.ok, isFalse);
      expect(r.error, contains('inactive'));
    });

    test('old documents load as active with no photo', () {
      final b = Brand.fromMap('x', {'name': 'Old', 'nameMr': 'जुना'});
      expect(b.active, isTrue);
      expect(b.photoUrl, isNull);
      final back = Brand.fromMap('x', b.copyWith(active: false).toMap());
      expect(back.active, isFalse);
    });
  });

  group('names', () {
    test('names are cleaned; renaming onto another brand is refused', () async {
      final app = await bootedApp();
      final r = await app.createBrand(
          name: '  Shree   Ganesh  ', nameMr: ' श्री  गणेश ');
      expect(r.value!.name, 'Shree Ganesh');
      expect(r.value!.nameMr, 'श्री गणेश');
      expect(
          (await app.updateBrand(r.value!.id,
                  name: 'Godrej', nameMr: '', active: true))
              .ok,
          isFalse);
      // Keeping its own name (e.g. only toggling active) is fine.
      expect(
          (await app.updateBrand(r.value!.id,
                  name: 'Shree Ganesh', nameMr: 'श्री गणेश', active: false))
              .ok,
          isTrue);
    });
  });

  group('photo (optional)', () {
    test('add, replace and remove — old files cleaned up', () async {
      final repo = InMemoryRepository();
      final app = await bootedApp(repo);
      final b = (await app.createBrand(
              name: 'Samruddhi', photo: BillPhotoChange.replace(_png, 'png')))
          .value!;
      expect(b.photoUrl, isNotNull);
      expect(repo.photos, hasLength(1));

      final r2 = (await app.updateBrand(b.id,
              name: b.name,
              nameMr: b.nameMr,
              active: true,
              photo: BillPhotoChange.replace(_png, 'jpg')))
          .value!;
      expect(r2.photoUrl, isNot(b.photoUrl));
      expect(repo.photos, hasLength(1), reason: 'replaced file removed');

      final r3 = (await app.updateBrand(b.id,
              name: b.name,
              nameMr: b.nameMr,
              active: true,
              photo: const BillPhotoChange.remove()))
          .value!;
      expect(r3.photoUrl, isNull);
      expect(repo.photos, isEmpty);

      final plain = (await app.createBrand(name: 'No Photo')).value!;
      expect(plain.photoUrl, isNull);
    });
  });

  group('screens (360px)', () {
    Future<AppState> pump(WidgetTester tester, Widget home,
        [AppState? a]) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = a ?? (await tester.runAsync(() => bootedApp(_Repo())))!;
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(theme: buildTheme(Brightness.light), home: home)));
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('brand with stock: no Delete, "Make Inactive" works',
        (tester) async {
      final app = await pump(tester, const BrandEditScreen(brandId: 'b1'));
      expect(find.byKey(const ValueKey('brand-delete')), findsNothing);
      expect(
          find.byKey(const ValueKey('brand-delete-blocked')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('brand-make-inactive')));
      await tester.pumpAndSettle();
      expect(app.brandOf('b1')!.active, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty brand: Delete → confirm → gone', (tester) async {
      final app = (await tester.runAsync(() => bootedApp(_Repo())))!;
      final id = (await tester.runAsync(() => _brand(app, 'Samruddhi')))!;
      await pump(
          tester,
          Builder(
              builder: (ctx) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                          builder: (_) => BrandEditScreen(brandId: id))),
                      child: const Text('open')))),
          app);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('brand-delete')));
      await tester.tap(find.byKey(const ValueKey('brand-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('brand-delete-confirm')));
      await tester.pumpAndSettle();
      expect(app.brandOf(id), isNull);
      expect(find.byType(BrandEditScreen), findsNothing);
    });

    testWidgets('new brand with photo + Marathi name, saved from the screen',
        (tester) async {
      BrandEditScreen.debugPickPhoto =
          (_) async => (bytes: _png, name: 'logo.png');
      addTearDown(() => BrandEditScreen.debugPickPhoto = null);
      final app = await pump(tester, const BrandEditScreen());
      await tester.enterText(
          find.byKey(const ValueKey('brand-name')), 'Samruddhi');
      await tester.enterText(
          find.byKey(const ValueKey('brand-name-mr')), 'समृद्धी');
      await tester.tap(find.byKey(const ValueKey('brand-photo-gallery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('brand-save')));
      await tester.pumpAndSettle();
      final b = app.brands.firstWhere((b) => b.name == 'Samruddhi');
      expect(b.nameMr, 'समृद्धी');
      expect(b.photoUrl, isNotNull);
      expect(b.active, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('catalogue: inactive tag, tap brand opens its screen',
        (tester) async {
      final app = (await tester.runAsync(() => bootedApp(_Repo())))!;
      await tester.runAsync(() => app.updateBrand('b2',
          name: 'Kargil', nameMr: 'कारगिल', active: false));
      await pump(tester, const CatalogueScreen(), app);
      expect(find.text('निष्क्रिय · Inactive'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('catalogue-brand-b2')));
      await tester.pumpAndSettle();
      expect(find.byType(BrandEditScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('purchase/sales pickers hide an inactive brand',
        (tester) async {
      final app = (await tester.runAsync(() => bootedApp(_Repo())))!;
      await tester.runAsync(() => app.updateBrand('b2',
          name: 'Kargil', nameMr: 'कारगिल', active: false));
      await pump(tester, const PurchaseEntryScreen(), app);
      // Brand picker: Kargil is not offered.
      await tester.tap(find.byKey(const ValueKey('purchase-row-0-brand')));
      await tester.pumpAndSettle();
      expect(find.text('Kargil'), findsNothing);
      expect(find.text('Godrej'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      // Product picker (All Brands): none of Kargil's products either.
      await tester.tap(find.byKey(const ValueKey('purchase-row-0-product')));
      await tester.pumpAndSettle();
      for (final p in app.products.where((p) => p.brandId == 'b2')) {
        expect(find.textContaining(p.name), findsNothing, reason: p.name);
      }
      final offered = app.products.where(app.isProductSelectable).length;
      expect(find.textContaining('$offered सापडले'), findsOneWidget);
    });
  });
}
