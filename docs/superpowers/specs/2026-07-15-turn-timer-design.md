# Optional Turn Timer — Design Spec (2026-07-15)

A soft, opt-in per-turn countdown: a toolbar "End Turn" control cycles whose turn it is through the seating order, with a seat-rotated countdown badge on the active player's zone. Reverses a preference noted in `DEV_NOTES.md` ("User explicitly does NOT want: ... turn timer") — the user has now explicitly asked for it as part of this batch; approved for autonomous design.

## Goals

1. A "Turn timer" toggle in Settings (default **off**, respecting that this was previously declined — it's opt-in, not a behavior change for players who don't want it) and a turn-length preset selector (30/60/90/120s, default 60s), matching the existing chip-row pattern.
2. When on, a toolbar "End Turn" button advances whose turn it is through the players in seating order (wrapping around), restarting the countdown.
3. The active player's zone shows a small seat-rotated badge with the remaining seconds, turning to a warning color once time runs out.
4. **Soft reminder, not enforcement**: hitting zero never forces anything (no auto-advance, no blocked input) — it's a visual cue only, matching how a table would actually use it (forcibly ending a Commander turn on a timer would interrupt real gameplay).

## Scope decisions (autonomous, noted for review)

- **Turn state is ephemeral UI state, not part of `GameState`/`GameEvent`.** Persisting it would mean threading a new field through the event-sourced model and the auto-restore JSON serialization for a feature whose whole value is a live, in-the-room pacing cue — not something meaningful to resume after an app restart. This mirrors how the ritual-picker's state was kept UI-local rather than event-sourced.
- **Turn order is `GameState.players` list order** — the same order that already drives zone layout and seating (`seatQuarterTurns`), so it needs no new concept.

## Architecture

**Settings.** `GameSettings` gains `turnTimerEnabled` (bool, default `false`) and `turnTimerSeconds` (int, default `60`), following the existing field/`copyWith`/setter trio. `SettingsScreen` gets a new "Turn timer" toggle plus a `_ChipRow` of `[30, 60, 90, 120]` for the length — always shown (not conditionally hidden behind the toggle), matching how the existing player-count/starting-life chips are always visible regardless of other state.

**Turn tracking (`_GameScreenState`).** Two new fields: `int? _activeTurnPlayerId` and `Duration? _turnDeadline`. Reuses the existing 60ms `_holdTimer` tick (already driving `_router.tick()` and `_ritualTick()`) to also call `_turnTimerTick()`, which:
- If the setting is off, clears `_activeTurnPlayerId` (so re-enabling starts fresh) and returns.
- If `_activeTurnPlayerId` is null (first activation, or just cleared), initializes it to `players.first.id` with a fresh deadline.
- Otherwise just repaints (`setState(() {})`) so the countdown badge updates.

A `ref.listenManual(gameProvider, ...)` (a third, independent listener alongside the existing persistence-save and game-over ones — each with one responsibility) resets `_activeTurnPlayerId = null` whenever `next.history.length <= 1` (a fresh `NewGame`), so a new game always restarts turn tracking from the first player rather than potentially reusing a stale id that happens to still exist in the new roster.

`_endTurn()` (called by the toolbar button, a no-op if the setting is off) advances to the next player in list order, wrapping, and resets the deadline.

**UI.** `_GameScreenState.build()` gains `final settings = ref.watch(settingsProvider);` (not currently watched there — only read one-off in handlers or watched locally inside `_PlayerZone`) so the toolbar button and badge react live to the setting toggling from the Settings screen. The toolbar gets a new "End Turn" (`Icons.skip_next`) button, disabled (`null` `onPressed`, matching the existing ritual-active/other-icon-disable convention) when the setting is off. A new `_TurnTimerBadge` widget — styled like the existing `_ZoneStatusBadge` (a translucent-black disc, accent-bordered) but showing the remaining whole seconds as text, switching to the negative/warning color (`LifeTapColors.negative`) once the deadline has passed — renders on the active player's zone only, seat-rotated, in the same badge layer as the existing Monarch/Initiative badges (a sibling condition, not merged into `_ZoneStatusBadges`, since this is ephemeral timer state, not a `GameState`-tracked status).

## Testing

- Settings: toggle + duration chips exist, default correctly, update `GameSettings`.
- A widget test enabling the timer and confirming: the badge appears on player 0 with the full duration; tapping "End Turn" moves the badge to player 1 and resets the displayed time; the badge disappears when the setting is toggled off; a fresh `NewGame` resets tracking back to player 0.
- A widget test using an injected fake clock (matching the ritual-picker's `GameScreen(clock: ...)` pattern, already available) to confirm the badge shows a warning color/state once the deadline passes, without anything else in the app being blocked or forced (life taps still work normally past zero).
