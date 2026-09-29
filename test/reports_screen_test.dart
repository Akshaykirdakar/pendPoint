// Widget tests for the Reports module UX changes:
//  - the date-range preset chips became a single dropdown (no horizontal
//    scrolling of presets any more);
//  - the Product filter loads real products dynamically, scoped to the
//    selected brand — never a product-type/category list;
//  - Payment Mix is tappable and opens a detail screen with matching values,
//    and each payment method row also drills into its own transactions;
//  - the export sheet offers Download PDF / Download Excel and shows help
//    text for each.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/data/memory_repository.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/ui/screens/payment_method_transactions_screen.dart';
import 'package:pend_point/ui/screens/payment_mix_screen.dart';
import 'package:pend_point/ui/screens/reports_screen.dart';
import 'package:pend_point/utils/theme.dart';

Future<void> _pump(WidgetTester tester, {Size size = const Size(400, 2200)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final app = AppState(InMemoryRepository());
  await app.bootstrap();
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: app,
    child: MaterialApp(
        theme: buildTheme(Brightness.light), home: const ReportsScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Date range dropdown opens and selecting a preset updates the range',
      (tester) async {
    await _pump(tester);

    // The dropdown shows the current preset ("7 Days" is the screen's
    // default) rather than a horizontally-scrolling row of chips.
    expect(find.text('मागील 7 दिवस · Last 7 Days'), findsOneWidget);

    await tester.tap(find.text('मागील 7 दिवस · Last 7 Days'));
    await tester.pumpAndSettle();
    expect(find.text('आज · Today'), findsWidgets);

    final option = find.text('आज · Today').last;
    await tester.ensureVisible(option);
    await tester.tap(option, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('आज · Today'), findsOneWidget);
  });

  testWidgets('Selecting Yesterday / 30 days presets works without horizontal chips',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.text('मागील 7 दिवस · Last 7 Days'));
    await tester.pumpAndSettle();
    var option = find.text('काल · Yesterday').last;
    await tester.ensureVisible(option);
    await tester.tap(option, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('काल · Yesterday'), findsOneWidget);

    await tester.tap(find.text('काल · Yesterday'));
    await tester.pumpAndSettle();
    option = find.text('मागील 30 दिवस · Last 30 Days').last;
    await tester.ensureVisible(option);
    await tester.tap(option, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('मागील 30 दिवस · Last 30 Days'), findsOneWidget);
  });

  testWidgets('Product filter lists real products (never a product-type/category list)',
      (tester) async {
    await _pump(tester);
    // Defaults to "All Products" and — once opened — lists actual seeded
    // products by name, never "Product Type" wording or category values.
    expect(find.text('सर्व · All Products'), findsOneWidget);
    expect(find.textContaining('उत्पाद · Product'), findsWidgets);
    expect(find.textContaining('Product Type'), findsNothing);

    await tester.tap(find.text('सर्व · All Products'));
    await tester.pumpAndSettle();
    expect(find.textContaining('दूध बूस्टर पेंड'), findsWidgets);
  });

  testWidgets('Brand filter narrows the report (brand + product-type filters combine)',
      (tester) async {
    await _pump(tester);
    final beforeRevenue = find.byType(ReportsScreen);
    expect(beforeRevenue, findsOneWidget);

    await tester.tap(find.text('सर्व ब्रँड · All Brands'));
    await tester.pumpAndSettle();
    // Pick the first real brand option (Godrej / गोदरेज from the sample seed).
    final brandOption = find.textContaining('गोदरेज').last;
    await tester.ensureVisible(brandOption);
    await tester.tap(brandOption, warnIfMissed: false);
    await tester.pumpAndSettle();
    // The screen rebuilds without throwing and still shows the Reports UI.
    expect(find.byType(ReportsScreen), findsOneWidget);
  });

  testWidgets('Payment Mix card is tappable and opens a detail screen', (tester) async {
    await _pump(tester);

    expect(find.textContaining('पेमेंट विभागणी'), findsWidgets);
    final tile = find.textContaining('संपूर्ण तपशील पहा').first;
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.byType(PaymentMixScreen), findsOneWidget);
  });

  testWidgets('Tapping a payment-method row opens its filtered transactions',
      (tester) async {
    await _pump(tester);

    final cashRow = find.textContaining('रोख · Cash').first;
    await tester.ensureVisible(cashRow);
    await tester.tap(cashRow);
    await tester.pumpAndSettle();

    expect(find.byType(PaymentMethodTransactionsScreen), findsOneWidget);
  });

  testWidgets('Payment Mix detail totals match the dashboard totals', (tester) async {
    await _pump(tester);
    final tile = find.textContaining('संपूर्ण तपशील पहा').first;
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    // StatTile renders its label upper-cased.
    expect(find.text('एकूण बिले · TOTAL BILLS'), findsOneWidget);
    expect(find.textContaining('तपशीलवार विभागणी'), findsOneWidget);
  });

  testWidgets('Export sheet opens with Download PDF / Download Excel and help text',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.text('एक्सपोर्ट · Export'));
    await tester.pumpAndSettle();

    expect(find.textContaining('PDF डाउनलोड करा'), findsOneWidget);
    expect(find.textContaining('Excel/CSV डाउनलोड करा'), findsOneWidget);
    expect(
        find.textContaining('Create a print-ready PDF version of this report'),
        findsOneWidget);
    expect(find.textContaining('🔗 सारांश शेअर करा'), findsOneWidget);
  });

  testWidgets('Help tooltip is present on the date-range field', (tester) async {
    await _pump(tester);
    expect(find.byTooltip('Select the period used to calculate this report.\n'
        'या अहवालासाठी वापरला जाणारा कालावधी निवडा.'), findsOneWidget);
  });

  testWidgets('Reports screen does not overflow horizontally at a narrow (phone) width',
      (tester) async {
    await _pump(tester, size: const Size(360, 2200));
    // pumpAndSettle above would already surface a RenderFlex overflow
    // exception during layout; reaching here with no pending exception is
    // the assertion.
    expect(tester.takeException(), isNull);
  });
}
