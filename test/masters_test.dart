// Brand + Product masters created from the purchase workflow, and the
// "All Brands" / specific-brand product filtering used across the app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/state/catalog_search.dart';
import 'package:pend_point/ui/screens/purchase_entry_screen.dart';
import 'package:pend_point/ui/screens/sales_entry_screen.dart';
import 'package:pend_point/utils/theme.dart';

import 'test_support.dart';

List<String> _names(AppState app, {String? brandId, String q = ''}) => [
      for (final p
          in searchProducts(app.products, app.brandOf, q, brandId: brandId))
        p.name
    ];

Future<AppState> _pump(WidgetTester tester, Widget home,
    [AppState? given]) async {
  tester.view.physicalSize = const Size(360, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final app = given ?? (await tester.runAsync(bootedApp))!;
  await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: home)));
  await tester.pumpAndSettle();
  return app;
}

String _fieldText(WidgetTester tester, Key key) => tester
    .widgetList<Text>(
        find.descendant(of: find.byKey(key), matching: find.byType(Text)))
    .map((t) => t.data ?? '')
    .join(' | ');

void main() {
  group('Brand master', () {
    test('6: create a brand', () async {
      final app = await bootedApp();
      final res = await app.createBrand(name: 'Samruddhi', nameMr: 'समृद्धी');
      expect(res.ok, isTrue, reason: res.error);
      expect(app.brands.map((b) => b.name), contains('Samruddhi'));
      expect(app.brandOf(res.value!.id)!.nameMr, 'समृद्धी');
    });

    test('7: duplicate brand rejected (case / spaces / Marathi name)',
        () async {
      final app = await bootedApp();
      final n = app.brands.length;
      for (final name in ['Godrej', ' godrej ', 'GODREJ']) {
        final r = await app.createBrand(name: name);
        expect(r.ok, isFalse, reason: name);
        expect(r.error, contains('already exists'));
      }
      expect((await app.createBrand(name: 'X', nameMr: 'गोदरेज')).ok, isFalse);
      expect((await app.createBrand(name: '   ')).ok, isFalse);
      expect(app.brands.length, n);
    });

    test('staff cannot create masters (same rule as Firestore)', () async {
      final app = await bootedApp(StaffLoginRepository());
      expect(app.hasOwnerRights, isFalse);
      final b = await app.createBrand(name: 'Samruddhi');
      expect(b.ok, isFalse);
      final p = await app.createProduct(
          brandId: 'b1', name: 'Z', bagWeightKg: 50, fullBagPrice: 1000);
      expect(p.ok, isFalse);
    });
  });

  group('Product master', () {
    late AppState app;
    late String brandId;
    setUp(() async {
      app = await bootedApp();
      brandId = (await app.createBrand(name: 'Samruddhi')).value!.id;
    });

    test('9+10+11: create under a brand; listed only under that brand',
        () async {
      for (final n in [
        'Samruddhi 25kg',
        'Samruddhi 50kg',
        'Samruddhi Special'
      ]) {
        final r = await app.createProduct(
            brandId: brandId, name: n, bagWeightKg: 25, fullBagPrice: 1050);
        expect(r.ok, isTrue, reason: r.error);
        expect(r.value!.brandId, brandId);
        expect(r.value!.perKgPrice, 42); // 1050 / 25 when not given
      }
      expect(
          _names(app, brandId: brandId),
          unorderedEquals(
              ['Samruddhi 25kg', 'Samruddhi 50kg', 'Samruddhi Special']));
      expect(_names(app, brandId: 'b1'), isNot(contains('Samruddhi 25kg')));
      expect(_names(app, brandId: 'b1', q: 'samruddhi'), isEmpty);
    });

    test('12: duplicate product under the same brand rejected; other brand OK',
        () async {
      await app.createProduct(
          brandId: brandId,
          name: 'Special',
          bagWeightKg: 50,
          fullBagPrice: 1000);
      final dup = await app.createProduct(
          brandId: brandId,
          name: ' special ',
          bagWeightKg: 50,
          fullBagPrice: 900);
      expect(dup.ok, isFalse);
      expect(dup.error, contains('already exists'));
      final other = await app.createProduct(
          brandId: 'b1', name: 'Special', bagWeightKg: 50, fullBagPrice: 900);
      expect(other.ok, isTrue, reason: other.error);
      expect(
          app.products.where((p) => p.name.trim().toLowerCase() == 'special'),
          hasLength(2));
    });

    test('no orphan products; required fields checked', () async {
      final n = app.products.length;
      expect(
          (await app.createProduct(
                  brandId: null, name: 'A', bagWeightKg: 50, fullBagPrice: 1))
              .ok,
          isFalse);
      expect(
          (await app.createProduct(
                  brandId: 'missing',
                  name: 'A',
                  bagWeightKg: 50,
                  fullBagPrice: 1))
              .ok,
          isFalse);
      expect(
          (await app.createProduct(
                  brandId: brandId, name: 'A', bagWeightKg: 0, fullBagPrice: 1))
              .ok,
          isFalse);
      expect(
          (await app.createProduct(
                  brandId: brandId,
                  name: 'A',
                  bagWeightKg: 50,
                  fullBagPrice: 0))
              .ok,
          isFalse);
      expect(app.products.length, n);
    });
  });

  group('Brand filter', () {
    test('14+15: All Brands = every product; a brand = only its products',
        () async {
      final app = await bootedApp();
      expect(_names(app).length, app.products.length);
      final godrej = _names(app, brandId: 'b1');
      expect(godrej, isNotEmpty);
      expect(
          godrej.every((n) =>
              app.products.firstWhere((p) => p.name == n).brandId == 'b1'),
          isTrue);
      expect(godrej.length, lessThan(app.products.length));
    });
  });

  group('Purchase entry (widgets)', () {
    testWidgets('8+13: new brand and new product are created and auto-selected',
        (tester) async {
      final app = await _pump(tester, const PurchaseEntryScreen());

      // Brand picker: search a missing brand → "Add New Brand".
      await tester.tap(find.byKey(const ValueKey('purchase-row-0-brand')));
      await tester.pumpAndSettle();
      // The field itself shows "All Brands", and so does the first option.
      expect(find.text('सर्व ब्रँड · All Brands'), findsNWidgets(2));
      await tester.enterText(
          find.byKey(const ValueKey('picker-search')), 'Samruddhi');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-create-row')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('brand-form-name')))
              .controller!
              .text,
          'Samruddhi');
      await tester.tap(find.byKey(const ValueKey('brand-form-save')));
      await tester.pumpAndSettle();
      final brand = app.brands.firstWhere((b) => b.name == 'Samruddhi');
      expect(_fieldText(tester, const ValueKey('purchase-row-0-brand')),
          contains('Samruddhi'));

      // Product picker (filtered to Samruddhi — empty) → "Add New Product".
      await tester.tap(find.byKey(const ValueKey('purchase-row-0-product')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('picker-option-0')), findsNothing);
      await tester.enterText(
          find.byKey(const ValueKey('picker-search')), 'Samruddhi 25kg');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-create-row')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('product-form-weight')), '25');
      await tester.enterText(
          find.byKey(const ValueKey('product-form-bag-price')), '1050');
      await tester.tap(find.byKey(const ValueKey('product-form-save')));
      await tester.pumpAndSettle();

      final p = app.products.firstWhere((p) => p.name == 'Samruddhi 25kg');
      expect(p.brandId, brand.id);
      expect(p.fullBagPrice, 1050);
      expect(_fieldText(tester, const ValueKey('purchase-row-0-product')),
          contains('Samruddhi 25kg'));
      // The row continues: bags field is there for the new product.
      expect(find.byKey(const ValueKey('purchase-row-0-bags')), findsOneWidget);

      // Creating the same product again from the form is refused.
      await tester.tap(find.byKey(const ValueKey('purchase-row-1-product')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('picker-search')), 'Samruddhi 25');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-create-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('product-form-brand')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Samruddhi').last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('product-form-name')), 'samruddhi 25kg');
      await tester.enterText(
          find.byKey(const ValueKey('product-form-weight')), '25');
      await tester.enterText(
          find.byKey(const ValueKey('product-form-bag-price')), '1000');
      await tester.tap(find.byKey(const ValueKey('product-form-save')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('master-form-error')))
              .data,
          contains('already exists'));
      expect(
          app.products.where((x) => x.name.toLowerCase() == 'samruddhi 25kg'),
          hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '16: changing brand clears an incompatible product; All keeps it',
        (tester) async {
      await _pump(tester, const PurchaseEntryScreen(productId: 'p1'));
      expect(_fieldText(tester, const ValueKey('purchase-row-0-product')),
          contains('Milk Booster'));

      // All Brands → no restriction → product stays. (The blank next row
      // also shows "All Brands", so pick the option in the sheet — last.)
      await tester.tap(find.byKey(const ValueKey('purchase-row-0-brand')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('सर्व ब्रँड · All Brands').last);
      await tester.pumpAndSettle();
      expect(_fieldText(tester, const ValueKey('purchase-row-0-product')),
          contains('Milk Booster'));

      // Kargil (another brand) → Milk Booster no longer fits → cleared.
      await tester.tap(find.byKey(const ValueKey('purchase-row-0-brand')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('picker-search')), 'Kargil');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-option-0')));
      await tester.pumpAndSettle();
      expect(_fieldText(tester, const ValueKey('purchase-row-0-product')),
          isNot(contains('Milk Booster')));
      expect(_fieldText(tester, const ValueKey('purchase-row-0-brand')),
          contains('Kargil'));
    });

    testWidgets('staff see no "Add New" in the pickers', (tester) async {
      final staffApp =
          (await tester.runAsync(() => bootedApp(StaffLoginRepository())))!;
      await _pump(tester, const PurchaseEntryScreen(), staffApp);
      await tester.tap(find.byKey(const ValueKey('purchase-row-0-brand')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('picker-search')), 'Nope');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('picker-create-row')), findsNothing);
      expect(find.byKey(const ValueKey('picker-create')), findsNothing);
    });

    testWidgets(
        'Sales entry: brand filter narrows the product search; All widens it',
        (tester) async {
      final app = await _pump(tester, const SalesEntryScreen());
      await tester.tap(find.byKey(const ValueKey('sales-brand-filter')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('picker-search')), 'Kargil');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-option-0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sales-next-product')));
      await tester.pumpAndSettle();
      final kargilCount = app.products.where((p) => p.brandId == 'b2').length;
      expect(find.byKey(ValueKey('picker-option-${kargilCount - 1}')),
          findsOneWidget);
      expect(find.byKey(ValueKey('picker-option-$kargilCount')), findsNothing);
      await tester.tapAt(const Offset(10, 10)); // close
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sales-brand-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('सर्व ब्रँड · All Brands').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sales-next-product')));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('${app.products.length} सापडले'), findsOneWidget);
    });
  });
}
