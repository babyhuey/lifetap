# Optional Turn Timer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An opt-in per-turn countdown: a toolbar "End Turn" button cycles whose turn it is through the seating order, with a seat-rotated countdown badge on the active player's zone.

**Architecture:** `GameSettings` gains `turnTimerEnabled`/`turnTimerSeconds`. `_GameScreenState` tracks `_activeTurnPlayerId`/`_turnDeadline` as ephemeral UI state (not part of `GameState`/`GameEvent`), driven by the existing 60ms tick and a dedicated `ref.listenManual` that resets on a fresh `NewGame`.

**Tech Stack:** Flutter 3.44.0, Riverpod.

## Global Constraints

- Flutter 3.44.0 pinned; runs only in Docker (`ghcr.io/cirruslabs/flutter:3.44.0`), never on the host.
- `dart format` and `flutter analyze` must be clean, and the relevant `flutter test` file must pass, before each task's commit.
- No Claude attribution or session links in any commit message.
- Commits use plain, factual messages matching this repo's existing style.
- Turn state must not touch `GameState`/`GameEvent`/persistence — it is ephemeral UI state local to `_GameScreenState`, following the same reasoning as the ritual-picker feature.
- Hitting zero must never force anything (no auto-advance, no blocked input) — visual cue only.

---

### Task 1: `GameSettings` toggle and duration for the turn timer

**Files:**
- Modify: `lib/ui/settings_screen.dart`
- Test: Create `test/ui/turn_timer_settings_test.dart`

**Interfaces:**
- Produces: `GameSettings.turnTimerEnabled` (bool, default `false`), `GameSettings.turnTimerSeconds` (int, default `60`), `SettingsNotifier.setTurnTimerEnabled(bool)`, `SettingsNotifier.setTurnTimerSeconds(int)`. `const List<int> turnTimerSecondsOptions = [30, 60, 90, 120];` (top-level, alongside the existing `playerCountOptions`/`startingLifeOptions`).

- [ ] **Step 1: Write the failing test**

Create `test/ui/turn_timer_settings_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/ui/settings_screen.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  test('turnTimerEnabled defaults off, turnTimerSeconds defaults to 60', () {
    final settings = container.read(settingsProvider);
    expect(settings.turnTimerEnabled, isFalse);
    expect(settings.turnTimerSeconds, 60);
  });

  test('setTurnTimerEnabled and setTurnTimerSeconds update independently', () {
    container.read(settingsProvider.notifier).setTurnTimerEnabled(true);
    expect(container.read(settingsProvider).turnTimerEnabled, isTrue);
    expect(container.read(settingsProvider).turnTimerSeconds, 60);

    container.read(settingsProvider.notifier).setTurnTimerSeconds(90);
    expect(container.read(settingsProvider).turnTimerSeconds, 90);
    expect(container.read(settingsProvider).turnTimerEnabled, isTrue);
  });

  test('turnTimerSecondsOptions offers the four presets', () {
    expect(turnTimerSecondsOptions, [30, 60, 90, 120]);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test test/ui/turn_timer_settings_test.dart'
```
Expected: FAIL — none of the new symbols exist.

- [ ] **Step 3: Add the fields, options list, and setters**

In `lib/ui/settings_screen.dart`, change:
```dart
const List<int> playerCountOptions = [2, 3, 4, 5, 6];
const List<int> startingLifeOptions = [20, 25, 30, 40, 60];
```
to:
```dart
const List<int> playerCountOptions = [2, 3, 4, 5, 6];
const List<int> startingLifeOptions = [20, 25, 30, 40, 60];
const List<int> turnTimerSecondsOptions = [30, 60, 90, 120];
```

Change:
```dart
@immutable
class GameSettings {
  const GameSettings({
    this.commanderDamageLifeLoss = true,
    this.autoKo = true,
    this.inAppKeyboard = true,
    this.hapticFeedback = true,
    this.soundEffects = false,
  });

  /// When true, commander damage also subtracts life (the default rule).
  final bool commanderDamageLifeLoss;

  /// When true, a player who has hit a lethal threshold is shown knocked out.
  final bool autoKo;

  /// When true, the rename editor uses a small seat-rotated on-screen keyboard
  /// instead of the OS keyboard (which the OS can't rotate to face a side seat).
  final bool inAppKeyboard;

  /// When true, a life-adjust or commander-damage tap gives light haptic
  /// feedback (stronger for a knocked-out player).
  final bool hapticFeedback;

  /// When true, the same taps also play a short system click/alert sound.
  final bool soundEffects;

  GameSettings copyWith({
    bool? commanderDamageLifeLoss,
    bool? autoKo,
    bool? inAppKeyboard,
    bool? hapticFeedback,
    bool? soundEffects,
  }) => GameSettings(
    commanderDamageLifeLoss:
        commanderDamageLifeLoss ?? this.commanderDamageLifeLoss,
    autoKo: autoKo ?? this.autoKo,
    inAppKeyboard: inAppKeyboard ?? this.inAppKeyboard,
    hapticFeedback: hapticFeedback ?? this.hapticFeedback,
    soundEffects: soundEffects ?? this.soundEffects,
  );
}
```
to:
```dart
@immutable
class GameSettings {
  const GameSettings({
    this.commanderDamageLifeLoss = true,
    this.autoKo = true,
    this.inAppKeyboard = true,
    this.hapticFeedback = true,
    this.soundEffects = false,
    this.turnTimerEnabled = false,
    this.turnTimerSeconds = 60,
  });

  /// When true, commander damage also subtracts life (the default rule).
  final bool commanderDamageLifeLoss;

  /// When true, a player who has hit a lethal threshold is shown knocked out.
  final bool autoKo;

  /// When true, the rename editor uses a small seat-rotated on-screen keyboard
  /// instead of the OS keyboard (which the OS can't rotate to face a side seat).
  final bool inAppKeyboard;

  /// When true, a life-adjust or commander-damage tap gives light haptic
  /// feedback (stronger for a knocked-out player).
  final bool hapticFeedback;

  /// When true, the same taps also play a short system click/alert sound.
  final bool soundEffects;

  /// When true, the toolbar's End Turn button and a per-turn countdown badge
  /// are active. A soft reminder only — it never forces anything.
  final bool turnTimerEnabled;

  /// Seconds per turn once [turnTimerEnabled] is on.
  final int turnTimerSeconds;

  GameSettings copyWith({
    bool? commanderDamageLifeLoss,
    bool? autoKo,
    bool? inAppKeyboard,
    bool? hapticFeedback,
    bool? soundEffects,
    bool? turnTimerEnabled,
    int? turnTimerSeconds,
  }) => GameSettings(
    commanderDamageLifeLoss:
        commanderDamageLifeLoss ?? this.commanderDamageLifeLoss,
    autoKo: autoKo ?? this.autoKo,
    inAppKeyboard: inAppKeyboard ?? this.inAppKeyboard,
    hapticFeedback: hapticFeedback ?? this.hapticFeedback,
    soundEffects: soundEffects ?? this.soundEffects,
    turnTimerEnabled: turnTimerEnabled ?? this.turnTimerEnabled,
    turnTimerSeconds: turnTimerSeconds ?? this.turnTimerSeconds,
  );
}
```

Change:
```dart
  void setHapticFeedback(bool value) =>
      state = state.copyWith(hapticFeedback: value);

  void setSoundEffects(bool value) =>
      state = state.copyWith(soundEffects: value);
}
```
to:
```dart
  void setHapticFeedback(bool value) =>
      state = state.copyWith(hapticFeedback: value);

  void setSoundEffects(bool value) =>
      state = state.copyWith(soundEffects: value);

  void setTurnTimerEnabled(bool value) =>
      state = state.copyWith(turnTimerEnabled: value);

  void setTurnTimerSeconds(int value) =>
      state = state.copyWith(turnTimerSeconds: value);
}
```

- [ ] **Step 4: Add the toggle and duration chip row to the Gameplay section**

In `lib/ui/settings_screen.dart`'s `build()`, change:
```dart
            _ToggleRow(
              label: 'Sound effects',
              value: settings.soundEffects,
              onChanged: ref.read(settingsProvider.notifier).setSoundEffects,
            ),
            const SizedBox(height: 32),
            const _SectionHeader('Offline'),
```
to:
```dart
            _ToggleRow(
              label: 'Sound effects',
              value: settings.soundEffects,
              onChanged: ref.read(settingsProvider.notifier).setSoundEffects,
            ),
            _ToggleRow(
              label: 'Turn timer',
              value: settings.turnTimerEnabled,
              onChanged: ref
                  .read(settingsProvider.notifier)
                  .setTurnTimerEnabled,
            ),
            const SizedBox(height: 12),
            const _RowLabel('Turn timer length'),
            const SizedBox(height: 10),
            _ChipRow(
              options: turnTimerSecondsOptions,
              selected: settings.turnTimerSeconds,
              onSelected: ref.read(settingsProvider.notifier).setTurnTimerSeconds,
            ),
            const SizedBox(height: 32),
            const _SectionHeader('Offline'),
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; dart format --set-exit-if-changed lib/ui/settings_screen.dart test/ui/turn_timer_settings_test.dart && flutter analyze --no-fatal-infos && flutter test test/ui/turn_timer_settings_test.dart'
```
Expected: format 0 changed, analyze no issues, all 3 tests pass.

- [ ] **Step 6: Run the full test suite to check for regressions**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test'
```
Expected: all tests pass (133 pre-existing + 3 new = 136).

- [ ] **Step 7: Commit**

```bash
git add lib/ui/settings_screen.dart test/ui/turn_timer_settings_test.dart
git commit -m "Add turn timer settings toggle and duration presets"
```

---

### Task 2: Turn tracking, End Turn button, and the countdown badge

**Files:**
- Modify: `lib/ui/game_screen.dart`
- Test: Create `test/ui/turn_timer_test.dart`

**Interfaces:**
- Consumes: `GameSettings.turnTimerEnabled`/`.turnTimerSeconds` from Task 1.
- Produces: `_GameScreenState._activeTurnPlayerId` (int?), `_endTurn()`, `_turnTimerTick()`, `_turnSecondsRemaining()`. `_TurnTimerBadge` (new private widget). `_Toolbar.onEndTurn` (new required `VoidCallback?` param).

- [ ] **Step 1: Write the failing test**

Create `test/ui/turn_timer_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/ui/game_screen.dart';
import 'package:lifetap/ui/settings_screen.dart';

void main() {
  testWidgets(
    'enabling the timer shows a full-duration badge on player 0; End Turn '
    'moves it to player 1 with a reset countdown',
    (tester) async {
      var now = Duration.zero;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(settingsProvider.notifier).setTurnTimerEnabled(true);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GameScreen(clock: () => now)),
        ),
      );
      await tester.pump();
      now = const Duration(milliseconds: 60);
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('60'), findsOneWidget);

      final players = container.read(gameProvider).current.players;
      // Tap without advancing `now` again: _endTurn() recomputes the
      // deadline from the *current* clock value, so checking immediately
      // (no further clock advancement) keeps the expected remaining time at
      // exactly the full duration — advancing `now` again here before the
      // check would make the assertion depend on exact elapsed-ms/1000
      // truncation instead of testing the actual reset behavior.
      await tester.tap(find.byKey(const ValueKey('end-turn-icon')));
      await tester.pump();

      expect(find.text('60'), findsOneWidget);
      // The badge is on player[1]'s zone, not player[0]'s.
      final badgeFinder = find.text('60');
      final badgeZoneRect = tester.getRect(badgeFinder);
      expect(badgeZoneRect.center.dx, greaterThan(400));
    },
  );

  testWidgets(
    'the countdown badge is absent when the setting is off, and '
    'disappears if the setting is turned off mid-game',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('turn-timer-badge')), findsNothing);

      container.read(settingsProvider.notifier).setTurnTimerEnabled(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const ValueKey('turn-timer-badge')), findsOneWidget);

      container.read(settingsProvider.notifier).setTurnTimerEnabled(false);
      await tester.pump();
      expect(find.byKey(const ValueKey('turn-timer-badge')), findsNothing);
    },
  );

  testWidgets(
    'a fresh new game resets turn tracking to player 0',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(settingsProvider.notifier).setTurnTimerEnabled(true);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      await tester.tap(find.byKey(const ValueKey('end-turn-icon')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      container.read(gameProvider.notifier).newGame(4, 40);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final badgeZoneRect = tester.getRect(find.byKey(const ValueKey('turn-timer-badge')));
      expect(badgeZoneRect.center.dx, lessThan(400));
    },
  );

  testWidgets(
    'the badge switches to the warning color once the deadline passes, '
    'without blocking normal life taps',
    (tester) async {
      var now = Duration.zero;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(settingsProvider.notifier).setTurnTimerEnabled(true);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GameScreen(clock: () => now)),
        ),
      );
      await tester.pump();
      // First tick: activates tracking with a deadline computed from
      // `now`=60ms (deadline = 60ms + 60s). Advancing `now` to 61s *before*
      // this pump (instead of after) would make the very first tick already
      // see the far-future value and compute the deadline from THAT, so the
      // remaining time would still read a full 60s afterward — `now` is a
      // static variable the injected clock reads, not real elapsed time, so
      // it never advances on its own between pumps.
      now = const Duration(milliseconds: 60);
      await tester.pump(const Duration(milliseconds: 60));

      // Now push `now` well past the deadline and let one more tick observe
      // it and repaint.
      now = const Duration(seconds: 61);
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('0'), findsOneWidget);

      final id = container.read(gameProvider).current.players.first.id;
      final before = container.read(gameProvider).current.player(id).life;
      await tester.tapAt(const Offset(110, 210));
      expect(
        container.read(gameProvider).current.player(id).life,
        isNot(before),
        reason: 'the timer hitting zero must never block a life tap',
      );
    },
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test test/ui/turn_timer_test.dart'
```
Expected: FAIL — `end-turn-icon`/`turn-timer-badge` keys and the countdown text don't exist yet.

- [ ] **Step 3: Add turn-tracking fields, tick logic, listener, and `_endTurn`**

In `lib/ui/game_screen.dart`, add fields to `_GameScreenState` immediately after `bool _gameOverShown = false;`:
```dart
  int? _activeTurnPlayerId;
  Duration? _turnDeadline;
```

In `initState()`, immediately after the game-over `ref.listenManual(...)` block (which ends with `});` right before `initState`'s closing brace), add a third listener:
```dart
    // Resets turn tracking on a fresh NewGame — checked by history length,
    // not by re-deriving from current players, since a new game's player
    // ids can coincidentally overlap with the prior game's (both start at
    // 0), which would make an "is this id still in the roster" check
    // unreliable as a reset signal.
    ref.listenManual(gameProvider, (previous, next) {
      if (next.history.length <= 1) {
        _activeTurnPlayerId = null;
      }
    });
```

Change the `_holdTimer` callback from:
```dart
    _holdTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      _router.tick();
      _ritualTick();
    });
```
to:
```dart
    _holdTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      _router.tick();
      _ritualTick();
      _turnTimerTick();
    });
```

Add these methods to `_GameScreenState`, immediately after `_ritualTick` (right before `_completeRitual`):
```dart
  void _turnTimerTick() {
    final settings = ref.read(settingsProvider);
    if (!settings.turnTimerEnabled) {
      _activeTurnPlayerId = null;
      return;
    }
    final players = ref.read(gameProvider).current.players;
    if (players.isEmpty) return;
    if (_activeTurnPlayerId == null) {
      _activeTurnPlayerId = players.first.id;
      _turnDeadline =
          _router.clock() + Duration(seconds: settings.turnTimerSeconds);
    }
    setState(() {});
  }

  /// Advances to the next player in seating order, wrapping around, and
  /// resets the countdown. A no-op while the setting is off.
  void _endTurn() {
    final settings = ref.read(settingsProvider);
    if (!settings.turnTimerEnabled) return;
    final players = ref.read(gameProvider).current.players;
    if (players.isEmpty) return;
    final currentIndex = players.indexWhere(
      (p) => p.id == _activeTurnPlayerId,
    );
    final nextIndex = currentIndex == -1 ? 0 : (currentIndex + 1) % players.length;
    setState(() {
      _activeTurnPlayerId = players[nextIndex].id;
      _turnDeadline =
          _router.clock() + Duration(seconds: settings.turnTimerSeconds);
    });
  }

  /// Whole seconds left in the active player's turn, clamped at 0 once the
  /// deadline has passed (never negative — the badge shows 0, not a
  /// countdown into negative numbers).
  int _turnSecondsRemaining() {
    final deadline = _turnDeadline;
    if (deadline == null) return 0;
    final remaining = deadline - _router.clock();
    return remaining.isNegative ? 0 : remaining.inSeconds;
  }
```

- [ ] **Step 4: Watch settings in `build()` and wire the toolbar button**

In `lib/ui/game_screen.dart`'s `build()`, change:
```dart
  Widget build(BuildContext context) {
    final session = ref.watch(gameProvider);
    final game = session.current;
    final players = game.players;
```
to:
```dart
  Widget build(BuildContext context) {
    final session = ref.watch(gameProvider);
    final game = session.current;
    final players = game.players;
    final settings = ref.watch(settingsProvider);
```

Change the `_Toolbar(...)` construction from:
```dart
                child: _Toolbar(
                  playerCount: players.length,
                  dayNight: game.dayNight,
                  onDayNight: _ritualActive
                      ? null
                      : () => ref.read(gameProvider.notifier).cycleDayNight(),
                  onSettings: _ritualActive ? null : _openSettings,
                  onUndo: _ritualActive
                      ? null
                      : () => ref.read(gameProvider.notifier).undo(),
                  onDice: _ritualActive ? null : _showDice,
                  onCoin: _ritualActive ? null : _showCoin,
                  onHistory: _ritualActive ? null : _showHistory,
                  onRitual: _toggleRitual,
                ),
```
to:
```dart
                child: _Toolbar(
                  playerCount: players.length,
                  dayNight: game.dayNight,
                  onDayNight: _ritualActive
                      ? null
                      : () => ref.read(gameProvider.notifier).cycleDayNight(),
                  onSettings: _ritualActive ? null : _openSettings,
                  onUndo: _ritualActive
                      ? null
                      : () => ref.read(gameProvider.notifier).undo(),
                  onDice: _ritualActive ? null : _showDice,
                  onCoin: _ritualActive ? null : _showCoin,
                  onHistory: _ritualActive ? null : _showHistory,
                  onRitual: _toggleRitual,
                  onEndTurn: (_ritualActive || !settings.turnTimerEnabled)
                      ? null
                      : _endTurn,
                ),
```

- [ ] **Step 5: Add the badge to the outer Stack**

In `lib/ui/game_screen.dart`, immediately after the Monarch/Initiative badges block (the `for (var i = 0; i < players.length; i++) if (game.monarchId == ... ) Positioned.fromRect(...)` block, right before the `Positioned.fromRect(rect: layout.toolbar, child: _Toolbar(...))` entry), add:
```dart
              // The active player's turn-countdown badge, seat-rotated,
              // positioned below the Monarch/Initiative badges (top: 80 vs.
              // their top: 48) so the two never overlap if a player holds
              // both. Ephemeral UI state, not a GameState status — a
              // sibling condition here rather than merged into
              // _ZoneStatusBadges.
              for (var i = 0; i < players.length; i++)
                if (settings.turnTimerEnabled &&
                    _activeTurnPlayerId == players[i].id)
                  Positioned.fromRect(
                    rect: rects[i],
                    child: IgnorePointer(
                      child: RotatedBox(
                        quarterTurns: turns[i],
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 80),
                            child: _TurnTimerBadge(
                              key: const ValueKey('turn-timer-badge'),
                              secondsRemaining: _turnSecondsRemaining(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
```

- [ ] **Step 6: Add the toolbar button and `_TurnTimerBadge` widget**

In `lib/ui/game_screen.dart`, change `_Toolbar`'s constructor/fields from:
```dart
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.playerCount,
    required this.dayNight,
    required this.onDayNight,
    required this.onSettings,
    required this.onUndo,
    required this.onDice,
    required this.onCoin,
    required this.onHistory,
    required this.onRitual,
  });

  final int playerCount;
  final DayNight dayNight;
  final VoidCallback? onDayNight;
  final VoidCallback? onSettings;
  final VoidCallback? onUndo;
  final VoidCallback? onDice;
  final VoidCallback? onCoin;
  final VoidCallback? onHistory;
  final VoidCallback onRitual;
```
to:
```dart
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.playerCount,
    required this.dayNight,
    required this.onDayNight,
    required this.onSettings,
    required this.onUndo,
    required this.onDice,
    required this.onCoin,
    required this.onHistory,
    required this.onRitual,
    required this.onEndTurn,
  });

  final int playerCount;
  final DayNight dayNight;
  final VoidCallback? onDayNight;
  final VoidCallback? onSettings;
  final VoidCallback? onUndo;
  final VoidCallback? onDice;
  final VoidCallback? onCoin;
  final VoidCallback? onHistory;
  final VoidCallback onRitual;
  final VoidCallback? onEndTurn;
```

In the same class's `build()`, change:
```dart
          IconButton(
            key: const ValueKey('ritual-icon'),
            tooltip: 'Pick starting player',
            color: Colors.white,
            onPressed: onRitual,
            icon: const Icon(Icons.shuffle),
          ),
        ],
      ),
    );
  }
}
```
to:
```dart
          IconButton(
            key: const ValueKey('ritual-icon'),
            tooltip: 'Pick starting player',
            color: Colors.white,
            onPressed: onRitual,
            icon: const Icon(Icons.shuffle),
          ),
          IconButton(
            key: const ValueKey('end-turn-icon'),
            tooltip: 'End turn',
            color: Colors.white,
            onPressed: onEndTurn,
            icon: const Icon(Icons.skip_next),
          ),
        ],
      ),
    );
  }
}
```

Add this new widget class at the end of `lib/ui/game_screen.dart` (after the last existing class):
```dart
/// The active player's turn countdown, styled like [_ZoneStatusBadge] (a
/// translucent-black, accent-bordered chip) but showing whole seconds
/// remaining and switching to the warning color once they've run out. A
/// rounded rect rather than a forced circle, since the digit count varies
/// (0-120). Purely a visual cue — reaching 0 never blocks or forces anything.
class _TurnTimerBadge extends StatelessWidget {
  const _TurnTimerBadge({super.key, required this.secondsRemaining});

  final int secondsRemaining;

  @override
  Widget build(BuildContext context) {
    final expired = secondsRemaining <= 0;
    final color = expired ? LifeTapColors.negative : LifeTapColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        '$secondsRemaining',
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; dart format --set-exit-if-changed lib/ui/game_screen.dart test/ui/turn_timer_test.dart && flutter analyze --no-fatal-infos && flutter test test/ui/turn_timer_test.dart'
```
Expected: format 0 changed, analyze no issues, all 4 tests pass.

- [ ] **Step 8: Run the full test suite to check for regressions**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test'
```
Expected: all tests pass (136 pre-existing + 4 new = 140).

- [ ] **Step 9: Commit**

```bash
git add lib/ui/game_screen.dart test/ui/turn_timer_test.dart
git commit -m "Add the turn timer: End Turn button and per-turn countdown badge"
```

---

### Task 3: Full verification sequence

**Files:** none (verification only).

**Interfaces:** none.

- [ ] **Step 1: Run the complete DEV_NOTES verification sequence**

```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; dart format --set-exit-if-changed lib test tool integration_test && flutter analyze --no-fatal-infos && flutter test'
```
Expected: format 0 changed, analyze no issues, all 140 tests pass.

The headless Linux integration test has proven unreliable in this sandbox in prior sessions — the format/analyze/full-suite run above plus GitHub Actions CI on push are the reliable checks.

- [ ] **Step 2: If anything fails, fix and re-run from Step 1**

Do not proceed until every check in Step 1 passes clean.
