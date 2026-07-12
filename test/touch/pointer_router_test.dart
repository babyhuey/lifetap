import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/touch/pointer_router.dart';

// Two stacked zones: zone 0 on top (y 0..100), zone 1 below (y 100..200).
const _zone0 = Rect.fromLTWH(0, 0, 100, 100);
const _zone1 = Rect.fromLTWH(0, 100, 100, 100);
const _short = Duration(milliseconds: 100);

// Offsets by half within each zone.
const _zone0Top = Offset(50, 20);
const _zone0Bottom = Offset(50, 80);
const _zone1Top = Offset(50, 120);

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
      router.down(1, _zone0Top);
      router.down(2, _zone1Top);
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

      router.down(1, _zone0Top);
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

      router.down(1, _zone0Top);
      router.down(2, _zone0Top);
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

      router.down(1, _zone0Top);
      router.down(2, _zone0Top);
      router.down(3, _zone0Top);
      router.up(1, heldFor: _short);
      router.up(2, heldFor: _short);
      router.up(3, heldFor: _short);

      expect(results, hasLength(1));
      expect((results.single as TapResult).magnitude, 10);
    });

    test('top-half tap is positive, bottom-half tap is negative', () {
      final results = <PointerResult>[];
      final router = PointerRouter(
        zones: const [_zone0, _zone1],
        onResult: results.add,
      );

      router.down(1, _zone0Top);
      router.up(1, heldFor: _short);
      router.down(2, _zone0Bottom);
      router.up(2, heldFor: _short);

      expect((results[0] as TapResult).magnitude, 1);
      expect((results[1] as TapResult).magnitude, -1);
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
