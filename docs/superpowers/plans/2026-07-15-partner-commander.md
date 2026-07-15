# Partner/Background Commander Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a player record a second commander (Partner/Background) with its own Scryfall art resolution, alongside their primary commander.

**Architecture:** `PlayerState` gains `partnerCommanderName`/`partnerArtUrl` (mirroring the existing `commanderName`/`artUrl` pair exactly, including the `_unset` sentinel pattern). A new `SetPartnerCommander` event mirrors `SetCommander`. `_PlayerSettingsSheet` gains a second field with its own independent async-resolution plumbing, mirroring the existing commander field's exactly. **Per the design spec, this does not touch commander-damage tracking or any main-game-screen display** — see the spec's "scope decision" section for why.

**Tech Stack:** Flutter 3.44.0, Riverpod.

## Global Constraints

- Flutter 3.44.0 pinned; runs only in Docker (`ghcr.io/cirruslabs/flutter:3.44.0`), never on the host.
- `dart format` and `flutter analyze` must be clean, and the relevant `flutter test` file must pass, before each task's commit.
- No Claude attribution or session links in any commit message.
- Commits use plain, factual messages matching this repo's existing style.
- No changes to `commanderDamage`, `_commanderDamageGrid`, `PlayerState.isDead`, or any main-game-screen (`GameScreen`) widget — this feature is scoped to data + the settings sheet only, per the design spec.
- The partner field's async resolution must mirror the primary commander field's exactly: independent stale-request guard, independent resolving spinner, "keep existing art on failed lookup" behavior, in-app-keyboard/native dual path.

---

### Task 1: Data model — `PlayerState` fields and the `SetPartnerCommander` event

**Files:**
- Modify: `lib/game/game_state.dart`
- Modify: `lib/game/game_events.dart`
- Test: Modify `test/game/game_events_test.dart`, `test/game/game_events_json_test.dart`

**Interfaces:**
- Produces: `PlayerState.partnerCommanderName`/`.partnerArtUrl` (both `String?`, default `null`), threaded through `copyWith` with the `_unset` sentinel. `class SetPartnerCommander extends GameEvent` with `playerId`, `commanderName`, `artUrl` fields, `apply`, `describe`, `toJson`. A new `'SetPartnerCommander'` case in `eventFromJson`.

- [ ] **Step 1: Write the failing tests**

In `test/game/game_events_test.dart`, add this group immediately after the existing `group('SetCommander describe', ...)` block (after its closing `});`, before `group('rename and recolor', ...)`):
```dart
  group('SetPartnerCommander describe', () {
    test('a cleared partner reads as cleared, not "→ null"', () {
      final state = _newGame();
      final line = const SetPartnerCommander(
        playerId: 0,
        commanderName: null,
      ).describe(state);

      expect(line, isNot(contains('null')));
      expect(line.toLowerCase(), contains('cleared'));
    });

    test('setting a partner shows the name', () {
      final state = _newGame();
      final line = const SetPartnerCommander(
        playerId: 0,
        commanderName: 'Thrasios, Triton Hero',
      ).describe(state);

      expect(line, contains('Thrasios, Triton Hero'));
    });

    test('setting a partner does not disturb the primary commander', () {
      var state = _newGame();
      state = const SetCommander(
        playerId: 0,
        commanderName: 'Atraxa',
        artUrl: 'http://art/atraxa',
      ).apply(state);
      state = const SetPartnerCommander(
        playerId: 0,
        commanderName: 'Thrasios, Triton Hero',
        artUrl: 'http://art/thrasios',
      ).apply(state);

      final player = state.player(0);
      expect(player.commanderName, 'Atraxa');
      expect(player.artUrl, 'http://art/atraxa');
      expect(player.partnerCommanderName, 'Thrasios, Triton Hero');
      expect(player.partnerArtUrl, 'http://art/thrasios');
    });
  });
```

In `test/game/game_events_json_test.dart`, add this test immediately after the existing `'SetCommander round-trips (both fields null)'` test (after its closing `});`, before `'RecolorPlayer round-trips'`):
```dart
  test('SetPartnerCommander round-trips (both fields set)', () {
    _expectRoundTrips(
      const SetPartnerCommander(
        playerId: 0,
        commanderName: 'Thrasios, Triton Hero',
        artUrl: 'http://art/thrasios',
      ),
    );
  });

  test('SetPartnerCommander round-trips (both fields null)', () {
    _expectRoundTrips(const SetPartnerCommander(playerId: 0));
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test test/game/game_events_test.dart test/game/game_events_json_test.dart'
```
Expected: FAIL — `SetPartnerCommander` and `PlayerState.partnerCommanderName`/`.partnerArtUrl` don't exist.

- [ ] **Step 3: Add the `PlayerState` fields**

In `lib/game/game_state.dart`, change:
```dart
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
```
to:
```dart
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
    this.partnerCommanderName,
    this.partnerArtUrl,
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

  /// A second commander (Partner/Background), or null if none has been set.
  /// Recorded name/art only — this app does not track commander damage
  /// separately per commander, only per opponent (see the design spec).
  final String? partnerCommanderName;

  /// Resolved art URL for [partnerCommanderName], or null.
  final String? partnerArtUrl;
```

Change:
```dart
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
```
to:
```dart
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
    Object? partnerCommanderName = _unset,
    Object? partnerArtUrl = _unset,
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
      partnerCommanderName: identical(partnerCommanderName, _unset)
          ? this.partnerCommanderName
          : partnerCommanderName as String?,
      partnerArtUrl: identical(partnerArtUrl, _unset)
          ? this.partnerArtUrl
          : partnerArtUrl as String?,
    );
  }
}
```

- [ ] **Step 4: Add the `SetPartnerCommander` event**

In `lib/game/game_events.dart`, add this class immediately after `SetCommander`'s closing brace (after line 261, before `RecolorPlayer`):
```dart

/// Sets a player's second commander (Partner/Background) name and resolved
/// art URL (either may be null to clear it) — recorded alongside, and
/// entirely independent of, the primary commander set by [SetCommander].
class SetPartnerCommander extends GameEvent {
  const SetPartnerCommander({
    required this.playerId,
    this.commanderName,
    this.artUrl,
  });

  final int playerId;
  final String? commanderName;
  final String? artUrl;

  @override
  GameState apply(GameState state) => state.replacePlayer(
    state
        .player(playerId)
        .copyWith(
          partnerCommanderName: commanderName,
          partnerArtUrl: artUrl,
        ),
  );

  @override
  String describe(GameState before) {
    final name = before.player(playerId).name;
    return commanderName == null
        ? '$name partner cleared'
        : '$name partner → $commanderName';
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'SetPartnerCommander',
    'playerId': playerId,
    'commanderName': commanderName,
    'artUrl': artUrl,
  };
}
```

- [ ] **Step 5: Add the `eventFromJson` case**

In `lib/game/game_events.dart`, change:
```dart
    'SetCommander' => SetCommander(
      playerId: json['playerId'] as int,
      commanderName: json['commanderName'] as String?,
      artUrl: json['artUrl'] as String?,
    ),
    'RecolorPlayer' => RecolorPlayer(
```
to:
```dart
    'SetCommander' => SetCommander(
      playerId: json['playerId'] as int,
      commanderName: json['commanderName'] as String?,
      artUrl: json['artUrl'] as String?,
    ),
    'SetPartnerCommander' => SetPartnerCommander(
      playerId: json['playerId'] as int,
      commanderName: json['commanderName'] as String?,
      artUrl: json['artUrl'] as String?,
    ),
    'RecolorPlayer' => RecolorPlayer(
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; dart format --set-exit-if-changed lib/game/game_state.dart lib/game/game_events.dart test/game/game_events_test.dart test/game/game_events_json_test.dart && flutter analyze --no-fatal-infos && flutter test test/game/game_events_test.dart test/game/game_events_json_test.dart'
```
Expected: format 0 changed, analyze no issues, all tests pass.

- [ ] **Step 7: Run the full test suite to check for regressions**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test'
```
Expected: all tests pass (140 pre-existing + 3 new game_events + 2 new json = 145).

- [ ] **Step 8: Commit**

```bash
git add lib/game/game_state.dart lib/game/game_events.dart test/game/game_events_test.dart test/game/game_events_json_test.dart
git commit -m "Add partner/background commander to the data model"
```

---

### Task 2: Partner field in the player settings sheet

**Files:**
- Modify: `lib/ui/game_screen.dart`
- Test: Create `test/ui/partner_commander_test.dart`

**Interfaces:**
- Consumes: `PlayerState.partnerCommanderName`/`.partnerArtUrl`, `SetPartnerCommander` from Task 1. `commanderArtSourceProvider` (pre-existing, `lib/data/commander_art.dart`).
- Produces: `_PlayerSettingsSheetState._partnerController`, `._resolvingPartner`, `._partnerSubmitId`, `._submitPartnerCommander`.

- [ ] **Step 1: Write the failing test**

Create `test/ui/partner_commander_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/data/commander_art.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/ui/game_screen.dart';

/// Resolves any name to a fixed URL immediately, keyed by the exact name, so
/// a test can tell which of the two fields' submissions actually resolved.
class _FakeArtSource implements CommanderArtSource {
  @override
  Future<String?> artUrl(String commanderName) =>
      Future.value('http://art/$commanderName');
}

void main() {
  testWidgets(
    'submitting the partner field resolves art and dispatches '
    'SetPartnerCommander independently of the primary commander field',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          commanderArtSourceProvider.overrideWithValue(_FakeArtSource()),
        ],
      );
      addTearDown(container.dispose);
      container.read(gameProvider.notifier).newGame(2, 20);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();

      final id = container.read(gameProvider).current.players.first.id;
      await tester.tap(find.byKey(ValueKey('cmdr-me-$id')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('field-commander')),
        'Atraxa',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('field-partner')),
        'Thrasios',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final player = container.read(gameProvider).current.player(id);
      expect(player.commanderName, 'Atraxa');
      expect(player.artUrl, 'http://art/Atraxa');
      expect(player.partnerCommanderName, 'Thrasios');
      expect(player.partnerArtUrl, 'http://art/Thrasios');
    },
  );

  testWidgets(
    'a failed partner lookup keeps the previously-resolved partner art and '
    'does not touch the primary commander',
    (tester) async {
      var partnerFails = false;
      final source = _ToggleFailArtSource(() => partnerFails);
      final container = ProviderContainer(
        overrides: [commanderArtSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);
      container.read(gameProvider.notifier).newGame(2, 20);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();

      final id = container.read(gameProvider).current.players.first.id;
      await tester.tap(find.byKey(ValueKey('cmdr-me-$id')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('field-commander')),
        'Atraxa',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('field-partner')),
        'Thrasios',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        container.read(gameProvider).current.player(id).partnerArtUrl,
        'http://art/Thrasios',
      );

      partnerFails = true;
      await tester.enterText(
        find.byKey(const ValueKey('field-partner')),
        'Kraum',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final player = container.read(gameProvider).current.player(id);
      expect(player.partnerCommanderName, 'Kraum');
      expect(
        player.partnerArtUrl,
        'http://art/Thrasios',
        reason: 'a failed lookup must not blank the previously-resolved art',
      );
      expect(
        player.commanderName,
        'Atraxa',
        reason: 'the partner field must never touch the primary commander',
      );
      expect(player.artUrl, 'http://art/Atraxa');

      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );
}

/// Resolves to a fixed URL unless [shouldFail] reads true at call time, in
/// which case it returns null — models a lookup that starts working and
/// later fails, independent per call rather than a one-shot toggle.
class _ToggleFailArtSource implements CommanderArtSource {
  _ToggleFailArtSource(this.shouldFail);

  final bool Function() shouldFail;

  @override
  Future<String?> artUrl(String commanderName) =>
      Future.value(shouldFail() ? null : 'http://art/$commanderName');
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test test/ui/partner_commander_test.dart'
```
Expected: FAIL — `ValueKey('field-partner')` doesn't exist.

- [ ] **Step 3: Add the partner controller, submit handler, and field**

In `lib/ui/game_screen.dart`, change:
```dart
class _PlayerSettingsSheetState extends ConsumerState<_PlayerSettingsSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _commanderController;
  bool _resolving = false;
  int _commanderSubmitId = 0;

  @override
  void initState() {
    super.initState();
    final player = ref.read(gameProvider).current.player(widget.playerId);
    _nameController = TextEditingController(text: player.name);
    _commanderController = TextEditingController(
      text: player.commanderName ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _commanderController.dispose();
    super.dispose();
  }
```
to:
```dart
class _PlayerSettingsSheetState extends ConsumerState<_PlayerSettingsSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _commanderController;
  late final TextEditingController _partnerController;
  bool _resolving = false;
  bool _resolvingPartner = false;
  int _commanderSubmitId = 0;
  int _partnerSubmitId = 0;

  @override
  void initState() {
    super.initState();
    final player = ref.read(gameProvider).current.player(widget.playerId);
    _nameController = TextEditingController(text: player.name);
    _commanderController = TextEditingController(
      text: player.commanderName ?? '',
    );
    _partnerController = TextEditingController(
      text: player.partnerCommanderName ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _commanderController.dispose();
    _partnerController.dispose();
    super.dispose();
  }
```

Add this method to `_PlayerSettingsSheetState`, immediately after `_submitCommander` (before `_recolor`):
```dart
  Future<void> _submitPartnerCommander(String value) async {
    final submitId = ++_partnerSubmitId;
    final name = value.trim();
    final notifier = ref.read(gameProvider.notifier);
    if (name.isEmpty) {
      notifier.dispatch(
        SetPartnerCommander(
          playerId: widget.playerId,
          commanderName: null,
          artUrl: null,
        ),
      );
      return;
    }
    setState(() => _resolvingPartner = true);
    final art = await ref.read(commanderArtSourceProvider).artUrl(name);
    if (!mounted || submitId != _partnerSubmitId) return;
    setState(() => _resolvingPartner = false);
    final existingArt = ref
        .read(gameProvider)
        .current
        .player(widget.playerId)
        .partnerArtUrl;
    notifier.dispatch(
      SetPartnerCommander(
        playerId: widget.playerId,
        commanderName: name,
        artUrl: art ?? existingArt,
      ),
    );
    if (art == null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn\'t find art for "$name"')));
    }
  }
```

- [ ] **Step 4: Wire the field's re-sync in `_editField`**

In `lib/ui/game_screen.dart`, change:
```dart
    if (!mounted) return;
    final player = ref.read(gameProvider).current.player(widget.playerId);
    if (identical(controller, _nameController)) {
      setState(() => _nameController.text = player.name);
    } else if (identical(controller, _commanderController) && !_resolving) {
      setState(() => _commanderController.text = player.commanderName ?? '');
    }
  }
```
to:
```dart
    if (!mounted) return;
    final player = ref.read(gameProvider).current.player(widget.playerId);
    if (identical(controller, _nameController)) {
      setState(() => _nameController.text = player.name);
    } else if (identical(controller, _commanderController) && !_resolving) {
      setState(() => _commanderController.text = player.commanderName ?? '');
    } else if (identical(controller, _partnerController) &&
        !_resolvingPartner) {
      setState(
        () => _partnerController.text = player.partnerCommanderName ?? '',
      );
    }
  }
```

- [ ] **Step 5: Add the field to the sheet's UI**

In `lib/ui/game_screen.dart`'s `_PlayerSettingsSheetState.build()`, change:
```dart
    final Widget? suffix = _resolving
        ? const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : null;
```
to:
```dart
    final Widget? suffix = _resolving
        ? const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : null;
    final Widget? partnerSuffix = _resolvingPartner
        ? const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : null;
```

Change:
```dart
                    else
                      TextField(
                        key: const ValueKey('field-commander'),
                        controller: _commanderController,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'Commander',
                          suffixIcon: suffix,
                        ),
                        onSubmitted: _submitCommander,
                      ),
                    const SizedBox(height: 16),
                    Row(
```
to:
```dart
                    else
                      TextField(
                        key: const ValueKey('field-commander'),
                        controller: _commanderController,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'Commander',
                          suffixIcon: suffix,
                        ),
                        onSubmitted: _submitCommander,
                      ),
                    const SizedBox(height: 12),
                    if (inAppKeyboard)
                      TextField(
                        key: const ValueKey('field-partner'),
                        controller: _partnerController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Partner / Background',
                          suffixIcon: partnerSuffix,
                        ),
                        onTap: () => _editField(
                          _partnerController,
                          'Partner / Background',
                          _submitPartnerCommander,
                        ),
                      )
                    else
                      TextField(
                        key: const ValueKey('field-partner'),
                        controller: _partnerController,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'Partner / Background',
                          suffixIcon: partnerSuffix,
                        ),
                        onSubmitted: _submitPartnerCommander,
                      ),
                    const SizedBox(height: 16),
                    Row(
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; dart format --set-exit-if-changed lib/ui/game_screen.dart test/ui/partner_commander_test.dart && flutter analyze --no-fatal-infos && flutter test test/ui/partner_commander_test.dart'
```
Expected: format 0 changed, analyze no issues, both tests pass.

- [ ] **Step 7: Run the full test suite to check for regressions**

Run:
```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; flutter test'
```
Expected: all tests pass (145 pre-existing + 2 new = 147).

- [ ] **Step 8: Commit**

```bash
git add lib/ui/game_screen.dart test/ui/partner_commander_test.dart
git commit -m "Add a Partner/Background field to the player settings sheet"
```

---

### Task 3: Full verification sequence

**Files:** none (verification only).

**Interfaces:** none.

- [ ] **Step 1: Run the complete DEV_NOTES verification sequence**

```bash
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache ghcr.io/cirruslabs/flutter:3.44.0 bash -c 'git config --global --add safe.directory /app; dart format --set-exit-if-changed lib test tool integration_test && flutter analyze --no-fatal-infos && flutter test'
```
Expected: format 0 changed, analyze no issues, all 147 tests pass.

The headless Linux integration test has proven unreliable in this sandbox in prior sessions — the format/analyze/full-suite run above plus GitHub Actions CI on push are the reliable checks.

- [ ] **Step 2: If anything fails, fix and re-run from Step 1**

Do not proceed until every check in Step 1 passes clean.
