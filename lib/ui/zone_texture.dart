import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Which zone edge the empty-zone color wash's radial highlight anchors to.
enum WashEdge { left, top, right, bottom }

/// The static per-seat texture parameters for an empty zone (no commander
/// art): which edge the color wash's radial highlight anchors to, and where
/// the shared grain tile is anchored so adjacent zones don't show visibly
/// identical grain.
@immutable
class ZoneTexture {
  const ZoneTexture({required this.edge, required this.grainAlignment});

  final WashEdge edge;
  final Alignment grainAlignment;
}

/// Derives [playerId]'s empty-zone texture from the game's [seed]. Pure and
/// deterministic: the same (seed, playerId) pair always returns the same
/// result, so a restored game looks exactly as it did before the app closed,
/// while a fresh NewGame's new random seed reshuffles every seat.
ZoneTexture zoneTextureFor(int seed, int playerId) {
  // Knuth's multiplicative hash constant folds playerId into a distinct
  // offset before seeding Random, so seats sharing a game's seed still
  // derive different values from each other.
  final rng = Random(seed ^ (playerId * 0x9E3779B9));
  final edge = WashEdge.values[rng.nextInt(WashEdge.values.length)];
  final grainAlignment = Alignment(
    rng.nextDouble() * 2 - 1,
    rng.nextDouble() * 2 - 1,
  );
  return ZoneTexture(edge: edge, grainAlignment: grainAlignment);
}

/// The color wash's alpha for [color]: high-luminance colors (yellow) drop to
/// 0.16 so they don't glow; everything else uses 0.20.
double washAlphaFor(Color color) =>
    color.computeLuminance() > 0.5 ? 0.16 : 0.20;

/// Side length (px) of the shared tiled grain image: small enough to
/// generate instantly and stay cheap in memory, fine enough to read as static
/// once tiled across a zone.
const int _grainTileSize = 64;

/// The grain's effective opacity over whatever sits behind it.
const double _grainOpacity = 0.07;

/// The process-wide tiled noise image backing every zone's film grain layer,
/// generated once and cached here so no zone regenerates its own and nothing
/// repaints per frame. Built from a fixed internal seed unrelated to any
/// game's seed — the grain pattern itself never changes, only each zone's
/// [ZoneTexture.grainAlignment] phase into it.
Future<ui.Image>? _grainImage;

/// Returns the shared grain image, generating it on first call.
Future<ui.Image> grainImage() => _grainImage ??= _buildGrainImage();

Future<ui.Image> _buildGrainImage() {
  final rng = Random(0xC0FFEE);
  final pixels = Uint8List(_grainTileSize * _grainTileSize * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = 255; // R
    pixels[i + 1] = 255; // G
    pixels[i + 2] = 255; // B
    // Alpha varies per pixel so the tile reads as static noise; scaled so its
    // average lands near the ~7% effective opacity the design calls for.
    pixels[i + 3] = (rng.nextDouble() * 2 * _grainOpacity * 255).round();
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    _grainTileSize,
    _grainTileSize,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}
