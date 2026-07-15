# Starting Player Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up the existing-but-unused `RitualDetector`/`pickWinner` as a toolbar-triggered "hold a finger in every zone for 1.5s to pick who goes first" feature, re-triggerable any time during a game.

**Architecture:** `RitualDetector` gains a per-zone progress query; a new pure `zoneAt` helper is extracted from `PointerRouter` so raw pointer positions can be resolved to a zone without going through the full gesture state machine. `GameScreen` gains a ritual state machine that, while active, routes raw pointer events to the `RitualDetector` instead of the normal life-adjust `PointerRouter` path, and renders a seat-rotated per-zone overlay showing hold progress and the winner announcement.

**Tech Stack:** Flutter 3.44.0, Riverpod, Dart. Spec: `docs/superpowers/specs/2026-07-14-starting-player-picker-design.md`.

## Global Constraints

- Flutter 3.44.0 pinned; runs only in Docker (`ghcr.io/cirruslabs/flutter:3.44.0`), never on the host.
- Every task's commit must be preceded by the project's full verification sequence passing for the files it touches (see Task 4 for the complete sequence run at the end); at minimum `dart format` and the relevant `flutter test` file must pass before each task's commit.
- No Claude attribution or session links in any commit message.
- Commits use plain, factual messages describing the change (matching this repo's existing commit style — see `git log`).
- All new/changed Dart code follows the existing file's doc-comment density and naming style (see `lib/touch/pointer_router.dart` and `lib/ui/game_screen.dart` for the conventions already in place).

---

### Task 1: `zoneAt` helper + `RitualDetector.progressForZone`

**Files:**
- Modify: `lib/touch/pointer_router.dart:131-136` (removes `PointerRouter._zoneAt`, adds top-level `zoneAt`), `lib/touch/pointer_router.dart:158-167` (`down()` call site), `lib/touch/pointer_router.dart:323-340` (`RitualDetector.progress` refactor + new `progressForZone`)
- Test: `test/touch/pointer_router_test.dart`

**Interfaces:**
- Produces: `int? zoneAt(List<Rect> zones, Offset position)` — top-level function, returns the index of the zone containing `position`, or `null`. Produces: `double RitualDetector.progressForZone(int zone)` — that zone's own hold progress, 0..1, independent of other zones.
- Consumes: nothing new from outside this file.

- [ ] **Step 1: Write the failing tests**

Append to `test/touch/pointer_router_test.dart`, inside the existing `group('RitualDetector', () { ... })` block (after the `'lifting a finger before completion resets progress'` test, before the closing `});` of that group):

```dart
    test(
      'progressForZone reflects only that zone, independent of others',
      () {
        var now = Duration.zero;
        final ritual = RitualDetector(zoneCount: 2, clock: () => now);

        ritual.down(1, 0); // only zone 0 held
        now = const Duration(milliseconds: 750);

        expect(ritual.progressForZone(0), closeTo(750 / 1500, 1e-9));
        expect(ritual.progressForZone(1), 0.0);
      },
    );
```

Then add a new top-level group at the very end of `main()`, after the closing `});` of the `pickWinner` group and before the final `}` of `main()`:

```dart

  group('zoneAt', () {
    test('returns the index of the zone containing the position', () {
      const zones = [_zone0, _zone1];
      expect(zoneAt(zones, const Offset(50, 50)), 0);
      expect(zoneAt(zones, const Offset(50, 150)), 1);
    });

    test('returns null outside every zone', () {
      const zones = [_zone0, _zone1];
      expect(zoneAt(zones, const Offset(500, 500)), isNull);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test test/touch/pointer_router_test.dart'
```
Expected: FAIL — `progressForZone` and `zoneAt` are undefined.

- [ ] **Step 3: Extract `zoneAt` and update `PointerRouter`**

In `lib/touch/pointer_router.dart`, delete the private method (lines 131-136):
```dart
  int? _zoneAt(Offset p) {
    for (var i = 0; i < zones.length; i++) {
      if (zones[i].contains(p)) return i;
    }
    return null;
  }
```

Add this top-level function immediately above `class PointerRouter {` (before line 77):
```dart
/// Returns the index of the zone in [zones] containing [position], or null if
/// [position] falls outside every zone. Shared by [PointerRouter]'s internal
/// gesture tracking and any caller that needs the same lookup without going
/// through the full gesture state machine (the starting-player ritual).
int? zoneAt(List<Rect> zones, Offset position) {
  for (var i = 0; i < zones.length; i++) {
    if (zones[i].contains(position)) return i;
  }
  return null;
}
```

In `down()`, change the first line from:
```dart
  void down(int pointerId, Offset position) {
    final zone = _zoneAt(position);
```
to:
```dart
  void down(int pointerId, Offset position) {
    final zone = zoneAt(zones, position);
```

- [ ] **Step 4: Add `progressForZone` and refactor `progress`**

In `lib/touch/pointer_router.dart`, replace the `progress` getter (lines 323-340):
```dart
  double get progress {
    if (zoneCount == 0) return 0;
    final now = clock();
    final limit = holdDuration.inMicroseconds;
    var least = limit;
    for (var z = 0; z < zoneCount; z++) {
      int? bestHeld;
      for (final h in _holds.values) {
        if (h.zone != z) continue;
        final held = (now - h.since).inMicroseconds;
        if (bestHeld == null || held > bestHeld) bestHeld = held;
      }
      if (bestHeld == null) return 0; // this zone has no held pointer
      final clamped = bestHeld.clamp(0, limit);
      if (clamped < least) least = clamped;
    }
    return least / limit;
  }
```
with:
```dart
  double get progress {
    if (zoneCount == 0) return 0;
    var least = 1.0;
    for (var z = 0; z < zoneCount; z++) {
      final p = progressForZone(z);
      if (p == 0) return 0; // this zone has no held pointer
      if (p < least) least = p;
    }
    return least;
  }

  /// This zone's own hold progress, 0..1 — unlike [progress] (the minimum
  /// across every zone), this reflects only [zone]'s own held pointer, so a
  /// caller can render each zone's hold independently.
  double progressForZone(int zone) {
    final now = clock();
    final limit = holdDuration.inMicroseconds;
    int? bestHeld;
    for (final h in _holds.values) {
      if (h.zone != zone) continue;
      final held = (now - h.since).inMicroseconds;
      if (bestHeld == null || held > bestHeld) bestHeld = held;
    }
    if (bestHeld == null) return 0;
    return bestHeld.clamp(0, limit) / limit;
  }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; dart format --set-exit-if-changed lib/touch/pointer_router.dart test/touch/pointer_router_test.dart && flutter analyze --no-fatal-infos && flutter test test/touch/pointer_router_test.dart'
```
Expected: format reports 0 changed, analyze reports no issues, all tests (including the 3 pre-existing `RitualDetector` tests, all `PointerRouter` tests, and the 2 new `zoneAt` tests) PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/touch/pointer_router.dart test/touch/pointer_router_test.dart
git commit -m "Extract zoneAt helper and add RitualDetector.progressForZone"
```

---

### Task 2: Wire the ritual picker into GameScreen

**Files:**
- Modify: `lib/ui/game_screen.dart` (class `GameScreen` and `_GameScreenState`, the pointer handlers, `_Toolbar`, `build()`)
- Create: new private widgets `_RitualOverlay`, `_RitualProgressPanel`, `_RitualWinnerBanner` in `lib/ui/game_screen.dart`
- Test: Create `test/ui/ritual_picker_test.dart`

**Interfaces:**
- Consumes: `int? zoneAt(List<Rect> zones, Offset position)` and `RitualDetector` (with `progressForZone`) from Task 1, both already exported by `lib/touch/pointer_router.dart` (already imported in `game_screen.dart:13`). `pickWinner(List<int> pointerIds, int seed)` from `lib/touch/pointer_router.dart:356-361` (pre-existing).
- Produces: `GameScreen({super.key, Duration Function()? clock})` — new optional constructor param for test injection.

- [ ] **Step 1: Write the failing widget test**

Create `test/ui/ritual_picker_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/ui/game_screen.dart';

// Default 4-player layout on the 800x600 test window: zone centers, well
// clear of the corner icons and commander-damage grid.
const _zoneCenters = [
  Offset(200, 134),
  Offset(600, 134),
  Offset(200, 466),
  Offset(600, 466),
];

void main() {
  testWidgets(
    'holding a finger in every zone for 1.5s announces a winner and leaves '
    'life totals unchanged',
    (tester) async {
      var now = Duration.zero;
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(home: GameScreen(clock: () => now))),
      );
      await tester.pump();

      expect(find.text('40'), findsNWidgets(4));

      await tester.tap(find.byKey(const ValueKey('ritual-icon')));
      await tester.pump();
      expect(find.byKey(const ValueKey('ritual-overlay')), findsOneWidget);

      final gestures = <TestGesture>[];
      for (var i = 0; i < _zoneCenters.length; i++) {
        gestures.add(
          await tester.startGesture(_zoneCenters[i], pointer: i + 1),
        );
      }

      now = const Duration(milliseconds: 1600);
      await tester.pump(const Duration(milliseconds: 1600));

      expect(
        find.byKey(const ValueKey('ritual-winner-banner')),
        findsOneWidget,
      );
      expect(
        find.text('40'),
        findsNWidgets(4),
        reason: 'holding fingers during the ritual must not change life',
      );

      for (final gesture in gestures) {
        await gesture.up();
      }

      now += const Duration(milliseconds: 2600);
      await tester.pump(const Duration(milliseconds: 2600));
      expect(find.byKey(const ValueKey('ritual-overlay')), findsNothing);
    },
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test test/ui/ritual_picker_test.dart'
```
Expected: FAIL — `GameScreen(clock: ...)` doesn't exist and `ValueKey('ritual-icon')` is never found.

- [ ] **Step 3: Add the `clock` constructor param and thread it to `PointerRouter`**

In `lib/ui/game_screen.dart`, replace lines 25-30:
```dart
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}
```
with:
```dart
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, this.clock});

  /// Overrides the pointer router's and ritual detector's time source.
  /// Defaults to real time; tests inject a controllable clock so a 1.5s hold
  /// can be simulated without waiting on the wall clock.
  final Duration Function()? clock;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}
```

In `initState()` (line 41), change:
```dart
    _router = PointerRouter(onResult: _onResult);
```
to:
```dart
    _router = PointerRouter(onResult: _onResult, clock: widget.clock);
```

- [ ] **Step 4: Add ritual state fields and lifecycle methods to `_GameScreenState`**

In `lib/ui/game_screen.dart`, in `_GameScreenState` (after line 36, `Timer? _holdTimer;`), add:
```dart
  bool _ritualActive = false;
  RitualDetector? _ritualDetector;
  int? _ritualWinnerPlayerId;
  final Map<int, int> _ritualPointerZones = {};
  Timer? _ritualDismissTimer;
```

Change the `_holdTimer` assignment in `initState()` (lines 45-48) from:
```dart
    _holdTimer = Timer.periodic(
      const Duration(milliseconds: 60),
      (_) => _router.tick(),
    );
```
to:
```dart
    _holdTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      _router.tick();
      _ritualTick();
    });
```

Change `dispose()` (lines 52-56) from:
```dart
  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }
```
to:
```dart
  @override
  void dispose() {
    _holdTimer?.cancel();
    _ritualDismissTimer?.cancel();
    super.dispose();
  }
```

Add these new methods to `_GameScreenState`, immediately after `_onResult` (after line 86, before `_onPointerDown`):
```dart
  void _toggleRitual() {
    if (_ritualActive) {
      _closeRitual();
    } else {
      _openRitual();
    }
  }

  void _openRitual() {
    final playerCount = ref.read(gameProvider).current.players.length;
    setState(() {
      _ritualDetector = RitualDetector(
        zoneCount: playerCount,
        clock: _router.clock,
      );
      _ritualActive = true;
      _ritualWinnerPlayerId = null;
      _ritualPointerZones.clear();
    });
  }

  void _ritualTick() {
    if (!_ritualActive || _ritualWinnerPlayerId != null) return;
    if (_ritualDetector!.poll()) {
      _completeRitual();
    } else {
      setState(() {});
    }
  }

  void _completeRitual() {
    final pointerIds = _ritualPointerZones.keys.toList();
    final winnerPointer = pickWinner(pointerIds, Random().nextInt(1 << 32));
    final winnerZone = _ritualPointerZones[winnerPointer]!;
    final winnerPlayerId = ref
        .read(gameProvider)
        .current
        .players[winnerZone]
        .id;
    setState(() => _ritualWinnerPlayerId = winnerPlayerId);
    _ritualDismissTimer = Timer(
      const Duration(milliseconds: 2500),
      _closeRitual,
    );
  }

  void _closeRitual() {
    _ritualDismissTimer?.cancel();
    _ritualDismissTimer = null;
    setState(() {
      _ritualActive = false;
      _ritualDetector = null;
      _ritualWinnerPlayerId = null;
      _ritualPointerZones.clear();
    });
  }
```

- [ ] **Step 5: Route pointer events to the ritual detector while active**

In `lib/ui/game_screen.dart`, replace the four pointer handlers (lines 88-105):
```dart
  void _onPointerDown(PointerDownEvent e) {
    _downAt[e.pointer] = e.timeStamp;
    _router.down(e.pointer, e.localPosition);
  }

  void _onPointerMove(PointerMoveEvent e) {
    _router.move(e.pointer, e.localPosition);
  }

  void _onPointerUp(PointerUpEvent e) {
    final downAt = _downAt.remove(e.pointer) ?? e.timeStamp;
    _router.up(e.pointer, heldFor: e.timeStamp - downAt);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _downAt.remove(e.pointer);
    _router.cancel(e.pointer);
  }
```
with:
```dart
  void _onPointerDown(PointerDownEvent e) {
    if (_ritualActive) {
      final zone = zoneAt(_router.zones, e.localPosition);
      if (zone != null) {
        _ritualDetector!.down(e.pointer, zone);
        _ritualPointerZones[e.pointer] = zone;
        setState(() {});
      }
      return;
    }
    _downAt[e.pointer] = e.timeStamp;
    _router.down(e.pointer, e.localPosition);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_ritualActive) return;
    _router.move(e.pointer, e.localPosition);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_ritualActive) {
      _ritualDetector?.up(e.pointer);
      _ritualPointerZones.remove(e.pointer);
      setState(() {});
      return;
    }
    final downAt = _downAt.remove(e.pointer) ?? e.timeStamp;
    _router.up(e.pointer, heldFor: e.timeStamp - downAt);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_ritualActive) {
      _ritualDetector?.up(e.pointer);
      _ritualPointerZones.remove(e.pointer);
      setState(() {});
      return;
    }
    _downAt.remove(e.pointer);
    _router.cancel(e.pointer);
  }
```

- [ ] **Step 6: Add the toolbar icon**

In `lib/ui/game_screen.dart`, find the `_Toolbar` class (around line 2125) and add a new required param. Change:
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
  });

  final int playerCount;
  final DayNight dayNight;
  final VoidCallback onDayNight;
  final VoidCallback onSettings;
  final VoidCallback onUndo;
  final VoidCallback onDice;
  final VoidCallback onCoin;
  final VoidCallback onHistory;
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
  });

  final int playerCount;
  final DayNight dayNight;
  final VoidCallback onDayNight;
  final VoidCallback onSettings;
  final VoidCallback onUndo;
  final VoidCallback onDice;
  final VoidCallback onCoin;
  final VoidCallback onHistory;
  final VoidCallback onRitual;
```

In the same class's `build()`, the `Row`'s `children` list ends with the History `IconButton`. Add a new `IconButton` immediately after it (still inside the `children` list, before the closing `],`):
```dart
          IconButton(
            key: const ValueKey('ritual-icon'),
            tooltip: 'Pick starting player',
            color: Colors.white,
            onPressed: onRitual,
            icon: const Icon(Icons.shuffle),
          ),
```

In `build()` of `_GameScreenState` (around line 257-267), the `_Toolbar(...)` construction currently ends with `onHistory: _showHistory,`. Add `onRitual: _toggleRitual,` immediately after it:
```dart
                child: _Toolbar(
                  playerCount: players.length,
                  dayNight: game.dayNight,
                  onDayNight: () =>
                      ref.read(gameProvider.notifier).cycleDayNight(),
                  onSettings: _openSettings,
                  onUndo: () => ref.read(gameProvider.notifier).undo(),
                  onDice: _showDice,
                  onCoin: _showCoin,
                  onHistory: _showHistory,
                  onRitual: _toggleRitual,
                ),
```

- [ ] **Step 7: Add the overlay widgets and wire them into `build()`**

In `lib/ui/game_screen.dart`, in `build()`, the outer `Stack`'s `children` list currently ends with the `_Toolbar` entry (the `Positioned.fromRect(rect: layout.toolbar, child: _Toolbar(...))` block, immediately before the closing `],` of `children` around line 268). Add a new conditional entry immediately after it:
```dart
              if (_ritualActive)
                _RitualOverlay(
                  players: players,
                  rects: rects,
                  turns: turns,
                  detector: _ritualDetector!,
                  winnerPlayerId: _ritualWinnerPlayerId,
                  onClose: _closeRitual,
                ),
```

Add these three new widget classes at the end of `lib/ui/game_screen.dart` (after the last existing class in the file):
```dart
class _RitualOverlay extends StatelessWidget {
  const _RitualOverlay({
    required this.players,
    required this.rects,
    required this.turns,
    required this.detector,
    required this.winnerPlayerId,
    required this.onClose,
  });

  final List<PlayerState> players;
  final List<Rect> rects;
  final List<int> turns;
  final RitualDetector detector;
  final int? winnerPlayerId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const ValueKey('ritual-overlay'),
      children: [
        const Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(color: Color(0xCC000000)),
          ),
        ),
        for (var i = 0; i < players.length; i++)
          Positioned.fromRect(
            rect: rects[i],
            child: IgnorePointer(
              child: RotatedBox(
                quarterTurns: turns[i],
                child: Center(
                  child: winnerPlayerId == null
                      ? _RitualProgressPanel(
                          progress: detector.progressForZone(i),
                        )
                      : winnerPlayerId == players[i].id
                      ? const _RitualWinnerBanner()
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            key: const ValueKey('ritual-close'),
            tooltip: 'Cancel',
            color: Colors.white,
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ),
      ],
    );
  }
}

class _RitualProgressPanel extends StatelessWidget {
  const _RitualProgressPanel({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 6,
            color: LifeTapColors.accent,
            backgroundColor: LifeTapColors.chipUnselected,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Hold',
          style: TextStyle(
            color: LifeTapColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}

class _RitualWinnerBanner extends StatelessWidget {
  const _RitualWinnerBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('ritual-winner-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: LifeTapColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LifeTapColors.accent, width: 2),
      ),
      child: const Text(
        'You go first!',
        style: TextStyle(
          color: LifeTapColors.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 20,
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Run the test to verify it passes**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; dart format --set-exit-if-changed lib/ui/game_screen.dart test/ui/ritual_picker_test.dart && flutter analyze --no-fatal-infos && flutter test test/ui/ritual_picker_test.dart'
```
Expected: format reports 0 changed, analyze reports no issues, the test PASSES.

- [ ] **Step 9: Run the full test suite to check for regressions**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test'
```
Expected: all tests pass (98 pre-existing + 1 new = 99).

- [ ] **Step 10: Commit**

```bash
git add lib/ui/game_screen.dart test/ui/ritual_picker_test.dart
git commit -m "Wire up the starting-player ritual picker"
```

---

### Task 3: Cancellation behavior and icon guards during the ritual

**Files:**
- Modify: `lib/ui/game_screen.dart` (the per-player settings and counters `IconButton`s)
- Test: `test/ui/ritual_picker_test.dart`

**Interfaces:**
- Consumes: everything from Task 2 (`_ritualActive`, `_closeRitual`, ritual `ValueKey`s).
- Produces: `ValueKey('settings-<playerId>')` on the per-player settings `IconButton` (new — the counters icon already has an equivalent key).

- [ ] **Step 1: Write the failing tests**

Append to `test/ui/ritual_picker_test.dart`, inside `main()` after the existing `testWidgets` block:

```dart

  testWidgets(
    'one zone lifting before every zone qualifies resets progress and never '
    'announces a winner',
    (tester) async {
      var now = Duration.zero;
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(home: GameScreen(clock: () => now))),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('ritual-icon')));
      await tester.pump();

      final gestures = <TestGesture>[];
      for (var i = 0; i < _zoneCenters.length; i++) {
        gestures.add(
          await tester.startGesture(_zoneCenters[i], pointer: i + 1),
        );
      }

      now = const Duration(milliseconds: 1000);
      await tester.pump(const Duration(milliseconds: 1000));

      // Player 0 lifts early, well before the 1.5s hold window elapses.
      await gestures[0].up();
      now = const Duration(milliseconds: 1600);
      await tester.pump(const Duration(milliseconds: 1600));

      expect(
        find.byKey(const ValueKey('ritual-winner-banner')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('ritual-overlay')), findsOneWidget);

      for (var i = 1; i < gestures.length; i++) {
        await gestures[i].up();
      }
      await tester.tap(find.byKey(const ValueKey('ritual-close')));
      await tester.pump();
      expect(find.byKey(const ValueKey('ritual-overlay')), findsNothing);
    },
  );

  testWidgets(
    'the per-player settings and counters icons are disabled while the '
    'ritual is active',
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

      final id = container.read(gameProvider).current.players.first.id;

      await tester.tap(find.byKey(const ValueKey('ritual-icon')));
      await tester.pump();

      final settingsButton = tester.widget<IconButton>(
        find.byKey(ValueKey('settings-$id')),
      );
      final countersButton = tester.widget<IconButton>(
        find.byKey(ValueKey('counters-$id')),
      );
      expect(settingsButton.onPressed, isNull);
      expect(countersButton.onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('ritual-close')));
      await tester.pump();

      final settingsAfter = tester.widget<IconButton>(
        find.byKey(ValueKey('settings-$id')),
      );
      expect(settingsAfter.onPressed, isNotNull);
    },
  );
```

Add the missing import at the top of `test/ui/ritual_picker_test.dart`:
```dart
import 'package:lifetap/game/game_notifier.dart';
```

- [ ] **Step 2: Run the tests to verify the icon-guard test fails**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test test/ui/ritual_picker_test.dart'
```
Expected: the cancellation test PASSES already (cancellation is inherent to `RitualDetector.up()` from Task 1/2 — this test documents and locks in that behavior). The icon-guard test FAILS: `find.byKey(ValueKey('settings-$id'))` finds nothing (no such key exists yet).

- [ ] **Step 3: Add the settings icon key and disable both icons during the ritual**

In `lib/ui/game_screen.dart`, find the per-player settings `IconButton` (around line 158-165):
```dart
                Positioned.fromRect(
                  rect: rects[i],
                  child: Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      tooltip: 'Player settings',
                      color: Colors.white70,
                      iconSize: 20,
                      icon: const Icon(Icons.settings),
                      onPressed: () =>
                          _showPlayerSettings(players[i].id, turns[i]),
                    ),
                  ),
                ),
```
Replace with:
```dart
                Positioned.fromRect(
                  rect: rects[i],
                  child: Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      key: ValueKey('settings-${players[i].id}'),
                      tooltip: 'Player settings',
                      color: Colors.white70,
                      iconSize: 20,
                      icon: const Icon(Icons.settings),
                      onPressed: _ritualActive
                          ? null
                          : () => _showPlayerSettings(players[i].id, turns[i]),
                    ),
                  ),
                ),
```

Find the per-player counters `IconButton` (around line 174-188):
```dart
                Positioned.fromRect(
                  rect: rects[i],
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      key: ValueKey('counters-${players[i].id}'),
                      tooltip: 'Counters',
                      color: Colors.white70,
                      iconSize: 20,
                      icon: const Icon(Icons.grid_view),
                      onPressed: () => _showCounters(players[i].id, turns[i]),
                    ),
                  ),
                ),
```
Replace with:
```dart
                Positioned.fromRect(
                  rect: rects[i],
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      key: ValueKey('counters-${players[i].id}'),
                      tooltip: 'Counters',
                      color: Colors.white70,
                      iconSize: 20,
                      icon: const Icon(Icons.grid_view),
                      onPressed: _ritualActive
                          ? null
                          : () => _showCounters(players[i].id, turns[i]),
                    ),
                  ),
                ),
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; dart format --set-exit-if-changed lib/ui/game_screen.dart test/ui/ritual_picker_test.dart && flutter analyze --no-fatal-infos && flutter test test/ui/ritual_picker_test.dart'
```
Expected: format reports 0 changed, analyze reports no issues, all 3 tests in the file PASS.

- [ ] **Step 5: Run the full test suite to check for regressions**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test'
```
Expected: all tests pass (99 pre-existing + 2 new = 101).

- [ ] **Step 6: Commit**

```bash
git add lib/ui/game_screen.dart test/ui/ritual_picker_test.dart
git commit -m "Disable per-player settings/counters icons during the ritual"
```

---

### Task 4: Full verification sequence

**Files:** none (verification only).

**Interfaces:** none.

- [ ] **Step 1: Run the complete DEV_NOTES verification sequence**

Run each in sequence, in Docker (per `DEV_NOTES.md`):
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; dart format --set-exit-if-changed lib test tool integration_test && flutter analyze --no-fatal-infos && flutter test'
```
Expected: format 0 changed, analyze no issues, all tests pass.

```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c '
git config --global --add safe.directory /app
apt-get update -qq && apt-get install -y -qq xvfb libgtk-3-dev ninja-build clang cmake pkg-config liblzma-dev
flutter config --enable-linux-desktop
xvfb-run -a flutter test integration_test -d linux
'
```
Expected: the integration suite passes. Run this one in the background with a generous timeout (Linux desktop toolchain install + first build is slow) and run only a single instance at a time — do not launch a second overlapping run against the same `PUB_CACHE`/`build/` mount, since two concurrent containers sharing that state can lock-contend or hang each other.

- [ ] **Step 2: If anything fails, fix and re-run from Step 1**

Do not proceed until every check in Step 1 passes clean.

- [ ] **Step 3: Push**

```bash
git push
```
This is a normal fast-forward push (no history rewrite involved) — safe to run directly.
