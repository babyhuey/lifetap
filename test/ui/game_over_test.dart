import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/data/game_persistence.dart';
import 'package:lifetap/game/game_events.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/game/game_state.dart';
import 'package:lifetap/ui/game_screen.dart';
import 'package:lifetap/ui/settings_screen.dart';

/// An in-memory [GamePersistence] that returns a fixed, pre-seeded history
/// from load() — standing in for a save file already on disk when the
/// GameScreen boots. See test/ui/game_persistence_ui_test.dart's
/// `_InMemoryPersistence` for the fuller two-container version; this one
/// only needs to serve a single fixed history to a lone container.
class _FixedPersistence implements GamePersistence {
  _FixedPersistence(this.stored);

  final List<GameEvent> stored;

  @override
  Future<void> save(List<GameEvent> history) async {}

  @override
  Future<List<GameEvent>?> load() async => stored;
}

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

  testWidgets(
    'undoing a game-over and then delivering a fresh lethal hit shows the '
    'dialog again',
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
      // A harmless move before the lethal one, so history stays longer than
      // 1 event after the lethal hit is undone below — this is what makes
      // the test actually discriminate the state-derived reset (checking
      // the current alive count) from the old, buggy history-length check
      // (`history.length <= 1`), which this specific history would have
      // passed too: [NewGame, harmless, lethal] undoes to [NewGame,
      // harmless] (length 2, not <= 1), so only a real alive-count check
      // correctly re-arms the flag here.
      container
          .read(gameProvider.notifier)
          .dispatch(
            AdjustCounter(
              playerId: players[1].id,
              mode: CounterMode.life,
              delta: -1,
            ),
          );
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

      // Dismiss, then undo the lethal hit — the KO'd player is back to
      // positive life, so the game is ongoing again.
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      container.read(gameProvider.notifier).undo();
      await tester.pump();
      expect(find.text('Game Over'), findsNothing);

      // A fresh lethal hit (this time on the other player) should show the
      // dialog again, since the latch re-armed once the game left the
      // one-survivor state.
      container
          .read(gameProvider.notifier)
          .dispatch(
            AdjustCounter(
              playerId: players[1].id,
              mode: CounterMode.life,
              delta: -20,
            ),
          );
      await tester.pump();
      await tester.pump();
      expect(find.text('Game Over'), findsOneWidget);
    },
  );

  testWidgets(
    'restoring an already-finished game does not re-show the dialog on '
    'relaunch',
    (tester) async {
      final persistence = _FixedPersistence(const [
        NewGame(playerCount: 2, startingLife: 20),
        AdjustCounter(playerId: 0, mode: CounterMode.life, delta: -20),
      ]);
      final container = ProviderContainer(
        overrides: [gamePersistenceProvider.overrideWithValue(persistence)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump(); // default seed
      await tester.pump(); // async restore resolves

      expect(find.text('Game Over'), findsNothing);
    },
  );
}
