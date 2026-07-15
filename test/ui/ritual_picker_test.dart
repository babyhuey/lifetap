import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/game/game_notifier.dart';
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

  testWidgets(
    'one zone lifting before every zone qualifies resets progress and never '
    'announces a winner',
    (tester) async {
      var now = Duration.zero;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: GameScreen(clock: () => now)),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('ritual-icon')));
      await tester.pump();

      final gestures = <TestGesture>[];
      for (var i = 0; i < _zoneCenters.length; i++) {
        gestures.add(
          await tester.startGesture(_zoneCenters[i], pointer: i + 1),
        );
      }

      now = const Duration(milliseconds: 1000);
      await tester.pump(const Duration(milliseconds: 1000));

      // Player 0 lifts early, well before the 1.5s hold window elapses.
      await gestures[0].up();
      now = const Duration(milliseconds: 1600);
      await tester.pump(const Duration(milliseconds: 1600));

      expect(find.byKey(const ValueKey('ritual-winner-banner')), findsNothing);
      expect(find.byKey(const ValueKey('ritual-overlay')), findsOneWidget);

      for (var i = 1; i < gestures.length; i++) {
        await gestures[i].up();
      }
      await tester.tap(find.byKey(const ValueKey('ritual-close')));
      await tester.pump();
      expect(find.byKey(const ValueKey('ritual-overlay')), findsNothing);
    },
  );

  testWidgets(
    'the per-player settings and counters icons are disabled while the '
    'ritual is active',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();

      final id = container.read(gameProvider).current.players.first.id;

      await tester.tap(find.byKey(const ValueKey('ritual-icon')));
      await tester.pump();

      final settingsButton = tester.widget<IconButton>(
        find.byKey(ValueKey('settings-$id')),
      );
      final countersButton = tester.widget<IconButton>(
        find.byKey(ValueKey('counters-$id')),
      );
      expect(settingsButton.onPressed, isNull);
      expect(countersButton.onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('ritual-close')));
      await tester.pump();

      final settingsAfter = tester.widget<IconButton>(
        find.byKey(ValueKey('settings-$id')),
      );
      expect(settingsAfter.onPressed, isNotNull);
    },
  );
}
