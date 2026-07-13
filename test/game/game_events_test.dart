import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/game/game_events.dart';
import 'package:lifetap/game/game_state.dart';

GameState _newGame({int players = 2, int life = 20}) => NewGame(
  playerCount: players,
  startingLife: life,
).apply(const GameState(players: [], startingLife: 20));

void main() {
  group('NewGame', () {
    test('seeds N players at the starting life with distinct colors', () {
      final state = _newGame(players: 4, life: 40);

      expect(state.playerCount, 4);
      expect(state.startingLife, 40);
      expect(state.players.map((p) => p.life), everyElement(40));
      expect(state.players.map((p) => p.name), ['P1', 'P2', 'P3', 'P4']);

      final colors = state.players.map((p) => p.color).toSet();
      expect(colors.length, 4, reason: 'each seat gets a distinct color');
    });
  });

  group('AdjustCounter life', () {
    test('life is unclamped and can go negative; <= 0 is dead', () {
      var state = _newGame(life: 20);
      state = AdjustCounter(
        playerId: 0,
        mode: CounterMode.life,
        delta: -25,
      ).apply(state);

      expect(state.player(0).life, -5);
      expect(state.player(0).isDead, isTrue);
    });

    test('exactly 0 life is dead', () {
      var state = _newGame(life: 20);
      state = AdjustCounter(
        playerId: 0,
        mode: CounterMode.life,
        delta: -20,
      ).apply(state);

      expect(state.player(0).life, 0);
      expect(state.player(0).isDead, isTrue);
    });
  });

  group('AdjustCounter poison', () {
    test('clamps at 0 and does not go negative', () {
      var state = _newGame();
      state = AdjustCounter(
        playerId: 0,
        mode: CounterMode.poison,
        delta: -3,
      ).apply(state);

      expect(state.player(0).poison, 0);
    });

    test('reaching 10 poison triggers isDead', () {
      var state = _newGame();
      state = AdjustCounter(
        playerId: 0,
        mode: CounterMode.poison,
        delta: 10,
      ).apply(state);

      expect(state.player(0).poison, 10);
      expect(state.player(0).isDead, isTrue);
    });

    test('clamps at 999', () {
      var state = _newGame();
      state = AdjustCounter(
        playerId: 0,
        mode: CounterMode.poison,
        delta: 5000,
      ).apply(state);

      expect(state.player(0).poison, 999);
    });
  });

  group('AdjustCommanderDamage', () {
    test('reduces life and records damage; 21 triggers isDead', () {
      var state = _newGame(life: 40);
      state = AdjustCommanderDamage(
        playerId: 0,
        fromPlayerId: 1,
        delta: 21,
      ).apply(state);

      expect(state.player(0).life, 40 - 21);
      expect(state.player(0).commanderDamage[1], 21);
      expect(state.player(0).isDead, isTrue);
    });

    test('sub-lethal commander damage is not dead', () {
      var state = _newGame(life: 40);
      state = AdjustCommanderDamage(
        playerId: 0,
        fromPlayerId: 1,
        delta: 20,
      ).apply(state);

      expect(state.player(0).commanderDamage[1], 20);
      expect(state.player(0).isDead, isFalse);
    });

    test('reduceLife:false records damage without touching life', () {
      var state = _newGame(life: 40);
      state = AdjustCommanderDamage(
        playerId: 0,
        fromPlayerId: 1,
        delta: 5,
        reduceLife: false,
      ).apply(state);

      expect(state.player(0).commanderDamage[1], 5);
      expect(
        state.player(0).life,
        40,
        reason: 'life is unchanged when reduceLife is false',
      );
    });

    test(
      'a decrement past the 0 floor credits life by only the applied change',
      () {
        var state = _newGame(life: 40);
        state = AdjustCommanderDamage(
          playerId: 0,
          fromPlayerId: 1,
          delta: 3,
        ).apply(state);
        expect(state.player(0).commanderDamage[1], 3);
        expect(state.player(0).life, 37);

        // Decrement by 10: the counter clamps to 0 (a −3 change), so life may only
        // be credited 3 back to 40 — not the raw 10 up to 47.
        state = AdjustCommanderDamage(
          playerId: 0,
          fromPlayerId: 1,
          delta: -10,
        ).apply(state);

        expect(state.player(0).commanderDamage[1], 0);
        expect(
          state.player(0).life,
          40,
          reason:
              'life is credited the clamped change (3), not the raw delta (10)',
        );
      },
    );

    test(
      'lethality is per-opponent: 13 + 13 from two opponents is not dead',
      () {
        var state = _newGame(players: 3, life: 40);
        state = AdjustCommanderDamage(
          playerId: 0,
          fromPlayerId: 1,
          delta: 13,
        ).apply(state);
        state = AdjustCommanderDamage(
          playerId: 0,
          fromPlayerId: 2,
          delta: 13,
        ).apply(state);

        expect(state.player(0).commanderDamage[1], 13);
        expect(state.player(0).commanderDamage[2], 13);
        expect(
          state.player(0).isDead,
          isFalse,
          reason: 'only 21+ from a single opponent is lethal, not the sum',
        );
      },
    );
  });

  group('rename and recolor', () {
    test('RenamePlayer and RecolorPlayer update the target player', () {
      var state = _newGame();
      state = const RenamePlayer(playerId: 0, name: 'Alice').apply(state);
      state = const RecolorPlayer(playerId: 0, color: 0xFF00FF00).apply(state);

      expect(state.player(0).name, 'Alice');
      expect(state.player(0).color, 0xFF00FF00);
    });
  });

  group('table statuses', () {
    test('SetMonarch is single-holder: a new player moves it, not both', () {
      var state = _newGame(players: 4);
      state = const SetMonarch(playerId: 1).apply(state);
      expect(state.monarchId, 1);

      state = const SetMonarch(playerId: 2).apply(state);
      expect(state.monarchId, 2, reason: 'monarch moves off the prior holder');
      expect(state.initiativeId, isNull);
    });

    test('SetMonarch(null) clears the monarch', () {
      var state = _newGame();
      state = const SetMonarch(playerId: 0).apply(state);
      state = const SetMonarch().apply(state);
      expect(state.monarchId, isNull);
    });

    test('SetInitiative is independent of the Monarch field', () {
      var state = _newGame(players: 4);
      state = const SetMonarch(playerId: 1).apply(state);
      state = const SetInitiative(playerId: 3).apply(state);

      expect(state.monarchId, 1);
      expect(state.initiativeId, 3);
    });

    test('CycleDayNight cycles none -> day -> night -> none', () {
      var state = _newGame();
      expect(state.dayNight, DayNight.none);

      state = const CycleDayNight().apply(state);
      expect(state.dayNight, DayNight.day);
      state = const CycleDayNight().apply(state);
      expect(state.dayNight, DayNight.night);
      state = const CycleDayNight().apply(state);
      expect(state.dayNight, DayNight.none);
    });

    test('a per-player mutation preserves the global status fields', () {
      var state = _newGame(players: 4);
      state = const SetMonarch(playerId: 1).apply(state);
      state = const SetInitiative(playerId: 2).apply(state);
      state = const CycleDayNight().apply(state);

      // Life adjustment flows through replacePlayer; the game-wide statuses
      // must survive it.
      state = const AdjustCounter(
        playerId: 0,
        mode: CounterMode.life,
        delta: -3,
      ).apply(state);

      expect(state.monarchId, 1);
      expect(state.initiativeId, 2);
      expect(state.dayNight, DayNight.day);
    });

    test('NewGame resets monarch, initiative, and day/night', () {
      var state = _newGame(players: 4);
      state = const SetMonarch(playerId: 0).apply(state);
      state = const SetInitiative(playerId: 1).apply(state);
      state = const CycleDayNight().apply(state);

      state = NewGame(playerCount: 4, startingLife: 40).apply(state);

      expect(state.monarchId, isNull);
      expect(state.initiativeId, isNull);
      expect(state.dayNight, DayNight.none);
    });
  });
}
