# Toolbar cleanup: 3-button bar + overflow menu, tap-target fixes

Date: 2026-07-20
Status: approved

## Problem

The middle toolbar holds up to 9 identical evenly-spaced white icons (new
game, player-count badge, undo, dice, coin flip, day/night, history,
pick-starting-player, end turn). The user reports all four failure modes:
frequent actions are buried, icons all look alike, there are too many, and
some icons don't communicate their meaning.

Clarified usage: mid-game staples are undo, dice/coin, and the per-player
poison/rad counters (which live in each zone's counters popup, not on the
bar). Everything else is once-per-game or rarer.

A measured tap-target audit (44pt Apple minimum) found: toolbar buttons lay
out at 40x40 (48 effective on touch platforms, but 24px glyphs feel small);
the player name pill is 35px tall; the counters popup tabs are 32px tall;
the zone gear/counters buttons have 48px targets but only 20px glyphs.

## Design

### Bar: 3 buttons (+1 conditional)

Undo, Dice, and a "More" (⋯) menu button, evenly spaced, each with a ~28px
glyph in a >=48px layout box. When (and only when) the turn timer setting is
on, End turn appears as a fourth button (key `end-turn-icon` preserved) — a
per-turn action earns bar space, but only in games that use it.

The coin-flip button is deleted outright: the dice popup already contains a
Coin tile (`die-coin`), so the control was redundant.

### Overflow menu

The ⋯ button (key `toolbar-menu`) opens a dark popup menu anchored at the
button (not a bottom sheet — the bar is mid-screen on a table, so an edge
sheet reads wrong from half the seats). Entries have icon + text label:

- "New game…" with the current player count — the old refresh button and
  player-count badge both opened the settings screen, so they collapse into
  this one entry.
- "Pick starting player" (key `ritual-icon` moves onto this entry).
- "History".
- "Day/Night: Off|Day|Night" showing current state; selecting cycles it.

End turn is NOT in the menu (it is the conditional bar button). Entries are
disabled while the starting-player ritual is active, same as the buttons they
replace. Menu items fire the same settings-gated haptic as other controls.

### Tap-target fixes from the audit

- Player name pill: visual look unchanged; transparent hit padding brings the
  tappable height from 35px to >=44px (outer top padding reduced to keep the
  same visual position).
- Counters popup Player/Counters tabs: vertical padding doubled, 32px ->
  ~44px tall.
- Zone gear and counters glyphs: 20px -> 28px (48px targets already fine;
  this fixes findability).

## Testing

- New toolbar test: bar renders exactly Undo/Dice/More (no new-game, badge,
  coin, day/night, history, ritual buttons); End turn present only with the
  turn timer enabled; menu opens with the four labeled entries; New game
  routes to settings, History opens the history sheet, Day/Night cycles
  state.
- Size guards: bar buttons >=44px layout boxes; name pill hit area >=44px
  tall; popup tabs >=44px tall.
- Updated: ritual tests open the menu before tapping `ritual-icon`;
  turn-timer tests unchanged (they enable the timer first).
