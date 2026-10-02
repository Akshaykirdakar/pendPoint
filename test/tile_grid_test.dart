// TileGrid must never ask for a negative tile width — seen on web when the
// available width was briefly smaller than the gaps between tiles.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pend_point/ui/widgets/tiles.dart';

void main() {
  for (final width in [0.0, 6.0, 14.0, 360.0]) {
    testWidgets('3-column grid in a ${width}px space lays out', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: width,
            child: TileGrid(columns: 3, gap: 10, [
              for (var i = 0; i < 4; i++) const SizedBox(height: 20),
            ]),
          ),
        ),
      ));
      // Only the negative-constraints assertion matters here; a tiny box
      // may still overflow visually, which is not what this guards.
      final e = tester.takeException();
      expect(e?.toString() ?? '', isNot(contains('negative')));
    });
  }
}
