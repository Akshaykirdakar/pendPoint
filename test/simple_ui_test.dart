// The simple, picture-first UI: labels follow the language setting
// (Marathi / English / both) and the big-tile screens fit a small phone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/models/app_settings.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/ui/root_shell.dart';
import 'package:pend_point/ui/screens/bill_screen.dart';
import 'package:pend_point/utils/lang.dart';
import 'package:pend_point/utils/theme.dart';

import 'test_support.dart';

Future<AppState> _pumpShell(WidgetTester tester, AppLang lang,
    {Size size = const Size(400, 1800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => appLang = AppLang.both);
  final app = (await tester.runAsync(bootedApp))!;
  await tester.runAsync(() => app.updateSettings((s) => s.lang = lang));
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: app,
    child: MaterialApp(theme: buildTheme(Brightness.light), home: const RootShell()),
  ));
  await tester.pumpAndSettle();
  return app;
}

void main() {
  group('pickLang', () {
    test('keeps only the chosen language', () {
      expect(pickLang('बिल रद्द · Void bill', AppLang.mr), 'बिल रद्द');
      expect(pickLang('बिल रद्द · Void bill', AppLang.en), 'Void bill');
      expect(pickLang('बिल रद्द · Void bill', AppLang.both), 'बिल रद्द · Void bill');
      expect(pickLang('बिल सेव्ह झाले\nBill saved', AppLang.en), 'Bill saved');
    });

    test('numbers, amounts and mixed parts are never dropped', () {
      expect(pickLang('₹1,450 · बाकी · Due', AppLang.mr), '₹1,450 · बाकी');
      expect(pickLang('#12 · खरेदी · Purchase', AppLang.en), '#12 · Purchase');
      // A part containing both scripts stays in either language.
      expect(pickLang('WhatsApp ला उघडेल · Opens WhatsApp', AppLang.mr),
          'WhatsApp ला उघडेल');
      // Nothing to split → unchanged.
      expect(pickLang('रमेश पाटील', AppLang.en), 'रमेश पाटील');
    });
  });

  testWidgets('Marathi only: big tiles and titles show no English',
      (tester) async {
    await _pumpShell(tester, AppLang.mr);
    expect(find.byKey(const ValueKey('home-new-bill')), findsOneWidget);
    expect(find.text('नवीन बिल'), findsOneWidget);
    expect(find.text('New Sale'), findsNothing);
    expect(find.text('खरेदी'), findsOneWidget);
    expect(find.text('Purchase'), findsNothing);
    expect(find.text('मुख्य'), findsOneWidget); // bottom tab
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('English only: tiles, tabs and titles in English', (tester) async {
    await _pumpShell(tester, AppLang.en);
    expect(find.text('New Sale'), findsOneWidget);
    expect(find.text('नवीन बिल'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('मुख्य'), findsNothing);
  });

  testWidgets('Tile screens fit a 360px phone in every language', (tester) async {
    for (final lang in AppLang.values) {
      final app = await _pumpShell(tester, lang, size: const Size(360, 2400));
      for (final tab in ['1', '2', '3', '4', '0']) {
        final label = {
          '0': lang == AppLang.en ? 'Home' : 'मुख्य',
          '1': lang == AppLang.en ? 'Sell' : 'विक्री',
          '2': lang == AppLang.en ? 'Stock' : 'साठा',
          '3': lang == AppLang.en ? 'Credit' : 'खाते',
          '4': lang == AppLang.en ? 'More' : 'अधिक',
        }[tab]!;
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$lang tab $label');
      }

      app.addToCart('p1', SaleType.bag, 1);
      final bill = (await tester.runAsync(app.finalizeSale))!.bill!;
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: BillScreen(billId: bill.id, justSaved: true)),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$lang bill screen');
      expect(find.byKey(const ValueKey('bill-whatsapp')), findsOneWidget);
    }
  });
}
