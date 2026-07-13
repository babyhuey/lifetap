import 'package:flutter/foundation.dart';

enum CounterMode { life, poison, energy, experience }

/// Sentinel so [PlayerState.copyWith] can tell "leave unchanged" apart from
/// "set to null" for the nullable commander fields.
const Object _unset = Object();

@immutable
class PlayerState {
  const PlayerState({
    required this.id,
    required this.name,
    required this.color,
    this.life = 20,
    this.poison = 0,
    this.energy = 0,
    this.experience = 0,
    this.commanderDamage = const {},
    this.counters = const {},
    this.commanderName,
    this.artUrl,
  });

  final int id;
  final String name;
  final int color; // ARGB
  final int life;
  final int poison;
  final int energy;
  final int experience;

  /// Damage taken from each opponent's commander, keyed by opponent id.
  final Map<int, int> commanderDamage;

  /// Generic named increment counters (Treasure, Storm, Rad, …), keyed by
  /// counter name. Separate from the fixed poison/energy/experience fields so
  /// arbitrary counters can be added without new state fields.
  final Map<String, int> counters;

  /// The player's commander card name, or null if none has been set.
  final String? commanderName;

  /// Resolved commander art URL used as the zone background, or null.
  final String? artUrl;

  int counter(CounterMode mode) => switch (mode) {
    CounterMode.life => life,
    CounterMode.poison => poison,
    CounterMode.energy => energy,
    CounterMode.experience => experience,
  };

  /// A player is out at 0 or fewer life, 10+ poison, or 21+ commander damage
  /// from any single opponent.
  bool get isDead =>
      life <= 0 || poison >= 10 || commanderDamage.values.any((d) => d >= 21);

  PlayerState copyWith({
    String? name,
    int? color,
    int? life,
    int? poison,
    int? energy,
    int? experience,
    Map<int, int>? commanderDamage,
    Map<String, int>? counters,
    Object? commanderName = _unset,
    Object? artUrl = _unset,
  }) {
    return PlayerState(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      life: life ?? this.life,
      poison: poison ?? this.poison,
      energy: energy ?? this.energy,
      experience: experience ?? this.experience,
      commanderDamage: commanderDamage ?? this.commanderDamage,
      counters: counters ?? this.counters,
      commanderName: identical(commanderName, _unset)
          ? this.commanderName
          : commanderName as String?,
      artUrl: identical(artUrl, _unset) ? this.artUrl : artUrl as String?,
    );
  }
}

@immutable
class GameState {
  const GameState({required this.players, required this.startingLife});

  final List<PlayerState> players;
  final int startingLife;

  int get playerCount => players.length;

  PlayerState player(int id) => players.firstWhere((p) => p.id == id);

  GameState replacePlayer(PlayerState updated) {
    return GameState(
      players: [for (final p in players) p.id == updated.id ? updated : p],
      startingLife: startingLife,
    );
  }
}
