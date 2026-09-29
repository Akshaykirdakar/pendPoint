// Font size × language × colour theme: every combination renders the main
// screens on a 360×640 phone without overflow; themes stay readable and keep
// success / warning / error / disabled states distinguishable.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/data/memory_repository.dart';
import 'package:pend_point/main.dart';
import 'package:pend_point/models/app_settings.dart';
import 'package:pend_point/models/bill.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/state/purchase_draft.dart';
import 'package:pend_point/ui/root_shell.dart';
import 'package:pend_point/ui/screens/bill_screen.dart';
import 'package:pend_point/ui/screens/checkout_screen.dart';
import 'package:pend_point/ui/screens/purchase_detail_screen.dart';
import 'package:pend_point/ui/screens/purchase_entry_screen.dart';
import 'package:pend_point/ui/screens/sales_entry_screen.dart';
import 'package:pend_point/ui/widgets/appearance_settings.dart';
import 'package:pend_point/ui/widgets/common.dart';
import 'package:pend_point/ui/widgets/pend_scaffold.dart';
import 'package:pend_point/utils/lang.dart';
import 'package:pend_point/utils/theme.dart';

import 'test_support.dart';

/// Records saved settings (what would go to Firestore meta/settings).
class _SettingsRepo extends InMemoryRepository {
  final saved = <Map<String, dynamic>>[];
  @override
  Future<void> saveSettings(AppSettings settings) async =>
      saved.add(settings.toMap());
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

double _hue(Color c) => HSVColor.fromColor(c).hue;
double _hueGap(Color a, Color b) {
  final d = (_hue(a) - _hue(b)).abs() % 360;
  return math.min(d, 360 - d);
}

/// A shop with a purchase (with photo ref), a saved bill, and a cart with a
/// bag line + a kg line at a changed rate, paid by a cash + credit split.
Future<({AppState app, String billId, String purchaseId})> _shop(
    WidgetTester tester) async {
  final app = (await tester.runAsync(bootedApp))!;
  final res = (await tester.runAsync(() => app.savePurchase(
      supplierId: app.suppliers.first.id,
      supplierBillNo: 'INV-77',
      lines: [
        PurchaseLineInput(
            productId: 'p1',
            bags: 8,
            rate: 1000,
            batchNo: 'AP-1',
            expiry: inDays(60))
      ],
      // tiny payload; the detail screen only shows the button
      photo: BillPhotoChange.replace(
          Uint8List.fromList(List.filled(16, 7)), 'jpg'))))!;
  expect(res.ok, isTrue, reason: res.error);
  app.addToCart('p1', SaleType.bag, 1);
  app.setCartCustomer('c1');
  app.payments
    ..clear()
    ..add(Payment(PayMode.credit, app.cartTotal));
  final bill = (await tester.runAsync(app.finalizeSale))!.bill!;
  app.addToCart('p1', SaleType.bag, 2);
  app.addToCart('p1', SaleType.kg, 12.5);
  app.setLineRate(1, app.cart[1].rate - 1);
  app.setCartCustomer('c1');
  app.payments
    ..clear()
    ..add(Payment(PayMode.cash, app.cartTotal));
  app.addSplitPayment();
  app.setPayment(1, amount: 500);
  return (app: app, billId: bill.id, purchaseId: res.purchase!.id);
}

Future<void> _show(WidgetTester tester, AppState app, Widget home,
    {AppColorTheme theme = AppColorTheme.green,
    Brightness brightness = Brightness.light}) async {
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: app,
    child: MaterialApp(
      theme: buildTheme(brightness, theme),
      builder: (context, child) =>
          AppTextScale(fontSize: app.settings.fontSize, child: child!),
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  tearDown(() => appLang = AppLang.both);

  // 25–29 + 34–36: every font size in every language, on a 360px phone.
  for (final lang in AppLang.values) {
    for (final font in AppFontSize.values) {
      testWidgets('${lang.name} + ${font.name}: main screens fit 360px',
          (tester) async {
        _phone(tester);
        final s = await _shop(tester);
        s.app.settings
          ..lang = lang
          ..fontSize = font;
        appLang = lang;
        final screens = <String, Widget>{
          'shell (all tabs)': const RootShell(),
          'sales entry': const SalesEntryScreen(),
          'checkout (split)': const CheckoutScreen(),
          'purchase entry': const PurchaseEntryScreen(productId: 'p1'),
          'purchase detail': PurchaseDetailScreen(purchaseId: s.purchaseId),
          'bill saved': BillScreen(billId: s.billId, justSaved: true),
          'settings: appearance': PendScaffold(
              titleMr: 'सेटिंग्ज',
              titleEn: 'Settings',
              body: AppearanceSettings(app: s.app)),
        };
        for (final e in screens.entries) {
          await _show(tester, s.app, e.value);
          // The text really is scaled by the setting.
          final scaler =
              MediaQuery.of(tester.element(find.byWidget(e.value))).textScaler;
          expect(scaler.scale(10), closeTo(10 * font.scale, 0.001),
              reason: e.key);
          expect(tester.takeException(), isNull, reason: e.key);
        }
      });
    }
  }

  testWidgets('font size + theme are wired into the real app (PendApp)',
      (tester) async {
    _phone(tester);
    final repo = _SettingsRepo();
    await tester.pumpWidget(PendApp(repo: repo));
    await tester.pumpAndSettle();
    final app = Provider.of<AppState>(tester.element(find.byType(RootShell)),
        listen: false);
    double scaleNow() =>
        MediaQuery.of(tester.element(find.byType(RootShell)))
            .textScaler
            .scale(10) /
        10;
    Color brandNow() =>
        Theme.of(tester.element(find.byType(RootShell))).colorScheme.primary;

    expect(scaleNow(), closeTo(1.0, 0.001)); // Medium by default
    expect(brandNow(), PendColors.light.brand); // Green = original look

    await app.updateSettings((s) => s
      ..fontSize = AppFontSize.extraLarge
      ..colorTheme = AppColorTheme.purple);
    await tester.pumpAndSettle();
    expect(scaleNow(), closeTo(1.3, 0.001));
    expect(
        brandNow(), BrandPalette.of(AppColorTheme.purple, dark: false).brand);
    // 31: persisted with the other shop settings.
    expect(repo.saved.last['fontSize'], 'extraLarge');
    expect(repo.saved.last['colorTheme'], 'purple');
    final back = AppSettings.fromMap(repo.saved.last);
    expect(back.fontSize, AppFontSize.extraLarge);
    expect(back.colorTheme, AppColorTheme.purple);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings chips change font size and theme at once',
      (tester) async {
    // 360 wide; tall enough that every chip is on screen at Extra Large.
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = (await tester.runAsync(() => bootedApp(_SettingsRepo())))!;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: Consumer<AppState>(
        builder: (context, a, _) => MaterialApp(
          theme: buildTheme(Brightness.light, a.settings.colorTheme),
          builder: (context, child) =>
              AppTextScale(fontSize: a.settings.fontSize, child: child!),
          home: PendScaffold(
              titleMr: 'सेटिंग्ज',
              titleEn: 'Settings',
              body: AppearanceSettings(app: a)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    for (final f in AppFontSize.values) {
      await tester.tap(find.byKey(ValueKey('font-size-${f.name}')));
      await tester.pumpAndSettle();
      expect(app.settings.fontSize, f);
      expect(
          MediaQuery.of(tester
                  .element(find.byKey(const ValueKey('font-size-sample'))))
              .textScaler
              .scale(10),
          closeTo(10 * f.scale, 0.001));
    }
    for (final t in AppColorTheme.values) {
      await tester.ensureVisible(find.byKey(ValueKey('color-theme-${t.name}')));
      await tester.tap(find.byKey(ValueKey('color-theme-${t.name}')));
      await tester.pumpAndSettle();
      expect(app.settings.colorTheme, t);
      expect(
          Theme.of(tester
                  .element(find.byKey(const ValueKey('font-size-sample'))))
              .colorScheme
              .primary,
          BrandPalette.of(t, dark: false).brand);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('34–36: Settings labels follow the language', (tester) async {
    _phone(tester);
    final app = (await tester.runAsync(bootedApp))!;
    for (final (lang, small, green) in [
      (AppLang.mr, 'छोटा', 'हिरवा'),
      (AppLang.en, 'Small', 'Green'),
      (AppLang.both, 'छोटा · Small', 'हिरवा · Green'),
    ]) {
      app.settings.lang = lang;
      appLang = lang;
      await _show(
          tester,
          app,
          PendScaffold(
              titleMr: 'सेटिंग्ज',
              titleEn: 'Settings',
              body: AppearanceSettings(app: app)));
      expect(find.text(small), findsOneWidget, reason: lang.name);
      expect(find.text(green), findsOneWidget, reason: lang.name);
    }
  });

  group('colour themes', () {
    for (final theme in AppColorTheme.values) {
      for (final b in Brightness.values) {
        final base = b == Brightness.dark ? PendColors.dark : PendColors.light;
        final pc = base.themed(theme);

        test('32: ${theme.name}/${b.name} is readable', () {
          expect(_contrast(pc.brandInk, pc.brand), greaterThanOrEqualTo(4.5),
              reason: 'text on brand (app bar, buttons)');
          expect(_contrast(pc.accentInk, pc.accent), greaterThanOrEqualTo(4.5),
              reason: 'text on the main action button');
          expect(_contrast(pc.brand, pc.surface), greaterThanOrEqualTo(3),
              reason: 'brand-coloured totals / selected tab on cards');
          expect(_contrast(pc.ink, pc.surface), greaterThanOrEqualTo(7));
          expect(_contrast(pc.critical, pc.surface), greaterThanOrEqualTo(3),
              reason: 'red error text stays visible');
        });

        test('33: ${theme.name}/${b.name} keeps semantic colours', () {
          // Success / warning / error never change with the theme…
          expect(pc.good, base.good);
          expect(pc.warning, base.warning);
          expect(pc.critical, base.critical);
          expect(pc.serious, base.serious);
          // …stay clearly different from each other…
          expect(_hueGap(pc.good, pc.critical), greaterThan(60));
          expect(_hueGap(pc.good, pc.warning), greaterThan(40));
          expect(_hueGap(pc.warning, pc.critical), greaterThan(25));
          // …and the brand never looks like an error.
          expect(_hueGap(pc.brand, pc.critical), greaterThan(20));
          // Selected tab (brand) vs unselected (muted) are clearly apart.
          expect(_contrast(pc.brand, pc.muted), greaterThan(1.2));
          expect(pc.brand, isNot(pc.muted));
        });
      }
    }

    testWidgets('30+33: each theme loads; disabled buttons look disabled',
        (tester) async {
      _phone(tester);
      final app = (await tester.runAsync(bootedApp))!;
      for (final theme in AppColorTheme.values) {
        for (final b in Brightness.values) {
          await _show(
              tester,
              app,
              Scaffold(
                  body: Column(children: [
                BigButton.brand('On', key: const ValueKey('on'), onTap: () {}),
                const BigButton.brand('Off', key: ValueKey('off')),
                const Expanded(child: RootShell()),
              ])),
              theme: theme,
              brightness: b);
          final ctx = tester.element(find.byKey(const ValueKey('on')));
          final c = ctx.c;
          expect(Theme.of(ctx).colorScheme.primary,
              BrandPalette.of(theme, dark: b == Brightness.dark).brand);
          Material mat(String k) => tester.widget<Material>(find
              .descendant(
                  of: find.byKey(ValueKey(k)), matching: find.byType(Material))
              .first);
          Text label(String k) => tester.widget<Text>(find.descendant(
              of: find.byKey(ValueKey(k)), matching: find.byType(Text)));
          expect(mat('on').color, c.brand);
          expect(mat('off').color, isNot(c.brand));
          expect(label('off').style!.color, c.muted);
          expect(label('on').style!.color, c.brandInk);
          expect(tester.takeException(), isNull,
              reason: '${theme.name}/${b.name}');
        }
      }
    });
  });
}
