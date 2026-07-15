import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/game/game_events.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/game/game_state.dart';

void main() {
  late ProviderContainer container;
  GameNotifier notifier() => container.read(gameProvider.notifier);
  GameSession session() => container.read(gameProvider);

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  test('starts as a 4-player, 40-life game with a single history event', () {
    expect(session().current.playerCount, 4);
    expect(session().current.players.map((p) => p.id), [0, 1, 2, 3]);
    expect(session().current.players.map((p) => p.life), everyElement(40));
    expect(session().history, hasLength(1));
  });

  test('dispatch appends history and updates current', () {
    notifier().dispatch(
      const AdjustCounter(playerId: 0, mode: CounterMode.life, delta: -3),
    );

    expect(session().history, hasLength(2));
    expect(session().current.player(0).life, 37);
  });

  test('restoreFrom folds the given history into current and stores it '
      'as-is', () {
    final history = <GameEvent>[
      const NewGame(playerCount: 3, startingLife: 30),
      const AdjustCounter(playerId: 0, mode: CounterMode.life, delta: -7),
      const RenamePlayer(playerId: 1, name: 'Restored'),
    ];

    notifier().restoreFrom(history);

    expect(session().history, history);
    expect(session().current.playerCount, 3);
    expect(session().current.player(0).life, 23);
    expect(session().current.player(1).name, 'Restored');
  });

  test('undo reverses a commander-damage-with-life event exactly', () {
    notifier().newGame(2, 40);
    final before = session().current.player(0);

    notifier().dispatch(
      const AdjustCommanderDamage(playerId: 0, fromPlayerId: 1, delta: 13),
    );
    final after = session().current.player(0);
    expect(after.life, before.life - 13);
    expect(after.commanderDamage[1], 13);

    notifier().undo();
    final restored = session().current.player(0);
    expect(restored.life, before.life);
    expect(restored.commanderDamage, before.commanderDamage);
    expect(session().history, hasLength(1));
  });

  test('undo does nothing at the initial (single-event) history', () {
    notifier().undo();
    expect(session().history, hasLength(1));
    expect(session().current.playerCount, 4);
  });

  test('historyLines returns one line per event in order', () {
    notifier().newGame(2, 20);
    notifier().dispatch(
      const AdjustCounter(playerId: 0, mode: CounterMode.life, delta: 5),
    );
    notifier().dispatch(
      const AdjustCounter(playerId: 1, mode: CounterMode.poison, delta: 2),
    );

    final lines = notifier().historyLines();
    expect(lines, hasLength(3));
    expect(lines[0], contains('New game'));
    expect(lines[1], contains('life +5'));
    expect(lines[2], contains('poison +2'));
  });

  test('toggleMonarch moves the single holder and clears on re-select', () {
    notifier().newGame(4, 40);

    notifier().toggleMonarch(1);
    expect(session().current.monarchId, 1);

    notifier().toggleMonarch(2);
    expect(session().current.monarchId, 2, reason: 'moves off player 1');

    notifier().toggleMonarch(2);
    expect(
      session().current.monarchId,
      isNull,
      reason: 're-selecting the holder clears it',
    );
  });

  test('toggleInitiative is independent of the monarch', () {
    notifier().newGame(4, 40);

    notifier().toggleMonarch(0);
    notifier().toggleInitiative(3);
    expect(session().current.monarchId, 0);
    expect(session().current.initiativeId, 3);

    notifier().toggleInitiative(3);
    expect(session().current.initiativeId, isNull);
    expect(session().current.monarchId, 0, reason: 'monarch untouched');
  });

  test('cycleDayNight advances the global state and undo reverses it', () {
    notifier().newGame(2, 20);
    expect(session().current.dayNight, DayNight.none);

    notifier().cycleDayNight();
    expect(session().current.dayNight, DayNight.day);

    notifier().undo();
    expect(session().current.dayNight, DayNight.none);
  });

  test('undo of SetMonarch restores the prior holder, not just null', () {
    notifier().newGame(4, 40);

    notifier().dispatch(const SetMonarch(playerId: 0));
    notifier().dispatch(const SetMonarch(playerId: 1));
    expect(session().current.monarchId, 1);

    notifier().undo();
    expect(
      session().current.monarchId,
      0,
      reason: 'undo re-folds to the prior holder (A), not a cleared field',
    );
  });

  test('undo of SetInitiative restores the prior holder, not just null', () {
    notifier().newGame(4, 40);

    notifier().dispatch(const SetInitiative(playerId: 0));
    notifier().dispatch(const SetInitiative(playerId: 1));
    expect(session().current.initiativeId, 1);

    notifier().undo();
    expect(
      session().current.initiativeId,
      0,
      reason: 'undo re-folds to the prior holder (A), not a cleared field',
    );
  });

  test(
    'undo restores the exact prior value even when the redone event clamped',
    () {
      notifier().newGame(2, 40);

      notifier().dispatch(
        const AdjustCounter(playerId: 0, mode: CounterMode.poison, delta: 997),
      );
      expect(session().current.player(0).poison, 997);

      // +5 would reach 1002 but clamps to 999 — the real change is only +2.
      notifier().dispatch(
        const AdjustCounter(playerId: 0, mode: CounterMode.poison, delta: 5),
      );
      expect(
        session().current.player(0).poison,
        999,
        reason: 'clamped at the cap',
      );

      notifier().undo();
      expect(
        session().current.player(0).poison,
        997,
        reason: 're-folding restores the exact prior value, not 999 - 5',
      );
    },
  );

  test('dropping the last event and re-folding equals the state after one undo '
      '(re-fold invariant across event types)', () {
    notifier().newGame(4, 40);

    const events = <GameEvent>[
      AdjustCounter(playerId: 0, mode: CounterMode.life, delta: -5),
      AdjustCommanderDamage(playerId: 1, fromPlayerId: 0, delta: 7),
      SetMonarch(playerId: 2),
      AdjustNamedCounter(playerId: 3, name: 'Treasure', delta: 4),
      CycleDayNight(),
      SetInitiative(playerId: 1),
    ];
    for (final event in events) {
      notifier().dispatch(event);
    }

    // Independently fold the whole history minus its last event.
    final history = session().history;
    var expected = const GameState(players: [], startingLife: 20);
    for (final event in history.sublist(0, history.length - 1)) {
      expected = event.apply(expected);
    }

    notifier().undo();

    expect(_snapshot(session().current), _snapshot(expected));
  });
}

/// A deeply-comparable view of the observable game state, so two states can be
/// checked for equality (neither [GameState] nor [PlayerState] defines `==`).
Map<String, Object?> _snapshot(GameState s) => {
  'monarch': s.monarchId,
  'initiative': s.initiativeId,
  'dayNight': s.dayNight,
  'players': [
    for (final p in s.players)
      {
        'id': p.id,
        'life': p.life,
        'poison': p.poison,
        'energy': p.energy,
        'experience': p.experience,
        'commanderDamage': p.commanderDamage,
        'counters': p.counters,
      },
  ],
};
