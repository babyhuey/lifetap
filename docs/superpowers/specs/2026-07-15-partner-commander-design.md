# Partner/Background Commander — Design Spec (2026-07-15)

Lets a player record a second commander (a Partner or Background, per the real Commander/EDH mechanics that let some decks legally run two commanders) alongside their primary one. Approved for autonomous design as part of a batch; the scope decision below is the most significant judgment call in this batch and is flagged prominently for review.

## Goals

1. A player can set a second commander's name in their settings sheet, with the same Scryfall art resolution the primary commander field already has.
2. Both commanders' names/art persist through undo/history/auto-restore exactly like every other piece of player state, by virtue of going through the same event-sourced `GameEvent` pipeline.

## The scope decision (read this first)

Real Commander rules track commander damage **per commander source, not per opponent**: 21+ damage from *either* an opponent's primary or their partner is independently lethal — it is not one combined 21-damage pool per opponent. Implementing that precisely would mean restructuring `commanderDamage` (currently `Map<int, int>` keyed by opponent id) into something keyed by *which specific commander*, and reshaping the commander-damage egocentric mini-map (`lib/ui/game_screen.dart`'s `_commanderDamageGrid`) so an opponent with a partner shows two separately-tappable damage counters instead of one. That grid is already one of the most carefully-engineered pieces of UI in this app (egocentric seat-relative ordering, `Wrap` overflow handling, KO-at-21 flagging, tap/long-press semantics) and doubling its addressable cells for any player who sets a partner is a substantially larger change than the other four features in this batch combined.

**Decision: this pass adds partner commander as recorded name/art only — it does not change commander-damage tracking or the grid.** Damage stays exactly as it is today (one counter per opponent, unchanged code, unchanged tests). This delivers real, working value (recording your deck's actual commanders, with real art) without the disproportionate scope of a full damage-model rework. Separate per-commander damage tracking is a natural, larger follow-up if wanted later — flagged for the final summary, not attempted here.

**Corollary — no main-screen zone display.** The existing badge stack near a zone's name pill (name pill, Monarch/Initiative badges, the turn-timer countdown from this same batch) is already three layers deep in a tight vertical band. Adding a fourth (a partner-name indicator) risks visual crowding, especially on the smaller zones in 5-/6-player layouts. Since the partner commander doesn't drive any gameplay mechanic in this scope (no damage tracking, no lethality check), there's no functional need for constant on-zone visibility — it's recorded data, viewable/editable from the settings sheet where it's set (which already shows the primary commander together with it, so seeing both there is natural). No existing widget or layout changes on the main game screen.

## Architecture

**Data (`game/`, pure).** `PlayerState` (`lib/game/game_state.dart`) gains `partnerCommanderName`/`partnerArtUrl` (both `String?`, both defaulting `null`), added to `copyWith` using the same `_unset` sentinel pattern the existing `commanderName`/`artUrl` pair already uses (needed for the same reason: distinguishing "leave unchanged" from "explicitly clear"). A new `SetPartnerCommander` event (`lib/game/game_events.dart`) mirrors `SetCommander` exactly — same shape (`playerId`, `commanderName`, `artUrl`), same `apply`/`describe`, and (since this batch's auto-restore feature already added JSON round-tripping to every event) a `toJson()` following the identical pattern plus a new case in `eventFromJson`.

**UI (`_PlayerSettingsSheet`, `lib/ui/game_screen.dart`).** A second `TextEditingController` (`_partnerController`) and a second async submit handler (`_submitPartnerCommander`) that mirror `_commanderController`/`_submitCommander` exactly: same Scryfall art resolution via `commanderArtSourceProvider`, same "keep existing art on a failed lookup" behavior, same stale-request guard pattern (a `_partnerSubmitId` counter, independent of `_commanderSubmitId` since the two fields resolve independently), same in-app-keyboard/native-field dual path, same resolving-spinner treatment (a separate `_resolvingPartner` bool — the two fields must show independent spinners, since submitting one shouldn't spin the other). A new "Partner / Background" field renders directly below the existing Commander field in the settings sheet.

## Testing

- `PlayerState.copyWith`: partner fields round-trip independently of the primary pair (setting one doesn't disturb the other), matching the existing `commanderName`/`artUrl` coverage style.
- `SetPartnerCommander`: `apply`/`describe` tests mirroring `SetCommander`'s existing tests.
- JSON round-trip: add `SetPartnerCommander` to the existing table-driven round-trip test alongside the other 10 event types (making it 11).
- Widget test on `_PlayerSettingsSheet`: submitting a partner name resolves art and dispatches `SetPartnerCommander`, independently of the primary commander field (setting a partner doesn't touch the primary, and vice versa); a failed partner lookup keeps existing partner art without touching the primary commander's art.
