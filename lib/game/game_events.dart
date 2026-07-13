import 'game_state.dart';

/// Default seat colors (ARGB) used when seeding a new game. Six distinct hues
/// so up to six seats read apart at a glance.
const List<int> defaultColors = [
  0xFFE53935, // red
  0xFF1E88E5, // blue
  0xFF43A047, // green
  0xFFFDD835, // yellow
  0xFF8E24AA, // purple
  0xFFFB8C00, // orange
];

/// Counters other than life are bounded to this range.
const int _counterMax = 999;

int _clampCounter(int value) =>
    value < 0 ? 0 : (value > _counterMax ? _counterMax : value);

/// Every mutation to the game is a [GameEvent]. State is a projection of the
/// event history, so [apply] must be pure and replaying the list from an empty
/// state must reproduce the current state exactly (this is what makes undo and
/// the history view correct).
sealed class GameEvent {
  const GameEvent();

  /// Returns a new state with this event applied to [state].
  GameState apply(GameState state);

  /// A human-readable, past-tense-ish line describing this event, evaluated
  /// against the state as it was *before* the event ran.
  String describe(GameState before);
}

/// Starts a fresh game, discarding any prior state.
class NewGame extends GameEvent {
  const NewGame({required this.playerCount, required this.startingLife});

  final int playerCount;
  final int startingLife;

  @override
  GameState apply(GameState state) {
    return GameState(
      players: [
        for (var i = 0; i < playerCount; i++)
          PlayerState(
            id: i,
            name: 'P${i + 1}',
            color: defaultColors[i % defaultColors.length],
            life: startingLife,
          ),
      ],
      startingLife: startingLife,
    );
  }

  @override
  String describe(GameState before) =>
      'New game: $playerCount players at $startingLife life';
}

/// Adjusts one of a player's counters. Life is unclamped (it can go negative);
/// poison/energy/experience are clamped to 0..999.
class AdjustCounter extends GameEvent {
  const AdjustCounter({
    required this.playerId,
    required this.mode,
    required this.delta,
  });

  final int playerId;
  final CounterMode mode;
  final int delta;

  @override
  GameState apply(GameState state) {
    final p = state.player(playerId);
    final updated = switch (mode) {
      CounterMode.life => p.copyWith(life: p.life + delta),
      CounterMode.poison => p.copyWith(poison: _clampCounter(p.poison + delta)),
      CounterMode.energy => p.copyWith(energy: _clampCounter(p.energy + delta)),
      CounterMode.experience => p.copyWith(
        experience: _clampCounter(p.experience + delta),
      ),
    };
    return state.replacePlayer(updated);
  }

  @override
  String describe(GameState before) {
    final p = before.player(playerId);
    final sign = delta >= 0 ? '+' : '';
    return '${p.name} ${mode.name} $sign$delta';
  }
}

/// Adjusts one of a player's generic named counters (Treasure, Storm, Rad, …),
/// creating the entry on first touch. Clamped to 0..999, like the other
/// secondary counters.
class AdjustNamedCounter extends GameEvent {
  const AdjustNamedCounter({
    required this.playerId,
    required this.name,
    required this.delta,
  });

  final int playerId;
  final String name;
  final int delta;

  @override
  GameState apply(GameState state) {
    final p = state.player(playerId);
    final current = p.counters[name] ?? 0;
    final updated = p.copyWith(
      counters: {...p.counters, name: _clampCounter(current + delta)},
    );
    return state.replacePlayer(updated);
  }

  @override
  String describe(GameState before) {
    final p = before.player(playerId);
    final sign = delta >= 0 ? '+' : '';
    return '${p.name} $name $sign$delta';
  }
}

/// Records commander damage dealt to [playerId] by [fromPlayerId]'s commander.
/// When [reduceLife] is true (the default rule) it also subtracts [delta] from
/// the receiving player's life; when false only the counter changes, so the
/// "Commander damage life loss" setting can turn the life side off.
class AdjustCommanderDamage extends GameEvent {
  const AdjustCommanderDamage({
    required this.playerId,
    required this.fromPlayerId,
    required this.delta,
    this.reduceLife = true,
  });

  final int playerId;
  final int fromPlayerId;
  final int delta;
  final bool reduceLife;

  @override
  GameState apply(GameState state) {
    final p = state.player(playerId);
    final current = p.commanderDamage[fromPlayerId] ?? 0;
    final next = current + delta;
    final clamped = next < 0 ? 0 : next;
    final applied = clamped - current; // differs from delta only at the 0 floor
    final updated = p.copyWith(
      commanderDamage: {...p.commanderDamage, fromPlayerId: clamped},
      life: reduceLife ? p.life - applied : p.life,
    );
    return state.replacePlayer(updated);
  }

  @override
  String describe(GameState before) {
    final target = before.player(playerId);
    final source = before.player(fromPlayerId);
    final sign = delta >= 0 ? '+' : '';
    return '${source.name} cmdr dmg to ${target.name} $sign$delta';
  }
}

/// Renames a player.
class RenamePlayer extends GameEvent {
  const RenamePlayer({required this.playerId, required this.name});

  final int playerId;
  final String name;

  @override
  GameState apply(GameState state) =>
      state.replacePlayer(state.player(playerId).copyWith(name: name));

  @override
  String describe(GameState before) =>
      '${before.player(playerId).name} renamed to $name';
}

/// Sets a player's commander name and resolved art URL (either may be null to
/// clear it). Art resolution happens in the UI before dispatch, so [apply]
/// stays pure.
class SetCommander extends GameEvent {
  const SetCommander({required this.playerId, this.commanderName, this.artUrl});

  final int playerId;
  final String? commanderName;
  final String? artUrl;

  @override
  GameState apply(GameState state) => state.replacePlayer(
    state
        .player(playerId)
        .copyWith(commanderName: commanderName, artUrl: artUrl),
  );

  @override
  String describe(GameState before) =>
      '${before.player(playerId).name} commander → $commanderName';
}

/// Recolors a player.
class RecolorPlayer extends GameEvent {
  const RecolorPlayer({required this.playerId, required this.color});

  final int playerId;
  final int color;

  @override
  GameState apply(GameState state) =>
      state.replacePlayer(state.player(playerId).copyWith(color: color));

  @override
  String describe(GameState before) =>
      '${before.player(playerId).name} recolored';
}

/// Sets the single-holder Monarch to [playerId], or clears it when null.
/// Because the holder is one game-wide field, moving it to a new player
/// automatically takes it off whoever held it before.
class SetMonarch extends GameEvent {
  const SetMonarch({this.playerId});

  final int? playerId;

  @override
  GameState apply(GameState state) => state.copyWith(monarchId: playerId);

  @override
  String describe(GameState before) => playerId == null
      ? 'Monarch cleared'
      : '${before.player(playerId!).name} became monarch';
}

/// Sets the single-holder Initiative to [playerId], or clears it when null.
/// Independent of the Monarch field, same single-holder move semantics.
class SetInitiative extends GameEvent {
  const SetInitiative({this.playerId});

  final int? playerId;

  @override
  GameState apply(GameState state) => state.copyWith(initiativeId: playerId);

  @override
  String describe(GameState before) => playerId == null
      ? 'Initiative cleared'
      : '${before.player(playerId!).name} took the initiative';
}

/// Advances the table-wide day/night state one step: none → day → night → none.
class CycleDayNight extends GameEvent {
  const CycleDayNight();

  @override
  GameState apply(GameState state) =>
      state.copyWith(dayNight: _nextDayNight(state.dayNight));

  @override
  String describe(GameState before) =>
      'Day/Night: ${_nextDayNight(before.dayNight).name}';
}

/// The next state in the day/night cycle.
DayNight _nextDayNight(DayNight current) => switch (current) {
  DayNight.none => DayNight.day,
  DayNight.day => DayNight.night,
  DayNight.night => DayNight.none,
};
