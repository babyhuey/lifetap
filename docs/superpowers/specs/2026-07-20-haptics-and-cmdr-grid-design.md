# Haptic feedback + larger commander-damage grid

Date: 2026-07-20
Status: approved

## Goal

Two UX improvements requested after iPad play-testing:

1. Haptic feedback when hitting game controls.
2. Bigger commander-damage squares — at 40px they are hard to hit.

A third request — perceived lag on life taps — was investigated and declined by
design: a tap only registers on finger-lift because the router must
disambiguate taps from swipes (±10) and holds (auto-repeat). Firing on
touch-down was offered and the user chose to keep on-release semantics.

## Design

### Haptics

Discovered during implementation: haptics already exist for life taps and
commander-damage cells (`_playFeedback`, `selectionClick`/`mediumImpact`),
gated by the existing "Haptic feedback" settings toggle. The user never felt
them because no iPad has a vibration motor.

The actual gap is the discrete controls, filled with the same pattern
(settings-gated `selectionClick`, failure-swallowing, via a shared
`_controlHaptic` helper):

- `_Toolbar` — every icon button and the player-count badge, wrapped at the
  construction site so null (disabled) callbacks stay null.
- `_CountersPopupState._bump` — the counters popup's +/- adjusters.

On hardware without a vibration motor (all iPads, and the web PWA under
Safari) the call is a silent no-op; it works on the Android sideload build and
on iPhones.

### Commander-damage grid

- `_cmdrCellSize` 40 → 56 (above Apple's 44px minimum touch target); the
  inter-cell gap stays 4.
- In-cell damage number 16pt → 20pt, "me" label 12pt → 14pt, so the larger
  cell doesn't look sparse.
- Long-press-to-decrement and all keys/behavior unchanged.

## Testing

- Widget test mocks `SystemChannels.platform` and asserts a
  `HapticFeedback.vibrate` call fires for a life tap and for a
  commander-damage cell tap.
- Widget test asserts a commander-damage cell renders at 56x56.
- Full suite guards against layout overflow in the 5/6-player layouts.
