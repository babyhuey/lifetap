import 'dart:math';
import 'dart:ui';

/// Result emitted for a classified gesture. Zones are identified by integer id;
/// the caller maps zone -> player and result -> game event. This layer is
/// deliberately game-agnostic so it can be unit-tested with synthetic pointers.
sealed class PointerResult {
  const PointerResult(this.zoneId);

  final int zoneId;
}

/// A tap in [zoneId]. [magnitude] is signed: positive for a top-half tap,
/// negative for a bottom-half tap. Its size encodes the multi-finger count
/// (1 finger = 1, 2 = 5, 3+ = 10).
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
  _ActivePointer({required this.zone, required this.downPos})
    : lastPos = downPos;

  final int zone;
  final Offset downPos;
  Offset lastPos;
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
    this.dragThreshold = 24.0,
    this.stepSize = 24.0,
    this.tapMaxHold = const Duration(milliseconds: 800),
  }) : zones = List.of(zones);

  /// Zone rectangles in the same coordinate space the caller feeds positions
  /// in. Mutable so the UI can update it on layout changes.
  List<Rect> zones;

  final void Function(PointerResult result) onResult;

  /// Vertical travel (logical px) beyond which a gesture is a scrub, not a tap.
  final double dragThreshold;

  /// Logical px of vertical travel per scrub step.
  final double stepSize;

  /// A still gesture held longer than this is treated as a hold, not a tap.
  final Duration tapMaxHold;

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

  void down(int pointerId, Offset position) {
    final zone = _zoneAt(position);
    if (zone == null) return; // outside every zone — ignore
    _active[pointerId] = _ActivePointer(zone: zone, downPos: position);
  }

  void move(int pointerId, Offset position) {
    _active[pointerId]?.lastPos = position;
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
    final topHalf = p.downPos.dy < zones[p.zone].center.dy;
    onResult(TapResult(p.zone, topHalf ? magnitude : -magnitude));

    // The other fingers of this tap must not each emit again.
    _consumed.addAll(peers);
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
