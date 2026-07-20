import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/game/game_events.dart';
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

  testWidgets('tapping Monarch in the counters popup marks that player as the '
      'single-holder monarch', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    // Nobody holds the monarch at the start of a fresh game.
    expect(container.read(gameProvider).current.monarchId, isNull);

    // Open player 0's counters popup and tap the Monarch status tile.
    await tester.tap(find.byKey(const ValueKey('counters-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monarch'));
    await tester.pump();

    expect(container.read(gameProvider).current.monarchId, 0);
  });

  testWidgets('the top (q2) seat\'s counters button opens the popup — it is not '
      'buried under the fixed north-up commander grid', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    // A 2-player table: seat 0 is the top seat, facing down (q2). Its counters
    // button used to be seat-rotated onto the grid's screen corner, where the
    // grid stole the tap; it now sits at the fixed screen top-left corner.
    container.read(gameProvider.notifier).newGame(2, 40);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('counters-0')));
    await tester.pumpAndSettle();

    // The counters popup opened (its footer is a reliable marker).
    expect(
      find.text('Tap to increment. Hold for additional options.'),
      findsOneWidget,
    );
  });

  testWidgets('a named-counter change is a first-class history row with a '
      'signed delta chip and a result value', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    container
        .read(gameProvider.notifier)
        .dispatch(
          const AdjustNamedCounter(playerId: 0, name: 'Treasure', delta: 3),
        );
    await tester.pump();

    // Open the history sheet from the toolbar's overflow menu.
    await tester.tap(find.byKey(const ValueKey('toolbar-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    // The Treasure row carries a signed delta chip and the resulting value,
    // exactly like a poison/life row (before the fix it fell through to the
    // plain text-only entry with neither).
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('→ 3'), findsOneWidget);
  });
}
