import 'dart:math';
import 'dart:ui';

/// Result emitted for a classified gesture. Zones are identified by integer id;
/// the caller maps zone -> player and result -> game event. This layer is
/// deliberately game-agnostic so it can be unit-tested with synthetic pointers.
sealed class PointerResult {
  const PointerResult(this.zoneId);

  final int zoneId;
}

/// A tap in [zoneId]. [magnitude] is signed: negative for a tap to the seated
/// player's left, positive to their right (resolved in the zone's own upright
/// frame, not the screen's). Its size encodes the multi-finger count (1 finger
/// = 1, 2 = 5, 3+ = 10). Hold auto-repeats reuse this result, carrying the
/// accelerating step as the (signed) magnitude.
class TapResult extends PointerResult {
  const TapResult(super.zoneId, this.magnitude);

  final int magnitude;

  @override
  String toString() => 'TapResult(zone: $zoneId, magnitude: $magnitude)';
}

/// A vertical drag in [zoneId]. [steps] is signed: positive when dragging up.
class ScrubResult extends PointerResult {
  const ScrubResult(super.zoneId, this.steps);

  final int steps;

  @override
  String toString() => 'ScrubResult(zone: $zoneId, steps: $steps)';
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

  /// True once the finger has travelled beyond the slop: it is a scrub, not a
  /// stationary hold, so it must not auto-repeat.
  bool moved = false;

  /// True once this pointer has emitted at least one hold repeat, so its up
  /// suppresses the one-shot tap (no double count).
  bool repeated = false;

  final HoldRepeater hold;
}

/// Pure-Dart per-zone pointer state machine. A pointer belongs to the zone it
/// landed in for its whole life. Feed it synthesized [down]/[move]/[up] events
/// and it emits typed [PointerResult]s through [onResult].
///
/// Cross-zone independence is structural: each pointer is tracked on its own,
/// so simultaneous gestures in different zones never interfere.
class PointerRouter {
  PointerRouter({
    required this.onResult,
    List<Rect> zones = const [],
    List<int> zoneTurns = const [],
    this.dragThreshold = 24.0,
    this.stepSize = 24.0,
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
  /// sign is resolved in the zone's own upright frame using this value, so
  /// left/right is from the seated player's viewpoint rather than the screen's.
  /// A zone with no entry defaults to 0 (upright), preserving physical
  /// left/right.
  List<int> zoneTurns;

  final void Function(PointerResult result) onResult;

  /// Vertical travel (logical px) beyond which a gesture is a scrub, not a tap.
  final double dragThreshold;

  /// Logical px of vertical travel per scrub step.
  final double stepSize;

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

  /// Sign of a tap at [p] within [zone], resolved in the zone's own upright
  /// frame: the point is rotated by −q·90° about the zone center (q being the
  /// zone's quarter-turns) so left-from-the-seat reads −1 and right-from-the-
  /// seat reads +1, whatever direction the seat faces.
  int _signAt(Offset p, int zone) {
    final q = zone < zoneTurns.length ? zoneTurns[zone] & 3 : 0;
    final c = zones[zone].center;
    final dx = p.dx - c.dx;
    final dy = p.dy - c.dy;
    final rx = switch (q) {
      1 => dy,
      2 => -dx,
      3 => -dy,
      _ => dx,
    };
    return rx < 0 ? -1 : 1;
  }

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
    // Any travel past the slop makes this a scrub gesture, not a stationary
    // hold, so it stops qualifying for auto-repeat.
    if ((position - p.downPos).distance > dragThreshold) p.moved = true;
  }

  /// Advances every held pointer's auto-repeat to the current [clock] time,
  /// emitting accelerating repeats (see [HoldRepeater]) for any finger held
  /// stationary past [holdThreshold]. The UI calls this from a periodic
  /// timer/Ticker; tests call it after advancing the injected clock.
  void tick() {
    final now = clock();
    for (final p in _active.values.toList()) {
      if (p.moved) continue; // a scrub in progress, not a stationary hold
      final step = p.hold.poll(now);
      if (step == 0) continue;
      p.repeated = true;
      // Same per-seat sign as a one-shot tap so a held finger repeats in the
      // direction the seated player expects.
      onResult(TapResult(p.zone, step * _signAt(p.downPos, p.zone)));
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

    // A stationary hold that already auto-repeated owns this gesture: no extra
    // one-shot tap (no double count) and no scrub on release.
    if (p.repeated) return;

    // Positive when the finger moved up the screen (screen y grows downward).
    final vertical = p.downPos.dy - p.lastPos.dy;
    if (vertical.abs() > dragThreshold) {
      final steps = (vertical / stepSize).round();
      if (steps != 0) onResult(ScrubResult(p.zone, steps));
      return;
    }

    if (wasConsumed) return;
    if (heldFor > tapMaxHold) return; // a hold, not a tap

    // Count fingers still down in the same zone (this one is already removed),
    // so a simultaneous multi-finger tap is measured at its peak.
    final peers = _active.entries
        .where((e) => e.value.zone == p.zone)
        .map((e) => e.key)
        .toList();
    final fingerCount = peers.length + 1;
    final magnitude = fingerCount >= 3 ? 10 : (fingerCount == 2 ? 5 : 1);
    // Sign in the zone's own upright frame (see [_signAt]) so the seated
    // player's left is − and right is +, regardless of how the seat is rotated.
    onResult(TapResult(p.zone, magnitude * _signAt(p.downPos, p.zone)));

    // The other fingers of this tap must not each emit again.
    _consumed.addAll(peers);
  }
}

/// Accelerating auto-repeat for a stationary held finger. Pure time
/// accumulator with no timers of its own: [start] it when the finger goes down,
/// then [poll] it with the current time on each UI tick. It returns the total
/// unsigned step magnitude that came due since the last poll (0 if none); the
/// caller applies the pointer's left/right sign.
///
/// Curve — each repeat consumes the next (step, gap-to-next) pair; the final
/// pair repeats forever. The first repeat fires [holdThreshold] after the down,
/// then steps grow and gaps shrink so a sustained hold reaches 10-per-step in
/// ~1.6s: 1@300ms, 1@300, 1@240, 2@180, 2@120, 5@90, 5@60, then 10@60…
class HoldRepeater {
  HoldRepeater({this.holdThreshold = const Duration(milliseconds: 300)});

  final Duration holdThreshold;

  static const List<(int step, int gapMs)> _curve = [
    (1, 300),
    (1, 300),
    (1, 240),
    (2, 180),
    (2, 120),
    (5, 90),
    (5, 60),
    (10, 60),
  ];

  Duration? _nextDue;
  int _fired = 0;

  /// Arms the repeater; the first repeat comes due at [now] + [holdThreshold].
  void start(Duration now) {
    _nextDue = now + holdThreshold;
    _fired = 0;
  }

  /// Returns the summed step magnitude of every repeat now due at [now],
  /// advancing the curve. A coarse tick spanning several due points is caught
  /// up in one call.
  int poll(Duration now) {
    if (_nextDue == null) return 0;
    var total = 0;
    while (now >= _nextDue!) {
      final index = _fired < _curve.length ? _fired : _curve.length - 1;
      final (step, gapMs) = _curve[index];
      total += step;
      _fired++;
      _nextDue = _nextDue! + Duration(milliseconds: gapMs);
    }
    return total;
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
