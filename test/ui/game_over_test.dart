import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/game/game_events.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/game/game_state.dart';
import 'package:lifetap/ui/game_screen.dart';
import 'package:lifetap/ui/settings_screen.dart';

void main() {
  testWidgets(
    'dropping the second-to-last player to 0 life shows the game-over '
    'dialog with the winner and every final life total',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(gameProvider.notifier).newGame(2, 20);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();

      final players = container.read(gameProvider).current.players;
      container
          .read(gameProvider.notifier)
          .dispatch(
            AdjustCounter(
              playerId: players[0].id,
              mode: CounterMode.life,
              delta: -20,
            ),
          );
      await tester.pump();
      await tester.pump();

      expect(find.text('Game Over'), findsOneWidget);
      expect(find.textContaining('${players[1].name} wins!'), findsOneWidget);
      expect(
        find.textContaining('${players[0].name}: 0 life (KO)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('${players[1].name}: 20 life'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'starting a new game after a game-over resets the flag so the next '
    'game-over shows again',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(gameProvider.notifier).newGame(2, 20);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();

      final firstPlayers = container.read(gameProvider).current.players;
      container
          .read(gameProvider.notifier)
          .dispatch(
            AdjustCounter(
              playerId: firstPlayers[0].id,
              mode: CounterMode.life,
              delta: -20,
            ),
          );
      await tester.pump();
      await tester.pump();
      expect(find.text('Game Over'), findsOneWidget);

      // Dismiss, then start a fresh game.
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      container.read(gameProvider.notifier).newGame(2, 20);
      await tester.pump();
      expect(find.text('Game Over'), findsNothing);

      final secondPlayers = container.read(gameProvider).current.players;
      container
          .read(gameProvider.notifier)
          .dispatch(
            AdjustCounter(
              playerId: secondPlayers[0].id,
              mode: CounterMode.life,
              delta: -20,
            ),
          );
      await tester.pump();
      await tester.pump();
      expect(find.text('Game Over'), findsOneWidget);
    },
  );

  testWidgets('the dialog never appears when Auto-KO is off, even at 0 life', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(gameProvider.notifier).newGame(2, 20);
    container.read(settingsProvider.notifier).setAutoKo(false);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    final players = container.read(gameProvider).current.players;
    container
        .read(gameProvider.notifier)
        .dispatch(
          AdjustCounter(
            playerId: players[0].id,
            mode: CounterMode.life,
            delta: -20,
          ),
        );
    await tester.pump();
    await tester.pump();

    expect(find.text('Game Over'), findsNothing);
  });
}
