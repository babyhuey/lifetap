# LifeTap 2 — Design Spec (2026-07-12)

Rebuild of the LifeTap MTG-style life counter as a Flutter app, feature-parity with the original plus first-class multi-touch. Approved in discussion 2026-07-12.

## Goals

1. Everything the original LifeTap does (baseline below), no regressions.
2. Headline improvement: true multi-touch — simultaneous, independent touch handling per player zone.
3. Real automated testing, run in Docker containers in CI.

## Baseline feature parity

- 2-player face-to-face split screen; tap to +/- life; starting-life presets 20/30/40; reset game.
- 3–6 players with adaptive zone layout (zones rotated to face each seat).
- Commander damage per opponent (auto-applies life loss), poison/energy/experience counters.
- Utilities: dice roll, coin flip, first-player picker, life-change history + undo, keep-screen-awake, per-player colors/names.

## Multi-touch features (the improvement)

| Feature | Behavior |
|---|---|
| Simultaneous taps | Touches in different zones are fully independent — two+ players tapping at the same instant all register; nothing queued or dropped |
| Multi-finger increments | Within a zone: 1-finger tap ±1, 2-finger tap ±5, 3-finger tap ±10 (top half +, bottom half −) |
| Per-finger drag | Vertical drag in a zone scrubs the life value; hold = auto-repeat increment |
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

- `game/`: `GameState` (players: life, commanderDamage map, poison/energy/experience, name, color; settings: playerCount 2–6, startingLife 20/30/40). **Event-sourced**: every mutation is a `GameEvent` appended to history → undo and the history view are projections. State managed with Riverpod.
- `touch/`: `PointerRouter` claims each pointer for the zone it lands in; per-zone state machine classifies concurrent-pointer count → tap magnitude, drag → scrub, hold → repeat; a global recognizer watches for the hold-together ritual and the first-player picker. Pure Dart: unit-testable with synthesized pointer streams, no emulator needed.
- `ui/`: zone layouts for 2 (mirrored halves), 3 (1+2), 4 (quadrants), 5–6 (grid); horizontal swipe switches a zone's counter mode (life ⇄ poison/energy/exp); commander-damage overlay per player; dice/coin; history sheet with undo; wakelock; color/name editor.

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
