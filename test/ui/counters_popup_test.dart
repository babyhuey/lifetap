import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/ui/game_screen.dart';

void main() {
  testWidgets('opening the counters popup and tapping Treasure increments the '
      "player's generic counter, and the footer is shown", (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    // Player 0 has no Treasure counter yet.
    expect(
      container.read(gameProvider).current.player(0).counters['Treasure'],
      isNull,
    );

    // Open the seat-rotated counters popup via player 0's affordance.
    await tester.tap(find.byKey(const ValueKey('counters-0')));
    await tester.pumpAndSettle();

    // The reference footer is present.
    expect(
      find.text('Tap to increment. Hold for additional options.'),
      findsOneWidget,
    );

    // Tapping the Treasure tile adds the generic counter and increments it.
    await tester.tap(find.text('Treasure').first);
    await tester.pump();

    expect(
      container.read(gameProvider).current.player(0).counters['Treasure'],
      1,
    );
  });
}
