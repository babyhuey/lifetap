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
}
