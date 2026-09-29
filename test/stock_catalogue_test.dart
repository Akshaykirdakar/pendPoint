// Stock page → the EXISTING Catalogue (no second implementation), and the
// QR → product lookup the scanner uses stays exactly as it was.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/ui/screens/catalogue_screen.dart';
import 'package:pend_point/ui/screens/product_detail_screen.dart';
import 'package:pend_point/ui/screens/product_edit_screen.dart';
import 'package:pend_point/ui/screens/stock_screen.dart';
import 'package:pend_point/utils/theme.dart';

import 'test_support.dart';

Future<AppState> _pump(WidgetTester tester, Widget home,
    {AppState? app}) async {
  tester.view.physicalSize = const Size(360, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final a = app ?? (await tester.runAsync(bootedApp))!;
  await tester.pumpWidget(ChangeNotifierProvider.value(
      value: a,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: home)));
  await tester.pumpAndSettle();
  return a;
}

void main() {
  testWidgets('22: Stock → Catalogue opens the existing Catalogue screen',
      (tester) async {
    await _pump(tester, const StockScreen());
    await tester.tap(find.byKey(const ValueKey('stock-catalogue')));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogueScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stock: brand filter shows one brand; All Brands shows all',
      (tester) async {
    final app = await _pump(tester, const StockScreen());

    await tester.tap(find.byKey(const ValueKey('stock-brand-filter')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('picker-search')), 'Kargil');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('picker-option-0')));
    await tester.pumpAndSettle();
    final kargil = app.products.where((p) => p.brandId == 'b2');
    final godrej = app.products.where((p) => p.brandId == 'b1');
    for (final p in kargil) {
      expect(find.textContaining(p.nameMr), findsWidgets);
    }
    for (final p in godrej) {
      expect(find.textContaining(p.nameMr), findsNothing);
    }

    await tester.tap(find.byKey(const ValueKey('stock-brand-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('सर्व ब्रँड · All Brands').last);
    await tester.pumpAndSettle();
    for (final p in godrej) {
      expect(find.textContaining(p.nameMr), findsWidgets);
    }
  });

  testWidgets('Stock: staff (no owner rights) do not get the Catalogue tile',
      (tester) async {
    final staff =
        (await tester.runAsync(() => bootedApp(StaffLoginRepository())))!;
    await _pump(tester, const StockScreen(), app: staff);
    expect(find.byKey(const ValueKey('stock-catalogue')), findsNothing);
  });

  test('23: every product\'s QR still resolves to that product; unknown → none',
      () async {
    final app = await bootedApp();
    for (final p in app.products) {
      expect(app.productForQr(p.qr)?.id, p.id, reason: p.qr);
    }
    expect(app.productForQr('PEND-P1')?.id, 'p1');
    expect(app.productForQr('NOT-A-CODE'), isNull);
    expect(app.productForQr(''), isNull);
  });

  testWidgets('23: a scanned product opens its product page', (tester) async {
    final app = await _pump(tester, const SizedBox());
    final scanned = app.productForQr('PEND-P1')!;
    await _pump(tester, ProductDetailScreen(productId: scanned.id), app: app);
    expect(find.textContaining(scanned.nameMr), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('24: a catalogue product still opens from the Catalogue',
      (tester) async {
    final app = await _pump(tester, const CatalogueScreen());
    final p = app.products.first;
    await tester.tap(find.text(p.nameMr).first);
    await tester.pumpAndSettle();
    expect(find.byType(ProductEditScreen), findsOneWidget);
    expect(find.text(p.name), findsWidgets);
  });
}
