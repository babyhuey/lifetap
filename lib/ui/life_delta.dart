import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long after the last life change to a player its floating "+N / −N"
/// indicator keeps accumulating before it resets. Consecutive changes within
/// this window sum into one growing number; then the entry clears and the label
/// fades out.
const Duration lifeDeltaWindow = Duration(milliseconds: 1800);

/// Transient, per-player accumulated life change, keyed by player id. Drives the
/// floating delta indicator near each life number. It lives in the ui/ layer
/// because it owns wall-clock reset timers — deliberately kept out of the pure
/// game/ session so it never touches event history or undo. A missing or zero
/// entry means there is nothing to show.
class LifeDeltaNotifier extends Notifier<Map<int, int>> {
  final Map<int, Timer> _timers = {};

  @override
  Map<int, int> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    });
    return const {};
  }

  /// Adds [delta] to [playerId]'s running total and (re)arms its reset timer, so
  /// changes landing within [lifeDeltaWindow] of each other keep summing.
  void bump(int playerId, int delta) {
    state = {...state, playerId: (state[playerId] ?? 0) + delta};
    _timers[playerId]?.cancel();
    _timers[playerId] = Timer(lifeDeltaWindow, () => _reset(playerId));
  }

  void _reset(int playerId) {
    _timers.remove(playerId)?.cancel();
    if (!state.containsKey(playerId)) return;
    state = {...state}..remove(playerId);
  }
}

final lifeDeltaProvider = NotifierProvider<LifeDeltaNotifier, Map<int, int>>(
  LifeDeltaNotifier.new,
);
