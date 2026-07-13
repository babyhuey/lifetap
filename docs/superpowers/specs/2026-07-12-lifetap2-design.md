# LifeTap 2 — Design Spec (2026-07-12)

Rebuild of the LifeTap MTG-style life counter as a Flutter app, feature-parity with the original plus first-class multi-touch. Approved in discussion 2026-07-12.

## Goals

1. Everything the original LifeTap does (baseline below), no regressions.
2. Headline improvement: true multi-touch — simultaneous, independent touch handling per player zone.
3. Real automated testing, run in Docker containers in CI.

## Baseline feature parity

- 2-player face-to-face split screen; tap to +/- life; starting-life presets 20/25/30/40/60; reset game.
- New games default to **4 players at 40 life** (2/3/5/6 also selectable in the new-game dialog; the starting-life set stays 20/25/30/40/60).
- 3–6 players with adaptive zone layout (zones rotated to face each seat).
- Commander damage per opponent (auto-applies life loss), poison/energy/experience counters.
- Utilities: dice roll, coin flip, first-player picker, life-change history + undo, keep-screen-awake, per-player colors/names.

## Multi-touch features (the improvement)

| Feature | Behavior |
|---|---|
| Simultaneous taps | Touches in different zones are fully independent — two+ players tapping at the same instant all register; nothing queued or dropped |
| Multi-finger increments | Within a zone: 1-finger tap ±1, 2-finger tap ±5, 3-finger tap ±10. Sign is resolved in the zone's **own upright frame**: the down-point is rotated by −q·90° (q = the seat's quarter-turns) about the zone center, then **left-of-the-seated-player − , right +**. So every player's own-left is − and own-right is + regardless of how their seat faces (an upside-down top seat's screen-left is that player's right). The `PointerRouter` carries a `zoneTurns` list parallel to `zones`; hold-repeat uses the same per-seat sign |
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

**Player zone** — either full-bleed commander art with a dark scrim, or (default, no art) a **near-black** `#0D0D0D` fill that uses the player's color only as an accent; everything seat-rotated via `seatQuarterTurns`:
- Empty (no-art) zones render near-black with the player's color as a **3px border accent** and a **name pill tinted with the player's color** (color at ~30% over translucent black); the big life number stays white. A fresh 4-player game therefore reads dark with subtle per-player accents rather than four colored blocks. When art is present the zone keeps the neutral divider hairline and the art + scrim path is unchanged.
- A huge white life number, `w800`, sized ≈ shortest-zone-side × 0.42 via `LayoutBuilder` + `FittedBox` so it never overflows, with a soft black shadow for legibility over art.
- A rounded name pill (radius 18) near the top-inner edge, tinted with the player's color; tapping it still opens the **upright** rename dialog (unchanged) and sits above the pointer `Listener` so it never counts as a life tap.
- Faint decorative `−`/`+` glyphs on the seated player's own left/right edges — rendered **inside the seat's `RotatedBox`** so they rotate with the seat and always match the router's per-seat sign — added as non-hittable decoration so taps fall through to the life router.
- A compact cluster of small rounded chips (radius 8) for the player's **non-zero** secondary counters (poison drop, energy bolt, experience), just above the commander-damage strip.
- A **commander-damage strip** pinned to the player-facing bottom edge (seat-rotated with the zone), above the `Listener`: a shield header plus one chip per **opponent** showing that opponent's color dot and the damage this player has taken from them (default 0). Tapping a chip = **+1** commander damage from that opponent (dispatches `AdjustCommanderDamage` with `reduceLife` set from the "Commander damage life loss" setting); long-press = **−1**, clamped at 0 (disabled at 0). A chip at **21+** — lethal — flags red, and with life-loss on the Auto-KO strikethrough then applies. Each chip carries `HitTestBehavior.opaque` so only its own hit area is consumed; the rest of the cell still taps life.
- The gear icon remains in a top corner (above the `Listener`) as the second path to the per-player settings sheet; the knocked-out visual (strikethrough) is gated by the Auto-KO setting.

**Toolbar** — a slim black strip (~64px) of evenly spaced white icon buttons: reset (opens Settings), a cyan-ringed player-count badge (also opens Settings), undo, d20 dice, coin flip, and history. For 2/4/6 players it sits **between the rows** (top row / strip / bottom row) — pairing with the top+bottom seating — while 3 and 5, which have no clean middle split, keep it at the bottom. The player-zone rects are computed to exclude the strip, so the top zones fill the area above it and the bottom zones below, and a toolbar touch is outside every zone (never a stray life tap).

**Settings / new-game screen** (`lib/ui/settings_screen.dart`, public `SettingsScreen`) — a black scaffold titled "Settings": a "Game Setup" header over a hairline; a single-select "Players" row (2/3/4/5/6) and "Starting life" row (20/25/30/40/60) rendered as ~44px circular chips (unselected `#2A2A2A`, selected = cyan 2px ring + cyan number); a cyan "Start game" button that dispatches `NewGame(count, life)`; and a "Gameplay" section with cyan toggle rows for "Commander damage life loss" and "Auto-KO". These two flags live in a lightweight `settingsProvider` (`GameSettings`) kept out of the event-sourced session; Auto-KO gates the zone's knocked-out visual. The "Commander damage life loss" toggle now drives `AdjustCommanderDamage.reduceLife` (an optional field, default `true`): the per-opponent commander-damage chips read the flag at dispatch, so with it **on** commander damage also subtracts life (the standard rule) and with it **off** only the per-opponent counter changes.

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
