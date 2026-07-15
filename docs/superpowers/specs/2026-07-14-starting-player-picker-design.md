# Starting Player Picker — Design Spec (2026-07-14)

Wires up the existing-but-unused `RitualDetector`/`pickWinner` (`lib/touch/pointer_router.dart:298-361`) as a "hold fingers down to pick who goes first" feature, re-triggerable any time during a game, not just at game start. Approved in discussion 2026-07-14.

## Goals

1. A toolbar icon opens a full-screen ritual overlay; every zone must hold a finger simultaneously for the existing 1.5s hold window to pick a winner.
2. Each zone shows its own progress independently, not just a single shared value.
3. The winner is announced seat-rotated in their own zone, matching the app's existing per-seat conventions (name pill, KO mark, badges).
4. Holding fingers during the ritual never changes life totals — it's fully isolated from the normal tap/hold/swipe life-adjust path.
5. Fully unit/widget-testable, matching the existing `RitualDetector`/`pickWinner` test coverage style.

## Non-goals

- No persisted "whose turn" state — this is a one-shot announcement, not tracked in `GameState`.
- No change to `PointerRouter`'s existing tap/hold/swipe behavior.

## Context: why this needs new plumbing

`GameScreen` (`lib/ui/game_screen.dart`) is the app's single permanent screen — there is no separate pre-game screen. Its `Listener` is wired once in `initState` and every pointer event already means "adjust life" via `PointerRouter` → `_onResult`. There is no existing gap in that flow to slot a ritual into, so this feature needs its own explicit mode that intercepts pointer events instead of extending an existing flow.

## Architecture

**Trigger.** A new icon in the existing central toolbar (alongside the dice and day/night buttons), following the same `_ValueKey`/tap-opens-popup pattern as those. Tapping it sets a `_ritualActive` flag on `GameScreen`'s state and shows the overlay described below. Tapping the icon again, or the overlay's close (✕), clears the flag and dismisses it.

**Pointer routing while active.** `_onPointerDown`/`_onPointerMove`/`_onPointerUp` in `game_screen.dart` gain an early branch: when `_ritualActive`, the event is resolved to a zone and forwarded to a `RitualDetector` instance instead of `_router`, so it never reaches `_onResult`/`AdjustCounter`. Zone resolution needs a new small pure helper — `PointerRouter` currently only resolves position→zone internally as part of its stateful gesture machine; extract that lookup into a standalone function (e.g. `zoneAt(List<Rect> zones, Offset position)`) that both `PointerRouter` and the ritual path can call. This is a refactor-only change to `PointerRouter` — no behavior change to its existing tests.

**Per-zone progress.** `RitualDetector.progress` currently returns a single `double` — the minimum across all zones. Add `double progressForZone(int zone)` that returns just that zone's own clamped `bestHeld / limit` (the per-zone computation already exists inside the `progress` getter's loop body; this pulls it out to be independently callable). `progress` itself is re-expressed as the min over `progressForZone` for all zones, so existing behavior and existing tests are unchanged.

**Overlay UI.** A new `_RitualOverlay` widget, added as a layer in `GameScreen`'s existing overlay `Stack` (same layer the settings/counters popups use), rendering one panel per zone via `Positioned.fromRect` + `RotatedBox(quarterTurns: ...)`, matching the seat-rotation convention used everywhere else (name pill, KO mark, commander-damage map). Each panel shows a fill/pulse driven by that zone's `progressForZone` and a "Hold here" prompt. A `Timer.periodic` (matching the existing 60ms tick already used for hold-repeat) drives repaint by calling `RitualDetector.poll()` each tick.

**Completion & winner announcement.** When `poll()` reports done, `pickWinner(heldPointerIds, seed)` — with `seed` from `Random().nextInt(...)` at call time, not a fixed value — picks a pointer; its zone maps to a player via the same `_router`-adjacent zone lookup. That player's panel switches to a "You go first!" banner (seat-rotated, same treatment as the other panels) for ~2.5s or until tapped, then the overlay auto-dismisses and `_ritualActive` clears.

**Cancellation.** A zone's finger lifting before every zone has qualified already resets that zone's progress to 0 via `RitualDetector.up()` — inherent, no new logic. The close (✕) exits ritual mode outright at any point, clearing `_ritualActive` and discarding the `RitualDetector` instance (a fresh one is created next time the icon is tapped, sized to the current player count).

**Interaction with other overlays.** The ritual icon is hidden/disabled while the settings or counters popup is open, and vice versa — only one full-screen overlay at a time, matching how those two already behave toward each other.

## Testing

- Unit tests for `RitualDetector.progressForZone` (new) alongside the existing `progress`/`poll` tests in `test/touch/pointer_router_test.dart`.
- Unit test for the extracted `zoneAt` helper.
- A widget test in `test/ui/` driving simulated multi-pointer holds across zones through `GameScreen`'s ritual overlay to a winner announcement, verifying: (a) life totals are unchanged by the held pointers, (b) the announcement appears in the correct (winning) zone, (c) the overlay auto-dismisses after announcement.
- A widget test for cancellation: one zone's finger lifts before completion → no announcement, progress resets.
