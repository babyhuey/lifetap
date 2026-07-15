# Polish Items — Design Spec (2026-07-15)

Three small, independent touch-feel and end-of-game improvements: haptic feedback, an optional sound toggle, and a lightweight game-over summary. Approved for autonomous design as part of a batch; decisions below are reasoned defaults, flagged for review at the end.

## Goals

1. Life-adjust taps (the core touch-zone tap/hold/swipe gesture) and commander-damage taps give light haptic feedback; a player being knocked out gives a stronger one. Toggleable, default **on**.
2. The same two trigger points can optionally also play a short system sound (click for a normal change, alert for a KO). Toggleable, default **off**, per the original ask.
3. When exactly one player remains un-knocked-out, a single centered dialog announces the winner and shows every player's final life total. Shown once per game.

## Scoped down from the original suggestion (noting the deliberate simplification)

- **No chronological death-order tracking.** The original phrasing mentioned "death order"; implementing that needs incremental previous/next player-state diffing on every state change to detect exactly when each player crosses into KO. For a "lightweight" polish item, a final life-totals list (current player order, KO'd players marked) delivers the same at-a-glance summary value without that bookkeeping. If real death order is wanted later, it's a separable follow-up.
- **Feedback is scoped to the two primary touch-zone gestures** (life-adjust tap/hold/swipe via `_onResult`, and commander-damage cell taps) — not the counters popup's poison/energy/experience/generic-counter taps, which are a separate, lower-frequency interaction surface. This matches the original framing ("a touch-first app," referring to the app's signature multi-touch gesture) rather than every tappable control.
- **KO feedback fires whenever the *affected* player's post-dispatch state is knocked-out**, not only on the exact alive→dead transition. Precisely detecting "just now" would need the same previous/next diffing avoided above. In practice a player is knocked out once and the table moves on, so the edge case (repeatedly tapping an already-dead player re-fires the KO feedback) is rare and low-cost for a polish feature.

## Architecture

**Settings.** `GameSettings` (`lib/ui/settings_screen.dart`) gains two fields, following the exact field/`copyWith`/setter trio every existing toggle (`autoKo`, `commanderDamageLifeLoss`, `inAppKeyboard`) already uses: `hapticFeedback` (default `true`), `soundEffects` (default `false`). Two new `SwitchListTile` rows in the existing "Gameplay" section.

**Trigger points, unified.** `_GameScreenState` (`lib/ui/game_screen.dart`) gains one small private helper, called from the two existing dispatch sites that change a player's life — `_onResult` (life-adjust tap/hold/swipe) and `_adjustCommanderDamage` (commander-damage cell tap) — right after the dispatch:
```dart
void _playFeedback(int playerId) {
  final settings = ref.read(settingsProvider);
  final knockedOut = _knockedOut(ref.read(gameProvider).current.player(playerId), settings);
  if (settings.hapticFeedback) {
    knockedOut ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
  }
  if (settings.soundEffects) {
    SystemSound.play(knockedOut ? SystemSoundType.alert : SystemSoundType.click);
  }
}
```
Reuses the existing `_knockedOut(player, settings)` helper (already gates on the Auto-KO setting), `HapticFeedback`/`SystemSound`/`SystemSoundType` from `package:flutter/services.dart` (already an implicit Flutter dependency — no new package). No new dependency, no bundled audio assets: `SystemSound.play` uses the platform's built-in click/alert sound, matching this app's existing "no third-party assets beyond Scryfall art" constraint.

**Game-over summary.** A `bool _gameOverShown` field on `_GameScreenState`, and one more `ref.listenManual(gameProvider, ...)` registered in `initState()` (alongside the existing persistence-save listener from the auto-restore feature — a separate listener, not merged into that one, so each has one clear responsibility):
```dart
ref.listenManual(gameProvider, (previous, next) {
  if (next.history.length <= 1) {
    _gameOverShown = false; // a fresh NewGame resets the flag
    return;
  }
  if (_gameOverShown) return;
  final settings = ref.read(settingsProvider);
  final alive = next.current.players.where((p) => !_knockedOut(p, settings)).toList();
  if (alive.length == 1) {
    _gameOverShown = true;
    _showGameOverSummary(next.current, alive.single);
  }
});
```
Reading `next.current.players` fresh each time (rather than diffing) is what makes this simple: if Auto-KO is off, `_knockedOut` always returns false, so `alive.length` never drops to 1 and the dialog never triggers — consistent with "Auto-KO off" already meaning "nothing is ever treated as eliminated" elsewhere in the app, no special-casing needed. The dialog itself (`_GameOverDialog`, a new small widget) is a generic centered `showDialog`, **not** seat-rotated — matching this app's existing convention that seat rotation is for per-player content (name, commander, counters) while table-wide events (dice, coin) use a plain centered dialog. Shows "`<winner>` wins!" and each player's final life value, with KO'd players marked.

## Testing

- `test/ui/settings_screen_test.dart` or a focused new test: the two new toggles exist, default correctly (`hapticFeedback` true, `soundEffects` false), and flipping them updates `GameSettings`.
- A widget test verifying `_playFeedback`'s condition logic indirectly is impractical (haptics/system sounds aren't observable in the test harness) — instead, test the **settings plumbing** is correct (the right `GameSettings` values are read at the point of the call) by structuring `_playFeedback` so it's simple enough that a code-review-level check suffices; no dedicated haptics/sound test is added; this is called out explicitly rather than silently skipped.
- `test/ui/` (new or existing file): a widget test that drives a 2-player game to exactly one player remaining (via direct `AdjustCounter` dispatches to drop one player to 0 life) and asserts the game-over dialog appears with the correct winner and life totals; a second test confirms starting a new game after a first game-over doesn't immediately reopen the dialog (the `_gameOverShown` reset); a third confirms the dialog does **not** appear when Auto-KO is off even at 0 life.
