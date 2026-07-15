# Auto-Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist the current game's event history so the app resumes exactly where it left off after being killed and relaunched.

**Architecture:** `GameEvent` subclasses gain a pure `toJson()`/`eventFromJson()` round-trip (no I/O, `game/` layer). A new `lib/data/game_persistence.dart` (mirroring `lib/data/commander_art.dart`'s interface + provider shape) does the `SharedPreferences` I/O. `GameScreen` (the `ui/` integration point, matching how it already bridges `commanderArtSourceProvider` into `game/`) loads on `initState` and saves via `ref.listen` on every state change.

**Tech Stack:** Flutter 3.44.0, Riverpod, `shared_preferences` (already a dependency), `dart:convert` (already used in `lib/data/commander_art.dart`).

## Global Constraints

- Flutter 3.44.0 pinned; runs only in Docker (`ghcr.io/cirruslabs/flutter:3.44.0`), never on the host.
- `dart format` and `flutter analyze` must be clean, and the relevant `flutter test` file must pass, before each task's commit.
- No Claude attribution or session links in any commit message.
- Commits use plain, factual messages matching this repo's existing style.
- `GameNotifier` (`lib/game/game_notifier.dart`) must not import anything from `lib/data/` — persistence is wired entirely from `lib/ui/game_screen.dart`, matching the existing `commanderArtSourceProvider` pattern (`game/` and `data/` are siblings; `ui/` is the only layer that depends on both).
- Persistence code (`lib/data/game_persistence.dart`) must never throw — `save` no-ops and `load` returns `null` on any failure, matching `ScryfallArtSource`'s established "never throws" contract in the same directory.

---

### Task 1: `GameEvent` JSON round-trip

**Files:**
- Modify: `lib/game/game_events.dart` (add `Map<String, dynamic> toJson()` to the abstract `GameEvent` base and every subclass; add top-level `eventFromJson`)
- Test: Create `test/game/game_events_json_test.dart`

**Interfaces:**
- Produces: `Map<String, dynamic> GameEvent.toJson()` (abstract on the base class, implemented per subclass). `GameEvent eventFromJson(Map<String, dynamic> json)` — top-level factory, throws `FormatException` on an unrecognized `'type'` tag (the caller in Task 2 catches this).

- [ ] **Step 1: Write the failing test**

Create `test/game/game_events_json_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test test/game/game_events_json_test.dart'
```
Expected: FAIL — `toJson`/`eventFromJson` are undefined.

- [ ] **Step 3: Add `toJson()` to the abstract base and every subclass**

In `lib/game/game_events.dart`, in the abstract `GameEvent` class, add the new abstract method after `describe`:
```dart
sealed class GameEvent {
  const GameEvent();

  /// Returns a new state with this event applied to [state].
  GameState apply(GameState state);

  /// A human-readable, past-tense-ish line describing this event, evaluated
  /// against the state as it was *before* the event ran.
  String describe(GameState before);

  /// A JSON-safe map representation, round-tripped by [eventFromJson]. Used
  /// to persist the event history across app restarts.
  Map<String, dynamic> toJson();
}
```

Add a `toJson()` override to each subclass, immediately after that subclass's `describe()` method. `NewGame`:
```dart
  @override
  Map<String, dynamic> toJson() => {
    'type': 'NewGame',
    'playerCount': playerCount,
    'startingLife': startingLife,
  };
```

`AdjustCounter`:
```dart
  @override
  Map<String, dynamic> toJson() => {
    'type': 'AdjustCounter',
    'playerId': playerId,
    'mode': mode.name,
    'delta': delta,
  };
```

`AdjustNamedCounter`:
```dart
  @override
  Map<String, dynamic> toJson() => {
    'type': 'AdjustNamedCounter',
    'playerId': playerId,
    'name': name,
    'delta': delta,
  };
```

`AdjustCommanderDamage`:
```dart
  @override
  Map<String, dynamic> toJson() => {
    'type': 'AdjustCommanderDamage',
    'playerId': playerId,
    'fromPlayerId': fromPlayerId,
    'delta': delta,
    'reduceLife': reduceLife,
  };
```

`RenamePlayer`:
```dart
  @override
  Map<String, dynamic> toJson() => {
    'type': 'RenamePlayer',
    'playerId': playerId,
    'name': name,
  };
```

`SetCommander`:
```dart
  @override
  Map<String, dynamic> toJson() => {
    'type': 'SetCommander',
    'playerId': playerId,
    'commanderName': commanderName,
    'artUrl': artUrl,
  };
```

`RecolorPlayer`:
```dart
  @override
  Map<String, dynamic> toJson() => {
    'type': 'RecolorPlayer',
    'playerId': playerId,
    'color': color,
  };
```

`SetMonarch`:
```dart
  @override
  Map<String, dynamic> toJson() => {'type': 'SetMonarch', 'playerId': playerId};
```

`SetInitiative`:
```dart
  @override
  Map<String, dynamic> toJson() => {
    'type': 'SetInitiative',
    'playerId': playerId,
  };
```

`CycleDayNight`:
```dart
  @override
  Map<String, dynamic> toJson() => const {'type': 'CycleDayNight'};
```

- [ ] **Step 4: Add the top-level `eventFromJson` factory**

At the end of `lib/game/game_events.dart` (after the last existing top-level declaration, `_nextDayNight`), add:
```dart

/// Reconstructs a [GameEvent] from the map produced by [GameEvent.toJson].
/// Throws [FormatException] on an unrecognized `'type'` tag — the caller
/// (the persistence layer) treats any such failure as "nothing to restore".
GameEvent eventFromJson(Map<String, dynamic> json) {
  final type = json['type'] as String;
  return switch (type) {
    'NewGame' => NewGame(
      playerCount: json['playerCount'] as int,
      startingLife: json['startingLife'] as int,
    ),
    'AdjustCounter' => AdjustCounter(
      playerId: json['playerId'] as int,
      mode: CounterMode.values.byName(json['mode'] as String),
      delta: json['delta'] as int,
    ),
    'AdjustNamedCounter' => AdjustNamedCounter(
      playerId: json['playerId'] as int,
      name: json['name'] as String,
      delta: json['delta'] as int,
    ),
    'AdjustCommanderDamage' => AdjustCommanderDamage(
      playerId: json['playerId'] as int,
      fromPlayerId: json['fromPlayerId'] as int,
      delta: json['delta'] as int,
      reduceLife: json['reduceLife'] as bool,
    ),
    'RenamePlayer' => RenamePlayer(
      playerId: json['playerId'] as int,
      name: json['name'] as String,
    ),
    'SetCommander' => SetCommander(
      playerId: json['playerId'] as int,
      commanderName: json['commanderName'] as String?,
      artUrl: json['artUrl'] as String?,
    ),
    'RecolorPlayer' => RecolorPlayer(
      playerId: json['playerId'] as int,
      color: json['color'] as int,
    ),
    'SetMonarch' => SetMonarch(playerId: json['playerId'] as int?),
    'SetInitiative' => SetInitiative(playerId: json['playerId'] as int?),
    'CycleDayNight' => const CycleDayNight(),
    _ => throw FormatException('Unknown GameEvent type: $type'),
  };
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; dart format --set-exit-if-changed lib/game/game_events.dart test/game/game_events_json_test.dart && flutter analyze --no-fatal-infos && flutter test test/game/game_events_json_test.dart'
```
Expected: format 0 changed, analyze no issues, all 13 tests pass.

- [ ] **Step 6: Run the full test suite to check for regressions**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test'
```
Expected: all tests pass (104 pre-existing + 13 new = 117).

- [ ] **Step 7: Commit**

```bash
git add lib/game/game_events.dart test/game/game_events_json_test.dart
git commit -m "Add JSON round-trip to GameEvent for session persistence"
```

---

### Task 2: Persistence layer

**Files:**
- Create: `lib/data/game_persistence.dart`
- Test: Create `test/data/game_persistence_test.dart`

**Interfaces:**
- Consumes: `GameEvent`, `GameEvent.toJson()`, `eventFromJson()` from Task 1 (`lib/game/game_events.dart`, already imported by nothing in `lib/data/` today — this task adds the first such import).
- Produces: `abstract class GamePersistence { Future<void> save(List<GameEvent> history); Future<List<GameEvent>?> load(); }`, `class SharedPreferencesGamePersistence implements GamePersistence`, `final gamePersistenceProvider = Provider<GamePersistence>((ref) => SharedPreferencesGamePersistence());`

- [ ] **Step 1: Write the failing tests**

Create `test/data/game_persistence_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/data/game_persistence.dart';
import 'package:lifetap/game/game_events.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SharedPreferencesGamePersistence', () {
    test('load returns null when nothing has been saved', () async {
      final persistence = SharedPreferencesGamePersistence();
      expect(await persistence.load(), isNull);
    });

    test('save then load round-trips a multi-event history', () async {
      final persistence = SharedPreferencesGamePersistence();
      final history = <GameEvent>[
        const NewGame(playerCount: 3, startingLife: 30),
        const AdjustCounter(playerId: 0, mode: CounterMode.life, delta: -5),
        const RenamePlayer(playerId: 1, name: 'Bob'),
      ];

      await persistence.save(history);
      final loaded = await persistence.load();

      expect(loaded, isNotNull);
      expect(loaded!.length, 3);
      expect(loaded[0], isA<NewGame>());
      expect((loaded[0] as NewGame).playerCount, 3);
      expect(loaded[1], isA<AdjustCounter>());
      expect((loaded[1] as AdjustCounter).delta, -5);
      expect(loaded[2], isA<RenamePlayer>());
      expect((loaded[2] as RenamePlayer).name, 'Bob');
    });

    test('a later save overwrites an earlier one', () async {
      final persistence = SharedPreferencesGamePersistence();
      await persistence.save(const [NewGame(playerCount: 2, startingLife: 20)]);
      await persistence.save(const [NewGame(playerCount: 4, startingLife: 40)]);

      final loaded = await persistence.load();
      expect((loaded!.single as NewGame).playerCount, 4);
    });

    test('load returns null (never throws) on malformed stored JSON', () async {
      SharedPreferences.setMockInitialValues({
        'lifetap:saved-session': 'not valid json {{{',
      });
      final persistence = SharedPreferencesGamePersistence();

      expect(await persistence.load(), isNull);
    });

    test(
      'load returns null (never throws) on a recognizable-JSON but unknown '
      'event type',
      () async {
        SharedPreferences.setMockInitialValues({
          'lifetap:saved-session': '[{"type":"NotARealEvent"}]',
        });
        final persistence = SharedPreferencesGamePersistence();

        expect(await persistence.load(), isNull);
      },
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test test/data/game_persistence_test.dart'
```
Expected: FAIL — `lib/data/game_persistence.dart` doesn't exist.

- [ ] **Step 3: Create the persistence layer**

Create `lib/data/game_persistence.dart`:
```dart
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; dart format --set-exit-if-changed lib/data/game_persistence.dart test/data/game_persistence_test.dart && flutter analyze --no-fatal-infos && flutter test test/data/game_persistence_test.dart'
```
Expected: format 0 changed, analyze no issues, all 5 tests pass.

- [ ] **Step 5: Run the full test suite to check for regressions**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test'
```
Expected: all tests pass (117 pre-existing + 5 new = 122).

- [ ] **Step 6: Commit**

```bash
git add lib/data/game_persistence.dart test/data/game_persistence_test.dart
git commit -m "Add SharedPreferences-backed game session persistence"
```

---

### Task 3: Wire restore-on-launch and save-on-change into GameScreen

**Files:**
- Modify: `lib/game/game_notifier.dart` (add `restoreFrom`)
- Modify: `lib/ui/game_screen.dart` (`initState`)
- Test: Modify `test/game/game_notifier_test.dart`; Create `test/ui/game_persistence_ui_test.dart`

**Interfaces:**
- Consumes: `gamePersistenceProvider`, `GamePersistence` from Task 2. `GameEvent` from Task 1.
- Produces: `void GameNotifier.restoreFrom(List<GameEvent> history)`.

- [ ] **Step 1: Write the failing tests**

In `test/game/game_notifier_test.dart`, add this test immediately after the existing `'dispatch appends history and updates current'` test (inside the same `main()`, no new imports needed — `GameEvent`/`AdjustCounter`/`RenamePlayer` are already imported in this file):
```dart
  test('restoreFrom folds the given history into current and stores it '
      'as-is', () {
    final history = <GameEvent>[
      const NewGame(playerCount: 3, startingLife: 30),
      const AdjustCounter(playerId: 0, mode: CounterMode.life, delta: -7),
      const RenamePlayer(playerId: 1, name: 'Restored'),
    ];

    notifier().restoreFrom(history);

    expect(session().history, history);
    expect(session().current.playerCount, 3);
    expect(session().current.player(0).life, 23);
    expect(session().current.player(1).name, 'Restored');
  });
```

Create `test/ui/game_persistence_ui_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/data/game_persistence.dart';
import 'package:lifetap/game/game_events.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/ui/game_screen.dart';

/// An in-memory [GamePersistence] two independent [ProviderContainer]s can
/// share, standing in for the real SharedPreferences-backed store surviving
/// an app restart.
class _InMemoryPersistence implements GamePersistence {
  List<GameEvent>? stored;

  @override
  Future<void> save(List<GameEvent> history) async {
    stored = List.of(history);
  }

  @override
  Future<List<GameEvent>?> load() async => stored;
}

void main() {
  testWidgets(
    'a new GameScreen instance resumes the prior session instead of the '
    'default fresh game',
    (tester) async {
      final shared = _InMemoryPersistence();

      // First "app session": play a few moves.
      final firstContainer = ProviderContainer(
        overrides: [gamePersistenceProvider.overrideWithValue(shared)],
      );
      addTearDown(firstContainer.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: firstContainer,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();

      final id = firstContainer.read(gameProvider).current.players.first.id;
      firstContainer
          .read(gameProvider.notifier)
          .dispatch(
            AdjustCounter(playerId: id, mode: CounterMode.life, delta: -9),
          );
      // Let the ref.listen save side effect run.
      await tester.pump();

      // "Kill and relaunch": a fresh container/widget tree, same persistence.
      final secondContainer = ProviderContainer(
        overrides: [gamePersistenceProvider.overrideWithValue(shared)],
      );
      addTearDown(secondContainer.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: secondContainer,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump(); // default seed
      await tester.pump(); // async restore resolves

      expect(secondContainer.read(gameProvider).current.player(id).life, 31);
    },
  );

  testWidgets('with nothing saved, a GameScreen boots the default fresh '
      'game', (tester) async {
    final shared = _InMemoryPersistence();
    final container = ProviderContainer(
      overrides: [gamePersistenceProvider.overrideWithValue(shared)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(container.read(gameProvider).current.playerCount, 4);
    expect(container.read(gameProvider).current.players.first.life, 40);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test test/game/game_notifier_test.dart test/ui/game_persistence_ui_test.dart'
```
Expected: FAIL — `restoreFrom` is undefined, and the UI test's restored-life assertion fails (life is 40, not 31) since nothing restores yet.

- [ ] **Step 3: Add `restoreFrom` to `GameNotifier`**

In `lib/game/game_notifier.dart`, add this method immediately after `newGame` (before `dispatch`):
```dart
  /// Replaces all state with [history], folded exactly like any other
  /// history — used to resume a session persisted before the app was last
  /// closed. Pure state-setting; the caller (the UI layer) is responsible
  /// for loading [history] from persistence.
  void restoreFrom(List<GameEvent> history) {
    state = GameSession(current: _fold(history), history: history);
  }
```

- [ ] **Step 4: Wire load-on-launch and save-on-change into `GameScreen`**

In `lib/ui/game_screen.dart`, add the import (alongside the existing `import '../data/commander_art.dart';`):
```dart
import '../data/game_persistence.dart';
```

Change `initState()` from:
```dart
  @override
  void initState() {
    super.initState();
    _router = PointerRouter(onResult: _onResult, clock: widget.clock);
    // Drives hold auto-repeat: while a finger is held stationary in a zone the
    // router emits accelerating repeats on each tick. A no-op when nothing is
    // held, so the fixed interval costs almost nothing at rest.
    _holdTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      _router.tick();
      _ritualTick();
    });
    _enableWakelock();
  }
```
to:
```dart
  @override
  void initState() {
    super.initState();
    _router = PointerRouter(onResult: _onResult, clock: widget.clock);
    // Drives hold auto-repeat: while a finger is held stationary in a zone the
    // router emits accelerating repeats on each tick. A no-op when nothing is
    // held, so the fixed interval costs almost nothing at rest.
    _holdTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      _router.tick();
      _ritualTick();
    });
    _enableWakelock();
    _restoreIfAvailable();
    // Persists every subsequent state change (including a fresh NewGame from
    // Settings, which naturally overwrites whatever was saved before). Does
    // not fire for the state current at registration, so the very first
    // default-seeded game before any move is only persisted once the player
    // acts — if the app is killed before that, relaunching just reseeds the
    // same default game, which is unobservable.
    ref.listen(gameProvider, (previous, next) {
      ref.read(gamePersistenceProvider).save(next.history);
    });
  }

  Future<void> _restoreIfAvailable() async {
    final history = await ref.read(gamePersistenceProvider).load();
    if (history == null || !mounted) return;
    ref.read(gameProvider.notifier).restoreFrom(history);
  }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; dart format --set-exit-if-changed lib/game/game_notifier.dart lib/ui/game_screen.dart test/game/game_notifier_test.dart test/ui/game_persistence_ui_test.dart && flutter analyze --no-fatal-infos && flutter test test/game/game_notifier_test.dart test/ui/game_persistence_ui_test.dart'
```
Expected: format 0 changed, analyze no issues, all tests pass.

- [ ] **Step 6: Run the full test suite to check for regressions**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test'
```
Expected: all tests pass (122 pre-existing + 1 notifier test + 2 UI tests = 125).

- [ ] **Step 7: Commit**

```bash
git add lib/game/game_notifier.dart lib/ui/game_screen.dart test/game/game_notifier_test.dart test/ui/game_persistence_ui_test.dart
git commit -m "Auto-restore the in-progress game on launch"
```

---

### Task 4: Full verification sequence

**Files:** none (verification only).

**Interfaces:** none.

- [ ] **Step 1: Run the complete DEV_NOTES verification sequence**

```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; dart format --set-exit-if-changed lib test tool integration_test && flutter analyze --no-fatal-infos && flutter test'
```
Expected: format 0 changed, analyze no issues, all 125 tests pass.

The headless Linux integration test (`xvfb-run -a flutter test integration_test -d linux`) has proven unreliable in this sandbox in prior sessions (hangs after toolchain install, unrelated to code correctness) — the format/analyze/full-suite run above plus GitHub Actions CI on push are the reliable checks; don't burn time re-attempting the local integration run unless specifically investigating something the unit/widget suite can't cover.

- [ ] **Step 2: If anything fails, fix and re-run from Step 1**

Do not proceed until every check in Step 1 passes clean.
