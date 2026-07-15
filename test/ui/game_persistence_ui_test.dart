import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/data/game_persistence.dart';
import 'package:lifetap/game/game_events.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/game/game_state.dart';
import 'package:lifetap/ui/game_screen.dart';

/// An in-memory [GamePersistence] two independent [ProviderContainer]s can
/// share, standing in for the real SharedPreferences-backed store surviving
/// an app restart.
class _InMemoryPersistence implements GamePersistence {
  List<GameEvent>? stored;

  @override
  Future<void> save(List<GameEvent> history) async {
    stored = List.of(history);
  }

  @override
  Future<List<GameEvent>?> load() async => stored;
}

void main() {
  testWidgets(
    'a new GameScreen instance resumes the prior session instead of the '
    'default fresh game',
    (tester) async {
      final shared = _InMemoryPersistence();

      // First "app session": play a few moves.
      final firstContainer = ProviderContainer(
        overrides: [gamePersistenceProvider.overrideWithValue(shared)],
      );
      addTearDown(firstContainer.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: firstContainer,
          // Keyed so the second pumpWidget below (a distinct key) is treated
          // as a brand-new widget rather than an update of this one — an
          // unkeyed GameScreen would have its State reused across both
          // pumps, which never re-runs initState and so never restores.
          child: MaterialApp(home: GameScreen(key: UniqueKey())),
        ),
      );
      await tester.pump();

      final id = firstContainer.read(gameProvider).current.players.first.id;
      firstContainer
          .read(gameProvider.notifier)
          .dispatch(
            AdjustCounter(playerId: id, mode: CounterMode.life, delta: -9),
          );
      // Let the ref.listen save side effect run.
      await tester.pump();

      // "Kill and relaunch": a fresh container/widget tree, same persistence.
      final secondContainer = ProviderContainer(
        overrides: [gamePersistenceProvider.overrideWithValue(shared)],
      );
      addTearDown(secondContainer.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: secondContainer,
          child: MaterialApp(home: GameScreen(key: UniqueKey())),
        ),
      );
      await tester.pump(); // default seed
      await tester.pump(); // async restore resolves

      expect(secondContainer.read(gameProvider).current.player(id).life, 31);
    },
  );

  testWidgets('with nothing saved, a GameScreen boots the default fresh '
      'game', (tester) async {
    final shared = _InMemoryPersistence();
    final container = ProviderContainer(
      overrides: [gamePersistenceProvider.overrideWithValue(shared)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(container.read(gameProvider).current.playerCount, 4);
    expect(container.read(gameProvider).current.players.first.life, 40);
  });

  testWidgets(
    'an unfoldable saved history (referencing a player no NewGame created) '
    'falls back to the default fresh game instead of crashing',
    (tester) async {
      final shared = _InMemoryPersistence()
        ..stored = const [
          NewGame(playerCount: 2, startingLife: 20),
          AdjustCounter(playerId: 5, mode: CounterMode.life, delta: -3),
        ];
      final container = ProviderContainer(
        overrides: [gamePersistenceProvider.overrideWithValue(shared)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(); // async restore resolves (and fails to fold)

      expect(container.read(gameProvider).current.playerCount, 4);
      expect(container.read(gameProvider).current.players.first.life, 40);
    },
  );
}
