# LifeTap 2

> Working name — see the note in `docs/superpowers/specs/` about renaming before any wider distribution; `LifeTap` is the reference app's trademark.

A Flutter rebuild of the LifeTap MTG-style life counter, with first-class multi-touch: two or more players can tap their own zones at the same instant and every touch registers independently.

## Features

- 2–6 players with adaptive, seat-facing zone layouts; tap to +/− life; starting-life presets 20/25/30/40/60.
- Commander damage per opponent (auto-applies life loss, toggleable), plus poison / energy / experience counters and a generic named-counter tray (Treasure, Storm, Rad, …).
- Monarch / Initiative / Day-Night table-wide statuses.
- A second commander (Partner/Background) can be recorded per player, with the same Scryfall art resolution as the primary commander.
- Event-sourced game log → life-change history and undo fall out of the same mechanism.
- **Auto-restore** — the app persists the current game's event history, so it resumes exactly where you left off after being closed and reopened.
- Dice, coin flip, keep-screen-awake, per-player names and colors, seat-rotated in-app keyboard for renaming on side seats.
- A toolbar button holds a finger down in every zone for 1.5s to randomly pick who goes first — usable any time, not just at game start.
- An optional per-turn countdown timer (off by default): an End Turn button cycles whose turn it is through the seats, with a seat-rotated badge — a soft reminder, never enforced.
- Optional haptic feedback (on by default) and sound effects (off by default) on taps; a one-time Game Over summary once one player remains.
- **Multi-touch:** simultaneous independent taps across zones; a stationary hold auto-repeats ±1 at an accelerating rate; a horizontal swipe is a single ±10 — the only amounts are ever ±1 and ±10.

## Architecture

Three layers, dependencies pointing downward only:

- `lib/game/` — pure-Dart domain: `GameState`, `PlayerState`, sealed `GameEvent`s (each with JSON round-trip for persistence), and a Riverpod `Notifier` holding state + history.
- `lib/touch/` — pure-Dart pointer state machine (`PointerRouter`, `RitualDetector`, first-player picker). Built on raw pointer events rather than `GestureDetector` so simultaneous cross-zone gestures don't fight Flutter's gesture arena. No widget dependencies — fully unit-tested with synthetic pointer streams.
- `lib/data/` — persistence and external lookups: `SharedPreferences`-backed game-session save/restore, and Scryfall commander-art resolution with offline disk caching.
- `lib/ui/` — the widgets: a `Listener`-based zone grid, toolbar, and sheets wired to the providers.

See `docs/superpowers/specs/` for design docs (one per feature) and `docs/superpowers/plans/` for the implementation plans they were built from.

## Development

Flutter is not required on the host — everything runs in the pinned CI container, so local runs match CI exactly:

```sh
IMG=ghcr.io/cirruslabs/flutter:3.44.0
docker run --rm -v "$PWD":/app -w /app -e PUB_CACHE=/app/.pub-cache "$IMG" \
  bash -c 'git config --global --add safe.directory /app && flutter pub get && flutter test'
# container writes as root; chown back afterward:
docker run --rm -v "$PWD":/app -w /app "$IMG" chown -R "$(id -u)":"$(id -g)" /app
```

## CI

GitHub Actions runs everything in the same pinned Flutter container (`.github/workflows/`):

- **`ci.yml`** — `test` job: `dart format --set-exit-if-changed` + `flutter analyze` + `flutter test --coverage` (lcov artifact). `integration` job: `flutter test integration_test -d linux` under `xvfb`, booting the real app and injecting pointer events (no emulator / KVM needed).
- **`deploy.yml`** — builds `flutter build web` and publishes to GitHub Pages (`https://babyhuey.github.io/lifetap/`) on every push to `main`, so the app is installable on an iPad as a PWA.
- **`release.yml`** — builds a debug-signed Android APK and an unsigned iOS IPA on every push to `main`, publishing them to the rolling `latest` pre-release for sideloading. Tagged releases (e.g. `v1.1.0`) are cut manually from a chosen commit with the same build artifacts attached.

`tool/junit_report.dart` converts `flutter test --machine` output to JUnit XML for any CI that consumes it.
