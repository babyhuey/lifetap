# Seeded empty-zone texture (grain + color wash)

Date: 2026-07-20
Status: approved (style chosen from browser mockups: "B — fine grain + color wash")

## Problem

Zones with no commander art render flat near-black (`LifeTapColors.emptyZone`)
with only a 3px player-color border. Boring, but any replacement must not
distract from the life number.

## Design

When `player.artUrl == null`, the zone background becomes two static layers
under the existing content (life number, hints, KO overlay all unchanged):

1. **Color wash** — a radial gradient of the seat's color anchored at the
   midpoint of one zone edge (left/top/right/bottom), alpha ~0.20 fading to
   transparent by ~65% radius. High-luminance colors (yellow) drop to ~0.16
   so they don't glow. The wash uses the player's current color, so recolors
   restyle it immediately.
2. **Film grain** — a fine static white-noise texture over the whole zone at
   ~7% effective opacity. Generated locally (no assets fetched, no new
   dependencies, no network); painted once and cached — zero per-frame cost,
   nothing animates.

**Seeding:** a game-level `seed` (random int) is created by NewGame, stored in
GameState, and round-trips through event JSON persistence (legacy persisted
games default to seed 0). Each seat derives its wash edge (and grain phase)
from `(gameSeed, playerId)` via a small pure function in
`lib/ui/zone_texture.dart` — new game, new arrangement; same game after
restore, same arrangement.

Zones with art are untouched. The empty-zone border, KO dimming, and scrim
behavior are unchanged. Everything stays dark (Safari dark-mode-extension
constraint).

## Testing

- Pure unit tests: edge derivation is deterministic for (seed, player) and
  varies across seeds; legacy seed-0 path works.
- Widget tests: empty zone renders the texture layer (key
  `zone-texture-<id>`); setting commander art removes it; recolor changes the
  wash color.
- Event JSON round-trip test updated for the NewGame seed field.
- Full suite green.
