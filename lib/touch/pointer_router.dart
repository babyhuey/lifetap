import 'dart:math';
import 'dart:ui';

/// Result emitted for a classified gesture. Zones are identified by integer id;
/// the caller maps zone -> player and result -> game event. This layer is
/// deliberately game-agnostic so it can be unit-tested with synthetic pointers.
sealed class PointerResult {
  const PointerResult(this.zoneId);

  final int zoneId;
}

/// A ±1 life change in [zoneId] from a tap or a hold-repeat. [magnitude] is
/// signed: −1 to the seated player's left, +1 to their right (resolved in the
/// zone's own upright frame, not the screen's). Every tap and every hold repeat
/// is exactly ±1 — the finger count and how long a finger is held never change
/// the amount, only how many ±1s arrive.
class TapResult extends PointerResult {
  const TapResult(super.zoneId, this.magnitude);

  final int magnitude;

  @override
  String toString() => 'TapResult(zone: $zoneId, magnitude: $magnitude)';
}

/// A ±10 life change in [zoneId] from a single horizontal swipe. [magnitude] is
/// signed on the same axis as a tap: −10 for a drag toward the seated player's
/// own left, +10 toward their own right (resolved in the zone's own upright
/// frame). Emitted exactly once per swipe gesture.
class SwipeResult extends PointerResult {
  const SwipeResult(super.zoneId, this.magnitude);

  final int magnitude;

  @override
  String toString() => 'SwipeResult(zone: $zoneId, magnitude: $magnitude)';
}

class _ActivePointer {
  _ActivePointer({
    required this.zone,
    required this.downPos,
    required this.hold,
  }) : lastPos = downPos;

  final int zone;
  final Offset downPos;
  Offset lastPos;

  /// True once the finger has travelled beyond the slop: it is a drag, not a
  /// stationary hold, so it must neither auto-repeat nor read as a tap on
  /// release.
  bool moved = false;

  /// True once this pointer has emitted at least one hold repeat, so its up
  /// suppresses the one-shot tap (no double count).
  bool repeated = false;

  /// True once this pointer has been recognized as a horizontal swipe and
  /// emitted its ±10, so it never also taps or hold-repeats.
  bool swiped = false;

  final HoldRepeater hold;
}

/// Pure-Dart per-zone pointer state machine. A pointer belongs to the zone it
/// landed in for its whole life. Feed it synthesized [down]/[move]/[up] events
/// and it emits typed [PointerResult]s through [onResult].
///
/// The only life-change amounts are ±1 and ±10: a quick tap is ±1, a stationary
/// hold repeats ±1 at an accelerating rate (the amount stays 1 forever), and a
/// horizontal swipe past the threshold is a single ±10.
///
/// Cross-zone independence is structural: each pointer is tracked on its own,
/// so simultaneous gestures in different zones never interfere.
class PointerRouter {
  PointerRouter({
    required this.onResult,
    List<Rect> zones = const [],
    List<int> zoneTurns = const [],
    this.dragThreshold = 24.0,
    this.swipeThreshold = 48.0,
    this.tapMaxHold = const Duration(milliseconds: 800),
    this.holdThreshold = const Duration(milliseconds: 300),
    Duration Function()? clock,
  }) : zones = List.of(zones),
       zoneTurns = List.of(zoneTurns),
       clock = clock ?? _monotonic;

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static Duration _monotonic() => _stopwatch.elapsed;

  /// Zone rectangles in the same coordinate space the caller feeds positions
  /// in. Mutable so the UI can update it on layout changes.
  List<Rect> zones;

  /// Quarter-turn rotation of each zone's seat, parallel to [zones]. A tap's
  /// sign and a swipe's direction are resolved in the zone's own upright frame
  /// using this value, so left/right is from the seated player's viewpoint
  /// rather than the screen's. A zone with no entry defaults to 0 (upright),
  /// preserving physical left/right.
  List<int> zoneTurns;

  final void Function(PointerResult result) onResult;

  /// Travel (logical px, any direction) beyond which a gesture stops qualifying
  /// as a stationary hold or a tap.
  final double dragThreshold;

  /// Seat-horizontal travel (logical px) beyond which a drag is recognized as a
  /// ±10 swipe.
  final double swipeThreshold;

  /// A still gesture held longer than this is treated as a hold, not a tap.
  final Duration tapMaxHold;

  /// A stationary finger held past this begins auto-repeating (see [tick]).
  final Duration holdThreshold;

  /// Injected monotonic time source. Tests supply a controllable clock; the UI
  /// uses the default real one and drives [tick] from a periodic timer.
  final Duration Function() clock;

  final Map<int, _ActivePointer> _active = {};

  /// Pointers whose tap was already emitted as part of another finger's
  /// multi-finger tap in the same zone; they must not emit again on up.
  final Set<int> _consumed = {};

  int? _zoneAt(Offset p) {
    for (var i = 0; i < zones.length; i++) {
      if (zones[i].contains(p)) return i;
    }
    return null;
  }

  /// Seat-horizontal component of a movement/offset [delta] within [zone]: the
  /// vector rotated by −q·90° (q being the zone's quarter-turns) into the seat's
  /// own upright frame, so the seated player's left reads negative and their
  /// right positive whatever direction the seat faces.
  double _horizontalAt(Offset delta, int zone) {
    final q = zone < zoneTurns.length ? zoneTurns[zone] & 3 : 0;
    return switch (q) {
      1 => delta.dy,
      2 => -delta.dx,
      3 => -delta.dy,
      _ => delta.dx,
    };
  }

  /// Sign of a tap at [p] within [zone], resolved in the zone's own upright
  /// frame: left-from-the-seat reads −1 and right-from-the-seat reads +1,
  /// whatever direction the seat faces.
  int _signAt(Offset p, int zone) =>
      _horizontalAt(p - zones[zone].center, zone) < 0 ? -1 : 1;

  void down(int pointerId, Offset position) {
    final zone = _zoneAt(position);
    if (zone == null) return; // outside every zone — ignore
    final hold = HoldRepeater(holdThreshold: holdThreshold)..start(clock());
    _active[pointerId] = _ActivePointer(
      zone: zone,
      downPos: position,
      hold: hold,
    );
  }

  void move(int pointerId, Offset position) {
    final p = _active[pointerId];
    if (p == null) return;
    p.lastPos = position;
    final delta = position - p.downPos;
    // Any travel past the slop makes this a drag, not a stationary hold, so it
    // stops qualifying for auto-repeat (and for a tap on release).
    if (delta.distance > dragThreshold) p.moved = true;
    // A swipe is recognized the moment seat-horizontal travel passes the
    // threshold: fire its ±10 once and lock the pointer so release adds no tap
    // and tick adds no hold-repeat. Vertical travel is deliberately ignored.
    if (!p.swiped) {
      final h = _horizontalAt(delta, p.zone);
      if (h.abs() > swipeThreshold) {
        p.swiped = true;
        p.moved = true;
        onResult(SwipeResult(p.zone, h < 0 ? -10 : 10));
      }
    }
  }

  /// Advances every held pointer's auto-repeat to the current [clock] time,
  /// emitting a ±1 [TapResult] for each accelerating repeat (see [HoldRepeater])
  /// that came due for any finger held stationary past [holdThreshold]. The UI
  /// calls this from a periodic timer/Ticker; tests call it after advancing the
  /// injected clock.
  void tick() {
    final now = clock();
    for (final p in _active.values.toList()) {
      if (p.moved) continue; // a drag/swipe in progress, not a stationary hold
      final repeats = p.hold.poll(now);
      if (repeats == 0) continue;
      p.repeated = true;
      // Same per-seat sign as a one-shot tap so a held finger repeats in the
      // direction the seated player expects. Each repeat is exactly ±1.
      final step = _signAt(p.downPos, p.zone);
      for (var i = 0; i < repeats; i++) {
        onResult(TapResult(p.zone, step));
      }
    }
  }

  /// Drops a pointer without emitting (pointer cancel).
  void cancel(int pointerId) {
    _active.remove(pointerId);
    _consumed.remove(pointerId);
  }

  void up(int pointerId, {required Duration heldFor}) {
    final p = _active.remove(pointerId);
    if (p == null) return;
    final wasConsumed = _consumed.remove(pointerId);

    // A swipe already emitted its ±10, a hold already repeated its ±1s, and a
    // drag that never became a swipe is not a tap. Any of these owns the
    // gesture, so release adds nothing.
    if (p.swiped || p.repeated || p.moved) return;

    if (wasConsumed) return;
    if (heldFor > tapMaxHold) return; // a hold that never repeated, not a tap

    // A quick, near-stationary release is a tap: exactly ±1, signed in the
    // zone's own upright frame (see [_signAt]) so the seated player's left is −
    // and right is +, regardless of how the seat is rotated.
    onResult(TapResult(p.zone, _signAt(p.downPos, p.zone)));

    // Fingers that landed together in this zone form a single ±1 tap (the count
    // no longer scales the amount), so the others must not each emit again.
    final peers = _active.entries
        .where((e) => e.value.zone == p.zone)
        .map((e) => e.key)
        .toList();
    _consumed.addAll(peers);
  }
}

/// Accelerating auto-repeat for a stationary held finger. Every repeat is a
/// single ±1 step — holding never changes the amount, only how fast the ±1s
/// arrive. Pure time accumulator with no timers of its own: [start] it when the
/// finger goes down, then [poll] it with the current time on each UI tick. It
/// returns how many ±1 repeats came due since the last poll (0 if none); the
/// caller applies the pointer's left/right sign.
///
/// The first repeat fires [holdThreshold] after the down; the gap before each
/// successive repeat then shrinks, so a sustained hold speeds up to a ±1 every
/// ~50ms and stays there.
class HoldRepeater {
  HoldRepeater({this.holdThreshold = const Duration(milliseconds: 300)});

  final Duration holdThreshold;

  /// Gap (ms) before each successive repeat; the final gap repeats forever.
  static const List<int> _gapsMs = [220, 180, 150, 120, 100, 80, 70, 60, 50];

  Duration? _nextDue;
  int _fired = 0;

  /// Arms the repeater; the first repeat comes due at [now] + [holdThreshold].
  void start(Duration now) {
    _nextDue = now + holdThreshold;
    _fired = 0;
  }

  /// Returns how many ±1 repeats are now due at [now], advancing the curve. A
  /// coarse tick spanning several due points is caught up in one call.
  int poll(Duration now) {
    if (_nextDue == null) return 0;
    var count = 0;
    while (now >= _nextDue!) {
      count++;
      final index = _fired < _gapsMs.length ? _fired : _gapsMs.length - 1;
      _nextDue = _nextDue! + Duration(milliseconds: _gapsMs[index]);
      _fired++;
    }
    return count;
  }
}

/// Fires [onComplete] once at least one pointer has been held simultaneously in
/// every one of [zoneCount] zones for [holdDuration]. [progress] is 0..1 (the
/// least-held qualifying zone drives it). Time comes from the injected [clock]
/// so it is fully testable.
class RitualDetector {
  RitualDetector({
    required this.zoneCount,
    required this.clock,
    this.holdDuration = const Duration(milliseconds: 1500),
    this.onComplete,
  });

  final int zoneCount;
  final Duration Function() clock;
  final Duration holdDuration;
  final void Function()? onComplete;

  final Map<int, ({int zone, Duration since})> _holds = {};
  bool _completed = false;

  void down(int pointerId, int zone) {
    _holds[pointerId] = (zone: zone, since: clock());
  }

  void up(int pointerId) {
    _holds.remove(pointerId);
    _completed = false;
  }

  double get progress {
    if (zoneCount == 0) return 0;
    final now = clock();
    final limit = holdDuration.inMicroseconds;
    var least = limit;
    for (var z = 0; z < zoneCount; z++) {
      int? bestHeld;
      for (final h in _holds.values) {
        if (h.zone != z) continue;
        final held = (now - h.since).inMicroseconds;
        if (bestHeld == null || held > bestHeld) bestHeld = held;
      }
      if (bestHeld == null) return 0; // this zone has no held pointer
      final clamped = bestHeld.clamp(0, limit);
      if (clamped < least) least = clamped;
    }
    return least / limit;
  }

  /// Recomputes progress and fires [onComplete] exactly once on completion.
  /// Returns whether the ritual is currently complete.
  bool poll() {
    final done = progress >= 1.0;
    if (done && !_completed) {
      _completed = true;
      onComplete?.call();
    }
    return done;
  }
}

/// Deterministically picks a winning pointer from [pointerIds] using [seed], so
/// the multi-touch first-player picker is testable.
int pickWinner(List<int> pointerIds, int seed) {
  if (pointerIds.isEmpty) {
    throw ArgumentError.value(pointerIds, 'pointerIds', 'must not be empty');
  }
  return pointerIds[Random(seed).nextInt(pointerIds.length)];
}
