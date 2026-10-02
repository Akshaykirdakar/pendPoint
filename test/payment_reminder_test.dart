// 🔔 Payment reminders from the Credit screen: WhatsApp or SMS, to one,
// several or all customers who owe money — opened one at a time.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/models/app_settings.dart';
import 'package:pend_point/services/reminder_service.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/ui/screens/customer_screen.dart';
import 'package:pend_point/ui/screens/khata_screen.dart';
import 'package:pend_point/ui/screens/payment_reminder_screen.dart';
import 'package:pend_point/utils/formatters.dart';
import 'package:pend_point/utils/lang.dart';
import 'package:pend_point/utils/theme.dart';

import 'test_support.dart';

/// Links that would have opened WhatsApp / SMS, in order.
final opened = <Uri>[];

Future<AppState> _pump(WidgetTester tester, Widget home,
    {AppLang lang = AppLang.both,
    Future<void> Function(AppState)? prep}) async {
  tester.view.physicalSize = const Size(720, 2800); // 360 × 1400
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final app = (await tester.runAsync(bootedApp))!;
  await tester.runAsync(() => app.updateSettings((s) => s.lang = lang));
  if (prep != null) await tester.runAsync(() => prep(app));
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: app,
    child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
  ));
  await tester.pumpAndSettle();
  return app;
}

/// A customer who owes money but has no mobile number.
Future<void> _noMobileDebtor(AppState app) async {
  final cu = await app.saveCustomer(name: 'No Phone Patil', mobile: '');
  cu.outstanding = 500;
}

void main() {
  setUp(() {
    opened.clear();
    ReminderService.launch = (uri) async {
      opened.add(uri);
      return true;
    };
  });
  tearDown(() => appLang = AppLang.both);

  test('message: name, shop and amount due, in Marathi and English', () {
    final m = ReminderService.message(
        shopName: 'Pend Shop', customerName: 'रमेश पाटील', due: 2380);
    expect(m, contains('रमेश पाटील'));
    expect(m, contains('Pend Shop'));
    expect(m, contains(money(2380)));
    expect(m, contains('उधार बाकी'));
    expect(m, contains('pending balance'));
  });

  test('WhatsApp / SMS links carry the number and the message', () {
    const msg = 'Your balance is ₹2,380';
    final wa =
        ReminderService.uri(ReminderChannel.whatsApp, '98220 11223', msg)!;
    expect(wa.host, 'wa.me');
    expect(wa.path, '/919822011223');
    expect(wa.queryParameters['text'], msg);
    final sms = ReminderService.uri(ReminderChannel.sms, '98220 11223', msg)!;
    expect(sms.toString(), startsWith('sms:+919822011223?body='));
    expect(Uri.decodeComponent(sms.query.substring(5)), msg);
    expect(ReminderService.uri(ReminderChannel.sms, '', msg), isNull);
  });

  testWidgets('Credit screen → reminder → select all → WhatsApp one by one',
      (tester) async {
    final app = await _pump(tester, const KhataScreen(), prep: _noMobileDebtor);
    await tester.tap(find.byKey(const ValueKey('khata-remind')));
    await tester.pumpAndSettle();
    expect(find.byType(PaymentReminderScreen), findsOneWidget);

    final owing = app.customers.where((c) => c.outstanding > 0).toList();
    final reachable = owing
        .where((c) => ReminderService.hasValidMobile(c.mobile))
        .toList()
      ..sort((a, b) => b.outstanding.compareTo(a.outstanding));
    // Only customers with dues are listed; one with no mobile can't be picked.
    for (final c in app.customers) {
      expect(find.byKey(ValueKey('remind-row-${c.id}')),
          c.outstanding > 0 ? findsOneWidget : findsNothing,
          reason: c.name);
    }
    expect(find.textContaining('No mobile number'), findsOneWidget);
    expect(find.byKey(const ValueKey('remind-preview')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('remind-select-all')));
    await tester.pumpAndSettle();
    expect(find.textContaining('(${reachable.length})'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('remind-send')));
    await tester.pumpAndSettle();
    // The first customer's WhatsApp opened; then Next for each of the rest.
    for (var i = 0; i < reachable.length; i++) {
      expect(opened, hasLength(i + 1));
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('remind-progress')))
              .data,
          '${i + 1} / ${reachable.length} · ${reachable[i].name}');
      final u = opened[i];
      expect(u.host, 'wa.me');
      expect(u.queryParameters['text'], contains(reachable[i].name));
      expect(
          u.queryParameters['text'], contains(money(reachable[i].outstanding)));
      final next = i == reachable.length - 1 ? 'remind-done' : 'remind-next';
      await tester.tap(find.byKey(ValueKey(next)));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('${reachable.length} reminders opened'),
        findsOneWidget);
    expect(opened.map((u) => u.path).toSet(), hasLength(reachable.length));
    expect(tester.takeException(), isNull);
  });

  testWidgets('one customer by SMS', (tester) async {
    final app = await _pump(tester, const PaymentReminderScreen());
    final c1 = app.customers.firstWhere((c) => c.id == 'c1');
    await tester.tap(find.byKey(const ValueKey('remind-sms')));
    await tester.tap(find.byKey(ValueKey('remind-row-${c1.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remind-send')));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    expect(opened.single.scheme, 'sms');
    expect(Uri.decodeComponent(opened.single.query),
        contains(money(c1.outstanding)));
    expect(find.byKey(const ValueKey('remind-done')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remind-done')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 reminders opened'), findsOneWidget);
  });

  testWidgets('Stop ends the round; nothing more opens', (tester) async {
    await _pump(tester, const PaymentReminderScreen());
    await tester.tap(find.byKey(const ValueKey('remind-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remind-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remind-stop')));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    expect(find.byKey(const ValueKey('remind-progress')), findsNothing);
  });

  testWidgets('WhatsApp missing → says so, never silent', (tester) async {
    ReminderService.launch = (uri) async => false;
    final app = await _pump(tester, const PaymentReminderScreen());
    await tester
        .tap(find.byKey(ValueKey('remind-row-${app.customers.first.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remind-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not open WhatsApp'), findsOneWidget);
  });

  testWidgets('customer page: WhatsApp / SMS reminder for that customer',
      (tester) async {
    final app = await _pump(tester, const CustomerScreen(customerId: 'c1'));
    final c1 = app.customers.firstWhere((c) => c.id == 'c1');
    await tester.tap(find.byKey(const ValueKey('customer-remind-whatsapp')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('customer-remind-sms')));
    await tester.pumpAndSettle();
    expect(opened.map((u) => u.scheme), ['https', 'sms']);
    expect(
        opened.first.queryParameters['text'], contains(money(c1.outstanding)));
  });

  testWidgets('customer page with no mobile says so', (tester) async {
    late String id;
    await _pump(tester, const SizedBox(), prep: (app) async {
      await _noMobileDebtor(app);
      id = app.customers.last.id;
    });
    final app = Provider.of<AppState>(tester.element(find.byType(SizedBox)),
        listen: false);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: CustomerScreen(customerId: id))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('customer-remind-sms')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Customer mobile number is not available'),
        findsOneWidget);
    expect(opened, isEmpty);
  });

  for (final lang in AppLang.values) {
    testWidgets('[${lang.name}] reminder screen fits 360px', (tester) async {
      await _pump(tester, const PaymentReminderScreen(),
          lang: lang, prep: _noMobileDebtor);
      await tester.tap(find.byKey(const ValueKey('remind-select-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remind-send')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(lang == AppLang.en ? 'Payment reminder' : 'उधार आठवण'),
          findsOneWidget);
    });
  }
}
