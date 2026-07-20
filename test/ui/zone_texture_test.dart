import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/ui/zone_texture.dart';

void main() {
  group('zoneTextureFor', () {
    test('is deterministic for a fixed seed and player', () {
      final first = zoneTextureFor(42, 1);
      final second = zoneTextureFor(42, 1);

      expect(first.edge, second.edge);
      expect(first.grainAlignment, second.grainAlignment);
    });

    test('different seeds can select across every edge over many draws', () {
      final edges = {
        for (var seed = 0; seed < 200; seed++) zoneTextureFor(seed, 0).edge,
      };
      expect(
        edges.length,
        greaterThan(1),
        reason: 'a constant edge would only ever pick one value',
      );
    });

    test(
      'different players under the same seed can derive different edges',
      () {
        final edges = {
          for (var playerId = 0; playerId < 200; playerId++)
            zoneTextureFor(7, playerId).edge,
        };
        expect(
          edges.length,
          greaterThan(1),
          reason: 'players sharing a seed should still fan out across edges',
        );
      },
    );

    test('seed 0 (legacy restored games) derives a valid texture', () {
      final texture = zoneTextureFor(0, 0);
      expect(WashEdge.values, contains(texture.edge));
      expect(texture.grainAlignment.x, inInclusiveRange(-1.0, 1.0));
      expect(texture.grainAlignment.y, inInclusiveRange(-1.0, 1.0));
    });
  });

  group('washAlphaFor', () {
    test('drops to 0.16 for a high-luminance color (yellow)', () {
      expect(washAlphaFor(const Color(0xFFFDD835)), 0.16);
    });

    test('stays at 0.20 for a low-luminance color (red)', () {
      expect(washAlphaFor(const Color(0xFFE53935)), 0.20);
    });
  });
}
