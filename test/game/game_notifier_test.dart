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
    expect(session().current.players, everyElement(isA<PlayerState>()));
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
}
