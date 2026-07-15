import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/game_events.dart';

/// Persists and restores the current game's event history so the app can
/// resume an in-progress game after being killed and relaunched.
abstract class GamePersistence {
  Future<void> save(List<GameEvent> history);
  Future<List<GameEvent>?> load();
}

/// Stores the history as JSON in [SharedPreferences]. Never throws — a
/// failed save is a silent no-op (the next restore attempt just falls back
/// to a fresh game, the same as if nothing had ever been saved), and a
/// failed load returns null for the same reason. A launch-time crash from a
/// corrupted save would be far worse than silently discarding it.
class SharedPreferencesGamePersistence implements GamePersistence {
  static const _key = 'lifetap:saved-session';

  @override
  Future<void> save(List<GameEvent> history) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(history.map((e) => e.toJson()).toList());
      await prefs.setString(_key, encoded);
    } catch (_) {
      // Best-effort; see class doc.
    }
  }

  @override
  Future<List<GameEvent>?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as List;
      final events = decoded
          .map((e) => eventFromJson(e as Map<String, dynamic>))
          .toList();
      return events.isEmpty ? null : events;
    } catch (_) {
      return null;
    }
  }
}

/// Overridable in tests with a fake so no test touches real
/// SharedPreferences I/O beyond what it explicitly sets up.
final gamePersistenceProvider = Provider<GamePersistence>(
  (ref) => SharedPreferencesGamePersistence(),
);
