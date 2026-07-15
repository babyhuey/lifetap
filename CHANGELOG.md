# Changelog

All notable changes to LifeTap are documented here.

## [1.1.0] - 2026-07-15

### Added

- **Starting player picker** — hold a finger down in every player zone for 1.5s to randomly pick who goes first, from a toolbar button. Re-triggerable any time, not just at game start.
- **Auto-restore** — the app now persists the current game's event history, so killing and relaunching resumes exactly where you left off instead of always starting a fresh game.
- **Optional turn timer** (off by default) — a toolbar "End Turn" button cycles whose turn it is through the seating order, with a seat-rotated countdown badge on the active player's zone. A soft reminder only: reaching zero never forces anything.
- **Partner/background commander** — record a second commander's name in a player's settings, with the same Scryfall art resolution the primary commander field already has. Recorded as data (visible in the settings sheet); this pass does not add separate per-commander damage tracking or a main-screen display for it.
- **Haptic feedback** (on by default) and **optional sound effects** (off by default) on life-adjust and commander-damage taps, with a stronger cue on a knock-out.
- **Game Over summary** — a one-time dialog announcing the winner and every player's final life total once exactly one player remains un-knocked-out.

## [1.0.0] - 2026-07-13

Initial release: multi-touch life counter (2–6 players), commander damage, poison/energy/experience counters, Monarch/Initiative/Day-Night, dice and coin flip, seat-rotated in-app keyboard, life-change history with undo, and Scryfall commander art with offline caching.
