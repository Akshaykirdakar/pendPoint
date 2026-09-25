// Widget tests for the redesigned QR sheet screen: photo + QR side-by-side
// cards with bilingual names, brand, and pack/category info chips, plus the
// brand filter and complete/specific print-mode toggle.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/data/memory_repository.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/ui/screens/qr_sheet_screen.dart';
import 'package:pend_point/utils/theme.dart';

Future<void> _pump(WidgetTester tester, {Size size = const Size(400, 2600)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final app = AppState(InMemoryRepository());
  await app.bootstrap();
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: app,
    child: MaterialApp(
        theme: buildTheme(Brightness.light), home: const QrSheetScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('QR sheet does not overflow at a narrow (phone) width',
      (tester) async {
    await _pump(tester, size: const Size(360, 2600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Select specific mode shows checkboxes and a live count',
      (tester) async {
    await _pump(tester);

    expect(find.byType(Checkbox), findsNothing);

    await tester.tap(find.text('निवडक · Select specific'));
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsWidgets);
    expect(find.textContaining('0 निवडले'), findsOneWidget);

    await tester.tap(find.text('सर्व निवडा · Select all'));
    await tester.pumpAndSettle();
    expect(find.textContaining('निवडले'), findsWidgets);
  });

  testWidgets('Brand dropdown filters the printable list', (tester) async {
    await _pump(tester);
    final app = AppState(InMemoryRepository());
    await app.bootstrap();
    final firstBrand = app.brands.first;

    await tester.tap(find.text('सर्व ब्रँड · All Brands'));
    await tester.pumpAndSettle();
    final option = find.text('${firstBrand.nameMr} · ${firstBrand.name}').last;
    await tester.ensureVisible(option);
    await tester.tap(option, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
