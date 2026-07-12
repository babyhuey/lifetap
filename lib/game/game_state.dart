import 'package:flutter/foundation.dart';

enum CounterMode { life, poison, energy, experience }

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
