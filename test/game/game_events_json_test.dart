import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/game/game_events.dart';
import 'package:lifetap/game/game_state.dart';

GameState _newGame({int players = 2, int life = 40}) => NewGame(
  playerCount: players,
  startingLife: life,
).apply(const GameState(players: [], startingLife: 20));

/// Applies both [original] and its JSON round-trip to a fresh 2-player,
/// 40-life state and asserts they produce identical resulting state and the
/// same describe() text — GameEvent has no `==` override (unchanged by this
/// feature), so equality is verified through behavior, not identity.
void _expectRoundTrips(GameEvent original) {
  final roundTripped = eventFromJson(original.toJson());
  final before = _newGame();

  final afterOriginal = original.apply(before);
  final afterRoundTripped = roundTripped.apply(before);

  expect(
    afterRoundTripped.players.map((p) => p.toString()).toList(),
    afterOriginal.players.map((p) => p.toString()).toList(),
  );
  expect(afterRoundTripped.monarchId, afterOriginal.monarchId);
  expect(afterRoundTripped.initiativeId, afterOriginal.initiativeId);
  expect(afterRoundTripped.dayNight, afterOriginal.dayNight);
  expect(roundTripped.describe(before), original.describe(before));
}

void main() {
  test('NewGame round-trips', () {
    _expectRoundTrips(const NewGame(playerCount: 3, startingLife: 30));
  });

  test('AdjustCounter round-trips', () {
    _expectRoundTrips(
      const AdjustCounter(playerId: 0, mode: CounterMode.poison, delta: 3),
    );
  });

  test('AdjustNamedCounter round-trips', () {
    _expectRoundTrips(
      const AdjustNamedCounter(playerId: 1, name: 'Treasure', delta: 2),
    );
  });

  test('AdjustCommanderDamage round-trips', () {
    _expectRoundTrips(
      const AdjustCommanderDamage(
        playerId: 0,
        fromPlayerId: 1,
        delta: 5,
        reduceLife: false,
      ),
    );
  });

  test('RenamePlayer round-trips', () {
    _expectRoundTrips(const RenamePlayer(playerId: 0, name: 'Alice'));
  });

  test('SetCommander round-trips (both fields set)', () {
    _expectRoundTrips(
      const SetCommander(
        playerId: 0,
        commanderName: 'Atraxa',
        artUrl: 'http://art/atraxa',
      ),
    );
  });

  test('SetCommander round-trips (both fields null)', () {
    _expectRoundTrips(const SetCommander(playerId: 0));
  });

  test('RecolorPlayer round-trips', () {
    _expectRoundTrips(const RecolorPlayer(playerId: 0, color: 0xFF112233));
  });

  test('SetMonarch round-trips (set)', () {
    _expectRoundTrips(const SetMonarch(playerId: 1));
  });

  test('SetMonarch round-trips (cleared)', () {
    _expectRoundTrips(const SetMonarch());
  });

  test('SetInitiative round-trips', () {
    _expectRoundTrips(const SetInitiative(playerId: 0));
  });

  test('CycleDayNight round-trips', () {
    _expectRoundTrips(const CycleDayNight());
  });

  test('eventFromJson throws FormatException on an unknown type tag', () {
    expect(
      () => eventFromJson(const {'type': 'NotARealEvent'}),
      throwsFormatException,
    );
  });
}
