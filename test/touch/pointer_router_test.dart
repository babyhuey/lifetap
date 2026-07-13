import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/touch/pointer_router.dart';

// Two stacked zones: zone 0 on top (y 0..100), zone 1 below (y 100..200).
const _zone0 = Rect.fromLTWH(0, 0, 100, 100);
const _zone1 = Rect.fromLTWH(0, 100, 100, 100);
const _short = Duration(milliseconds: 100);

// Offsets by horizontal half within each zone (x < 50 = left, x > 50 = right).
const _zone0Left = Offset(20, 50);
const _zone0Right = Offset(80, 50);
const _zone1Right = Offset(80, 150);

void main() {
  group('PointerRouter taps', () {
    test('simultaneous taps in two zones both register, correct zones', () {
      final results = <PointerResult>[];
      final router = PointerRouter(
        zones: const [_zone0, _zone1],
        onResult: results.add,
      );

      // Pointer A goes down in zone 0, pointer B in zone 1, then both lift —
      // fully interleaved, as two players tapping at the same instant.
      router.down(1, _zone0Right);
      router.down(2, _zone1Right);
      router.up(1, heldFor: _short);
      router.up(2, heldFor: _short);

      expect(results, hasLength(2));
      expect(results.whereType<TapResult>().map((r) => r.zoneId).toSet(), {
        0,
        1,
      });
      expect(results.every((r) => r is TapResult), isTrue);
    });

    test('single-finger tap has magnitude 1', () {
      final results = <PointerResult>[];
      final router = PointerRouter(
        zones: const [_zone0, _zone1],
        onResult: results.add,
      );

      router.down(1, _zone0Right);
      router.up(1, heldFor: _short);

      expect(results, [isA<TapResult>()]);
      expect((results.single as TapResult).magnitude, 1);
    });

    test('two-finger simultaneous tap yields a single magnitude 5', () {
      final results = <PointerResult>[];
      final router = PointerRouter(
        zones: const [_zone0, _zone1],
        onResult: results.add,
      );

      router.down(1, _zone0Right);
      router.down(2, _zone0Right);
      router.up(1, heldFor: _short);
      router.up(2, heldFor: _short);

      expect(results, hasLength(1));
      expect((results.single as TapResult).magnitude, 5);
    });

    test('three-finger simultaneous tap yields a single magnitude 10', () {
      final results = <PointerResult>[];
      final router = PointerRouter(
        zones: const [_zone0, _zone1],
        onResult: results.add,
      );

      router.down(1, _zone0Right);
      router.down(2, _zone0Right);
      router.down(3, _zone0Right);
      router.up(1, heldFor: _short);
      router.up(2, heldFor: _short);
      router.up(3, heldFor: _short);

      expect(results, hasLength(1));
      expect((results.single as TapResult).magnitude, 10);
    });

    test('right-half tap is positive, left-half tap is negative', () {
      final results = <PointerResult>[];
      final router = PointerRouter(
        zones: const [_zone0, _zone1],
        onResult: results.add,
      );

      router.down(1, _zone0Right);
      router.up(1, heldFor: _short);
      router.down(2, _zone0Left);
      router.up(2, heldFor: _short);

      expect((results[0] as TapResult).magnitude, 1);
      expect((results[1] as TapResult).magnitude, -1);
    });
  });

  group('PointerRouter per-seat tap sign', () {
    // The same physical-left tap flips sign with the seat's facing: on an
    // upright (q0) seat the player's left is the screen's left, but a 180°
    // (q2) seat is upside-down, so the screen's left is that player's right.
    test('physical left is − at q0 but + at q2', () {
      final results = <PointerResult>[];
      final router = PointerRouter(
        zones: const [_zone0, _zone1],
        zoneTurns: const [0, 2],
        onResult: results.add,
      );

      // Physical-left column of each zone (x < center 50).
      router.down(1, const Offset(20, 50)); // zone 0, q0
      router.up(1, heldFor: _short);
      router.down(2, const Offset(20, 150)); // zone 1, q2
      router.up(2, heldFor: _short);

      expect((results[0] as TapResult).magnitude, -1, reason: 'q0 left is −');
      expect((results[1] as TapResult).magnitude, 1, reason: 'q2 left is +');
    });

    // Side-facing seats sign by vertical position: q1 faces right so the
    // player's left is the screen's top; q3 faces left so their left is the
    // screen's bottom.
    test('q1 signs by vertical: top is −, bottom is +', () {
      final results = <PointerResult>[];
      final router = PointerRouter(
        zones: const [_zone0],
        zoneTurns: const [1],
        onResult: results.add,
      );

      router.down(1, const Offset(50, 20)); // above center (y < 50)
      router.up(1, heldFor: _short);
      router.down(2, const Offset(50, 80)); // below center (y > 50)
      router.up(2, heldFor: _short);

      expect((results[0] as TapResult).magnitude, -1);
      expect((results[1] as TapResult).magnitude, 1);
    });

    test('q3 signs by vertical opposite to q1: top is +, bottom is −', () {
      final results = <PointerResult>[];
      final router = PointerRouter(
        zones: const [_zone0],
        zoneTurns: const [3],
        onResult: results.add,
      );

      router.down(1, const Offset(50, 20)); // above center
      router.up(1, heldFor: _short);
      router.down(2, const Offset(50, 80)); // below center
      router.up(2, heldFor: _short);

      expect((results[0] as TapResult).magnitude, 1);
      expect((results[1] as TapResult).magnitude, -1);
    });

    test('held finger repeats in the seat frame (q2 physical-left is +)', () {
      var now = Duration.zero;
      final results = <PointerResult>[];
      final router = PointerRouter(
        zones: const [_zone0],
        zoneTurns: const [2],
        clock: () => now,
        onResult: results.add,
      );

      router.down(1, const Offset(20, 50)); // physical left of a q2 seat
      now = const Duration(milliseconds: 300);
      router.tick();

      expect(results, isNotEmpty);
      expect(
        results.every((r) => (r as TapResult).magnitude > 0),
        isTrue,
        reason: 'physical-left on an upside-down seat is the player\'s right',
      );
    });
  });

  group('PointerRouter drag', () {
    test('a vertical drag yields a ScrubResult, not a tap', () {
      final results = <PointerResult>[];
      final router = PointerRouter(
        zones: const [_zone0, _zone1],
        onResult: results.add,
      );

      router.down(1, const Offset(50, 90));
      router.move(1, const Offset(50, 40));
      router.move(1, const Offset(50, 10)); // dragged up ~80px
      router.up(1, heldFor: const Duration(milliseconds: 300));

      expect(results, hasLength(1));
      expect(results.single, isA<ScrubResult>());
      final scrub = results.single as ScrubResult;
      expect(scrub.zoneId, 0);
      expect(scrub.steps, greaterThan(0), reason: 'dragging up increases');
    });
  });

  group('PointerRouter hold-to-accelerate', () {
    ({PointerRouter router, List<PointerResult> results}) makeRouter(
      Duration Function() clock,
    ) {
      final results = <PointerResult>[];
      final router = PointerRouter(
        zones: const [_zone0, _zone1],
        clock: clock,
        onResult: results.add,
      );
      return (router: router, results: results);
    }

    test('no repeat fires before the hold threshold', () {
      var now = Duration.zero;
      final (:router, :results) = makeRouter(() => now);

      router.down(1, _zone0Right);
      now = const Duration(milliseconds: 299);
      router.tick();

      expect(results, isEmpty);
    });

    test('held right pointer repeats positive, held left negative', () {
      var now = Duration.zero;

      final right = makeRouter(() => now);
      right.router.down(1, _zone0Right);
      now = const Duration(milliseconds: 300);
      right.router.tick();
      expect(right.results, isNotEmpty);
      expect(
        right.results.every((r) => (r as TapResult).magnitude > 0),
        isTrue,
      );

      now = Duration.zero;
      final left = makeRouter(() => now);
      left.router.down(1, _zone0Left);
      now = const Duration(milliseconds: 300);
      left.router.tick();
      expect(left.results, isNotEmpty);
      expect(left.results.every((r) => (r as TapResult).magnitude < 0), isTrue);
    });

    test(
      'held pointer accelerates: steps grow and cumulative change climbs',
      () {
        var now = Duration.zero;
        final (:router, :results) = makeRouter(() => now);

        router.down(1, _zone0Right);

        // Poll on a fine cadence, as the UI's periodic ticker does, for ~2s.
        final steps = <int>[];
        for (var ms = 20; ms <= 2000; ms += 20) {
          now = Duration(milliseconds: ms);
          final before = results.length;
          router.tick();
          for (var i = before; i < results.length; i++) {
            steps.add((results[i] as TapResult).magnitude);
          }
        }

        expect(steps.every((m) => m > 0), isTrue, reason: 'right half is +');
        expect(steps.first, 1, reason: 'first repeat is the smallest step');
        expect(steps.reduce(max), 10, reason: 'ramps up to the ±10 ceiling');
        expect(
          steps.last,
          greaterThan(steps.first),
          reason: 'steps get bigger the longer it holds',
        );
        final total = steps.fold<int>(0, (a, b) => a + b);
        expect(
          total,
          greaterThan(steps.first),
          reason: 'cumulative change grows',
        );
      },
    );

    test('up after repeats does not add an extra tap', () {
      var now = Duration.zero;
      final (:router, :results) = makeRouter(() => now);

      router.down(1, _zone0Right);
      now = const Duration(milliseconds: 500);
      router.tick();
      final afterHold = results.length;
      expect(afterHold, greaterThan(0));

      router.up(1, heldFor: const Duration(milliseconds: 500));
      expect(results, hasLength(afterHold), reason: 'no extra one-shot tap');
    });

    test(
      'a quick tap released before the threshold still yields a single ±1',
      () {
        var now = Duration.zero;
        final (:router, :results) = makeRouter(() => now);

        router.down(1, _zone0Right);
        router.up(1, heldFor: _short); // released, no tick in between

        expect(results, [isA<TapResult>()]);
        expect((results.single as TapResult).magnitude, 1);
      },
    );
  });

  group('RitualDetector', () {
    test('fires only when every active zone has a held pointer past 1.5s', () {
      var now = Duration.zero;
      var fired = false;
      final ritual = RitualDetector(
        zoneCount: 2,
        clock: () => now,
        onComplete: () => fired = true,
      );

      ritual.down(1, 0);
      ritual.down(2, 1);

      now = const Duration(milliseconds: 1499);
      expect(ritual.poll(), isFalse);
      expect(fired, isFalse);
      expect(ritual.progress, lessThan(1.0));

      now = const Duration(milliseconds: 1500);
      expect(ritual.poll(), isTrue);
      expect(fired, isTrue);
      expect(ritual.progress, 1.0);
    });

    test('does not fire if one zone is missing a held pointer', () {
      var now = Duration.zero;
      var fired = false;
      final ritual = RitualDetector(
        zoneCount: 2,
        clock: () => now,
        onComplete: () => fired = true,
      );

      ritual.down(1, 0); // only zone 0 held

      now = const Duration(seconds: 10);
      expect(ritual.poll(), isFalse);
      expect(fired, isFalse);
      expect(ritual.progress, 0.0);
    });

    test('lifting a finger before completion resets progress', () {
      var now = Duration.zero;
      final ritual = RitualDetector(zoneCount: 1, clock: () => now);

      ritual.down(1, 0);
      now = const Duration(milliseconds: 1000);
      expect(ritual.progress, closeTo(1000 / 1500, 1e-9));

      ritual.up(1);
      expect(ritual.progress, 0.0);
    });
  });

  group('pickWinner', () {
    test('is deterministic for a fixed seed and returns a member', () {
      final ids = [11, 22, 33, 44];
      final first = pickWinner(ids, 42);
      final second = pickWinner(ids, 42);

      expect(first, second);
      expect(ids, contains(first));
    });

    test('different seeds can select across the input over many draws', () {
      final ids = [1, 2, 3, 4, 5];
      final drawn = {
        for (var seed = 0; seed < 200; seed++) pickWinner(ids, seed),
      };
      expect(drawn, isNotEmpty);
      expect(drawn.every(ids.contains), isTrue);
    });

    test('throws on empty input', () {
      expect(() => pickWinner(const [], 1), throwsArgumentError);
    });
  });
}
