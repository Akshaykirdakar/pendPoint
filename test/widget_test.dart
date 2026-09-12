import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pend_point/data/memory_repository.dart';
import 'package:pend_point/main.dart';
import 'package:pend_point/ui/screens/more_screen.dart';

void main() {
  testWidgets('app starts', (WidgetTester tester) async {
    await tester.pumpWidget(PendApp(repo: InMemoryRepository()));
    await tester.pumpAndSettle();

    expect(find.byType(PendApp), findsOneWidget);
    expect(find.text('New Sale'), findsOneWidget);

    await tester.tap(find.text('विक्री'));
    await tester.pumpAndSettle();
    expect(find.text('New Sale'), findsOneWidget);

    await tester.tap(find.text('साठा'));
    await tester.pumpAndSettle();
    expect(find.text('Inventory'), findsOneWidget);

    await tester.tap(find.text('खाते'));
    await tester.pumpAndSettle();
    expect(find.text('Credit / Khata'), findsOneWidget);

    await tester.tap(find.text('अधिक'));
    await tester.pumpAndSettle();

    // RootShell keeps every tab mounted in an IndexedStack; verify that the
    // More tab was selected, then assert its primary Marathi page heading.
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 4);
    expect(
      find.descendant(
        of: find.byType(MoreScreen),
        matching: find.text('अधिक'),
      ),
      findsOneWidget,
    );
  });
}
