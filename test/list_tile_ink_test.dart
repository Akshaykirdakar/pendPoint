// ListTile rows inside the rounded card look must have their own Material
// ancestor (InkCard) — otherwise Flutter reports "ListTile background color
// or ink splashes may be invisible" and the ripple is hidden by the card.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/ui/screens/branch_edit_screen.dart';
import 'package:pend_point/ui/screens/supplier_edit_screen.dart';
import 'package:pend_point/ui/widgets/common.dart';
import 'package:pend_point/utils/theme.dart';

import 'test_support.dart';

/// Collects every FlutterError reported while [body] runs.
Future<List<String>> _reported(Future<void> Function() body) async {
  final errors = <String>[];
  final old = FlutterError.onError;
  FlutterError.onError = (d) => errors.add(d.exceptionAsString());
  try {
    await body();
  } finally {
    FlutterError.onError = old;
  }
  return errors;
}

Widget _app(Widget body) => MaterialApp(
    theme: buildTheme(Brightness.light), home: Scaffold(body: body));

var switched = false;
var tapped = 0;

/// The same kind of rows as Settings → Inventory Alerts.
Widget rows() => Column(mainAxisSize: MainAxisSize.min, children: [
      StatefulBuilder(
          builder: (context, setState) => SwitchListTile(
              key: const ValueKey('switch'),
              title: const Text('Expiry alerts'),
              value: switched,
              onChanged: (v) => setState(() => switched = v))),
      ListTile(
          key: const ValueKey('tile'),
          title: const Text('Row'),
          onTap: () => tapped++),
    ]);

void main() {
  const warning = 'ListTile background color or ink splashes may be invisible';

  testWidgets('the old decorated-Container card DOES trigger the warning',
      (tester) async {
    // Control: proves this test can see the problem.
    final errors = await _reported(() async {
      await tester.pumpWidget(_app(Builder(
          builder: (context) =>
              Container(decoration: cardDecoration(context), child: rows()))));
    });
    expect(errors.join('\n'), contains(warning));
  });

  testWidgets('InkCard: no warning, ink on the card, taps and switch work',
      (tester) async {
    switched = false;
    tapped = 0;
    final errors = await _reported(() async {
      await tester.pumpWidget(_app(Padding(
          padding: const EdgeInsets.all(16), child: InkCard(child: rows()))));
    });
    expect(errors, isEmpty);

    // Same rounded card look: background + border + radius + shadow.
    final box = tester.widget<DecoratedBox>(find
        .ancestor(
            of: find.byType(Material).last, matching: find.byType(DecoratedBox))
        .first);
    final deco = box.decoration as BoxDecoration;
    expect(deco.color, isNotNull);
    expect(deco.border, isNotNull);
    expect(deco.borderRadius, isNotNull);
    expect(deco.boxShadow, isNotEmpty);

    // The rows' nearest Material is the card's own, clipped to its corners.
    final m = Material.of(tester.element(find.byKey(const ValueKey('tile'))));
    final mat = tester.widget<Material>(find
        .ancestor(
            of: find.byKey(const ValueKey('tile')),
            matching: find.byType(Material))
        .first);
    expect(mat.type, MaterialType.transparency);
    expect(mat.clipBehavior, Clip.antiAlias);
    expect(m, isNotNull);

    // Ripple + tap behaviour.
    await tester.tap(find.byKey(const ValueKey('tile')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(InkWell), findsWidgets);
    await tester.pumpAndSettle();
    expect(tapped, 1);
    await tester.tap(find.byKey(const ValueKey('switch')));
    await tester.pumpAndSettle();
    expect(switched, isTrue);
  });

  testWidgets('screens with SwitchListTile rows report no ink warning',
      (tester) async {
    final app = (await tester.runAsync(bootedApp))!;
    for (final screen in <Widget>[
      BranchEditScreen(branchId: app.branches.first.id),
      SupplierEditScreen(supplierId: app.suppliers.first.id),
    ]) {
      final errors = await _reported(() async {
        await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
            value: app,
            child: MaterialApp(
                theme: buildTheme(Brightness.light), home: screen)));
        await tester.pumpAndSettle();
      });
      expect(errors.where((e) => e.contains(warning)), isEmpty,
          reason: '${screen.runtimeType}');
    }
  });
}
