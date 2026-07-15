import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/ui/game_screen.dart';

// Default 4-player layout on the 800x600 test window: zone centers, well
// clear of the corner icons and commander-damage grid.
const _zoneCenters = [
  Offset(200, 134),
  Offset(600, 134),
  Offset(200, 466),
  Offset(600, 466),
];

void main() {
  testWidgets(
    'holding a finger in every zone for 1.5s announces a winner and leaves '
    'life totals unchanged',
    (tester) async {
      var now = Duration.zero;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: GameScreen(clock: () => now)),
        ),
      );
      await tester.pump();

      expect(find.text('40'), findsNWidgets(4));

      await tester.tap(find.byKey(const ValueKey('ritual-icon')));
      await tester.pump();
      expect(find.byKey(const ValueKey('ritual-overlay')), findsOneWidget);

      final gestures = <TestGesture>[];
      for (var i = 0; i < _zoneCenters.length; i++) {
        gestures.add(
          await tester.startGesture(_zoneCenters[i], pointer: i + 1),
        );
      }

      now = const Duration(milliseconds: 1600);
      await tester.pump(const Duration(milliseconds: 1600));

      expect(
        find.byKey(const ValueKey('ritual-winner-banner')),
        findsOneWidget,
      );
      expect(
        find.text('40'),
        findsNWidgets(4),
        reason: 'holding fingers during the ritual must not change life',
      );

      for (final gesture in gestures) {
        await gesture.up();
      }

      now += const Duration(milliseconds: 2600);
      await tester.pump(const Duration(milliseconds: 2600));
      expect(find.byKey(const ValueKey('ritual-overlay')), findsNothing);
    },
  );
}
