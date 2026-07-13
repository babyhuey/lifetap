# LifeTap 2 — Design Spec (2026-07-12)

Rebuild of the LifeTap MTG-style life counter as a Flutter app, feature-parity with the original plus first-class multi-touch. Approved in discussion 2026-07-12.

## Goals

1. Everything the original LifeTap does (baseline below), no regressions.
2. Headline improvement: true multi-touch — simultaneous, independent touch handling per player zone.
3. Real automated testing, run in Docker containers in CI.

## Baseline feature parity

- 2-player face-to-face split screen; tap to +/- life; starting-life presets 20/25/30/40/60; reset game.
- New games default to **4 players at 20 life** (2/3/5/6 also selectable in the new-game dialog).
- 3–6 players with adaptive zone layout (zones rotated to face each seat).
- Commander damage per opponent (auto-applies life loss), poison/energy/experience counters.
- Utilities: dice roll, coin flip, first-player picker, life-change history + undo, keep-screen-awake, per-player colors/names.

## Multi-touch features (the improvement)

| Feature | Behavior |
|---|---|
| Simultaneous taps | Touches in different zones are fully independent — two+ players tapping at the same instant all register; nothing queued or dropped |
| Multi-finger increments | Within a zone: 1-finger tap ±1, 2-finger tap ±5, 3-finger tap ±10. Sign is by horizontal position in the zone rect: **left half − , right half +** (was top/bottom). Sign is by *physical* left/right; per-seat rotation is a separate planned fix |
| Per-finger drag | Vertical drag in a zone scrubs the life value. A stationary hold (movement under the scrub slop) auto-repeats after ~300ms and **accelerates** — step 1→2→5→10 while the interval shrinks ~300ms→60ms, reaching ±10-per-step in ~1.6s. A hold that repeated does not also emit a tap on release. Stationary-hold wins over scrub |
| Hold-together ritual | ≥1 finger held in **every** active zone for 1.5s (with progress ring) = start/reset game — replaces a reset button and prevents accidents |
| Multi-touch first-player picker | Everyone touches and holds anywhere; after the hold window a random finger wins — replaces the menu-based picker |

## Architecture

**Decision: raw `Listener` pointer events + custom per-zone pointer state machine, NOT `GestureDetector`.** Flutter's gesture arena globally disambiguates competing gestures, which serializes cross-zone gestures — exactly the failure this rebuild removes. Rejected alternatives: per-zone GestureDetectors (arena conflicts), Flame engine (overkill).

Three layers, dependencies point downward only:

```
ui/      Flutter widgets: zone grid, overlays, sheets, theming
touch/   pure Dart pointer state machine (no Flutter widget deps beyond event types)
game/    pure Dart domain: state, events, reducers
```

- `game/`: `GameState` (players: life, commanderDamage map, poison/energy/experience, name, color; settings: playerCount 2–6, startingLife 20/25/30/40/60). **Event-sourced**: every mutation is a `GameEvent` appended to history → undo and the history view are projections. State managed with Riverpod.
- `touch/`: `PointerRouter` claims each pointer for the zone it lands in; per-zone state machine classifies concurrent-pointer count → tap magnitude, drag → scrub, hold → repeat; a global recognizer watches for the hold-together ritual and the first-player picker. Pure Dart: unit-testable with synthesized pointer streams, no emulator needed.
- `ui/`: zone layouts for 2 (mirrored halves), 3 (1+2), 4 (quadrants), 5–6 (grid); horizontal swipe switches a zone's counter mode (life ⇄ poison/energy/exp); commander-damage overlay per player; dice/coin; history sheet with undo; wakelock; color/name editor. Each zone shows an editable player-name label pinned to its top edge, rotated to the seat's facing so it reads right-side-up; the label sits above the pointer `Listener` so its own hit area is consumed (tapping it opens the editor, not a life change) while the rest of the zone still taps life. Tapping it opens an **upright, screen-centered** rename dialog (quarterTurns 0 — deliberately not seat-rotated) with an autofocused, prefilled `TextField` that dispatches `RenamePlayer` on confirm; focusing the field never reorients the landscape-locked screen. The gear settings sheet remains a second path to the same rename.

## Visual design (2026-07-12 reskin)

An independent black + cyan reskin following a common MTG life-counter layout. It restyles `ui/` and the theme only; the pure `game/` and `touch/` layers and their behavior are untouched. All iconography is our own (Material icons / painted shapes); backgrounds still come from the existing Scryfall-art-by-card-name mechanism — no third-party art or icon assets are embedded.

**Design tokens** (`lib/ui/theme.dart`, `LifeTapColors`): pure-black `#000000` background; cyan accent `#33C7F0` for selected states, toggles-on, the player-count badge ring, and active chips; surfaces/sheets `#141414`, chips `#1E1E1E`, unselected chip `#2A2A2A`, hairline dividers `#2C2C2C`; white primary / `#9E9E9E` secondary text; positive delta green `#47C266`, negative red `#E5533C`, poison purple `#9B6DE8`. `buildLifeTapTheme()` is a dark Material 3 theme with the black scaffold and cyan `colorScheme.primary`. Landscape orientation stays locked in `main.dart`.

**Player zone** — full-bleed commander art with a dark scrim, everything seat-rotated via `seatQuarterTurns`:
- A huge white life number, `w800`, sized ≈ shortest-zone-side × 0.42 via `LayoutBuilder` + `FittedBox` so it never overflows, with a soft black shadow for legibility over art.
- A rounded translucent-black name pill (radius 18) near the top-inner edge; tapping it still opens the **upright** rename dialog (unchanged) and sits above the pointer `Listener` so it never counts as a life tap.
- Faint decorative `−`/`+` glyphs on the physical left/right edges of the zone (matching the router's physical left = −, right = + sign), added as non-hittable decoration so taps fall through to the life router.
- A compact outer-edge cluster of small rounded chips (radius 8) for the player's **non-zero** secondary counters (poison drop, energy bolt, experience) and commander-damage (shield) entries.
- The gear icon remains in a top corner (above the `Listener`) as the second path to the per-player settings sheet; the knocked-out visual (strikethrough) is gated by the Auto-KO setting.

**Toolbar** — a slim black bottom bar of evenly spaced white icon buttons: reset (opens Settings), a cyan-ringed player-count badge (also opens Settings), undo, d20 dice, coin flip, and history.

**Settings / new-game screen** (`lib/ui/settings_screen.dart`, public `SettingsScreen`) — a black scaffold titled "Settings": a "Game Setup" header over a hairline; a single-select "Players" row (2/3/4/5/6) and "Starting life" row (20/25/30/40/60) rendered as ~44px circular chips (unselected `#2A2A2A`, selected = cyan 2px ring + cyan number); a cyan "Start game" button that dispatches `NewGame(count, life)`; and a "Gameplay" section with cyan toggle rows for "Commander damage life loss" and "Auto-KO". These two flags live in a lightweight `settingsProvider` (`GameSettings`) kept out of the event-sourced session; Auto-KO gates the zone's knocked-out visual. Commander damage has no in-app adjust UI, so its toggle is a stored flag with no dispatch site yet.

**History sheet** — color-coded and newest-first, projected from the event log: each life/counter change shows a dot in the player's color, the name, a counter icon (heart = life, drop = poison, bolt = energy, sparkle = experience, shield = commander damage), a rounded signed delta chip (green gain / red loss / accent counter), and "→ resulting value". An Undo button in the header updates the list live.

## Testing & CI (Docker)

All CI jobs run in containers on GitLab CI; the same containers work locally via `docker run` so dev == CI.

| Stage | Job | Container | What it does |
|---|---|---|---|
| lint | format + analyze | `ghcr.io/cirruslabs/flutter` | `dart format --set-exit-if-changed`, `flutter analyze` |
| test | unit + widget | `ghcr.io/cirruslabs/flutter` | `flutter test --coverage` — game reducers, pointer state machine (synthesized multi-pointer streams: simultaneous taps in 2 zones, 3-finger taps, ritual timing), widget tests per zone. Coverage artifact + JUnit report on the MR |
| integration | linux desktop | same image + `xvfb` | `flutter test integration_test -d linux` under xvfb — real end-to-end app boot and multi-pointer injection via `WidgetTester`. Runs on shared runners (no KVM/emulator needed) |

Android emulator testing is deliberately out of CI scope (shared runners lack KVM); integration tests run on the Linux desktop target instead, which exercises the same Dart/Flutter code paths including the pointer layer.

## Out of scope (v1)

Monarch/initiative markers, themes beyond player colors, cloud sync, iOS store release plumbing.

## Open items

- Remote hosting namespace (personal GitLab vs GitHub) — repo is local-only until decided.
- App icon / name polish.
