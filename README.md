# LifeTap 2

A Flutter rebuild of the LifeTap MTG-style life counter, with first-class multi-touch: two or more players can tap their own zones at the same instant and every touch registers independently.

## Features

- 2–6 players with adaptive, seat-facing zone layouts; tap to +/− life; starting-life presets 20/30/40.
- Commander damage per opponent (auto-applies life loss), plus poison / energy / experience counters.
- Event-sourced game log → life-change history and undo fall out of the same mechanism.
- Dice, coin flip, keep-screen-awake, per-player names and colors.
- **Multi-touch:** simultaneous independent taps across zones; multi-finger increments (1/2/3 fingers = ±1/±5/±10); vertical drag to scrub life; a hold-together ritual and a random first-player picker.

## Architecture

Three layers, dependencies pointing downward only:

- `lib/game/` — pure-Dart domain: `GameState`, `PlayerState`, sealed `GameEvent`s, and a Riverpod `Notifier` holding state + history.
- `lib/touch/` — pure-Dart pointer state machine (`PointerRouter`, `RitualDetector`, first-player picker). Built on raw pointer events rather than `GestureDetector` so simultaneous cross-zone gestures don't fight Flutter's gesture arena. No widget dependencies — fully unit-tested with synthetic pointer streams.
- `lib/ui/` — the widgets: a `Listener`-based zone grid, toolbar, and sheets wired to the providers.

See `docs/superpowers/specs/2026-07-12-lifetap2-design.md` for the full design.

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

`.gitlab-ci.yml` runs three stages in the same container:

1. **lint** — `dart format --set-exit-if-changed` + `flutter analyze`.
2. **test** — `flutter test --coverage`; results converted to a JUnit report (`tool/junit_report.dart`) shown on the MR, plus an lcov coverage artifact.
3. **integration** — `flutter test integration_test -d linux` under `xvfb`, booting the real app and injecting pointer events (no emulator / KVM needed).
