import 'package:flutter_test/flutter_test.dart';

import 'package:pend_point/data/memory_repository.dart';
import 'package:pend_point/main.dart';

void main() {
  testWidgets('app starts', (WidgetTester tester) async {
    await tester.pumpWidget(PendApp(repo: InMemoryRepository()));

    expect(find.byType(PendApp), findsOneWidget);
  });
}
