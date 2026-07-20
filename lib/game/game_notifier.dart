import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'game_events.dart';
import 'game_state.dart';

/// The full game session: the current projected [GameState] plus the ordered
/// event [history] it was folded from. Undo and the history view are both
/// projections of [history].
class GameSession {
  const GameSession({required this.current, required this.history});

  final GameState current;
  final List<GameEvent> history;
}

class GameNotifier extends Notifier<GameSession> {
  /// The state every history fold starts from; only a [NewGame] event is
  /// expected to seed real players on top of it.
  static const GameState _empty = GameState(players: [], startingLife: 20);

  @override
  GameSession build() {
    final event = NewGame(
      playerCount: 4,
      startingLife: 40,
      seed: Random().nextInt(1 << 31),
    );
    return GameSession(current: event.apply(_empty), history: [event]);
  }

  /// Starts a fresh game, replacing all history with a single [NewGame]. Its
  /// seed is randomized here (rather than inside [NewGame.apply]) so the
  /// event itself stays a pure function of its fields and replaying history
  /// deterministically reproduces the same state.
  void newGame(int count, int startingLife) {
    final event = NewGame(
      playerCount: count,
      startingLife: startingLife,
      seed: Random().nextInt(1 << 31),
    );
    state = GameSession(current: event.apply(_empty), history: [event]);
  }

  /// Replaces all state with [history], folded exactly like any other
  /// history — used to resume a session persisted before the app was last
  /// closed. Pure state-setting; the caller (the UI layer) is responsible
  /// for loading [history] from persistence.
  void restoreFrom(List<GameEvent> history) {
    state = GameSession(current: _fold(history), history: history);
  }

  /// Appends [event] and applies it to the current state. [event.apply] is a
  /// pure function of prior state, so applying just the new event is
  /// equivalent to re-folding the whole history but O(1) instead of O(n).
  void dispatch(GameEvent event) {
    state = GameSession(
      current: event.apply(state.current),
      history: [...state.history, event],
    );
  }

  /// Toggles the Monarch on [playerId]: clears it if they already hold it,
  /// otherwise moves it to them (single-holder).
  void toggleMonarch(int playerId) {
    final held = state.current.monarchId == playerId;
    dispatch(SetMonarch(playerId: held ? null : playerId));
  }

  /// Toggles the Initiative on [playerId], with the same single-holder
  /// semantics as [toggleMonarch] but an independent field.
  void toggleInitiative(int playerId) {
    final held = state.current.initiativeId == playerId;
    dispatch(SetInitiative(playerId: held ? null : playerId));
  }

  /// Advances the table-wide day/night state one step.
  void cycleDayNight() => dispatch(const CycleDayNight());

  /// Drops the most recent event and re-folds from scratch. Re-folding is what
  /// makes undo correct for events whose effect depends on prior state
  /// (clamped counters, commander-damage-with-life).
  void undo() {
    if (state.history.length <= 1) return;
    final history = state.history.sublist(0, state.history.length - 1);
    state = GameSession(current: _fold(history), history: history);
  }

  /// One description line per event, each evaluated against the state that
  /// existed immediately before it.
  List<String> historyLines() {
    final lines = <String>[];
    var s = _empty;
    for (final event in state.history) {
      lines.add(event.describe(s));
      s = event.apply(s);
    }
    return lines;
  }

  GameState _fold(List<GameEvent> history) {
    var s = _empty;
    for (final event in history) {
      s = event.apply(s);
    }
    return s;
  }
}

final gameProvider = NotifierProvider<GameNotifier, GameSession>(
  GameNotifier.new,
);
