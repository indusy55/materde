// Extracts a seed color from the user's wallpaper.
//
// The Material You pipeline is: downsample the wallpaper, quantize it into a
// small palette, score the candidates for vibrancy, and keep the winner as the
// theme seed. See docs/05 "Color Extraction from Wallpaper".
//
// Phase 0 ships the plumbing and a fallback seed; actual wallpaper decoding
// lands with the appearance settings.

import 'dart:ui';

import 'package:material_color_utilities/material_color_utilities.dart';

/// Fallback seed used before a wallpaper color is available.
const Color kFallbackSeed = Color(0xFF6750A4); // Material 3 baseline purple.

/// Picks the best theme seed from a quantized color palette.
///
/// [colorsToPopulation] maps each ARGB color to how often it appeared in the
/// wallpaper, as produced by `QuantizerCelebi`. Returns [kFallbackSeed] when
/// the palette is empty or unusable.
Color seedFromPalette(Map<int, int> colorsToPopulation) {
  if (colorsToPopulation.isEmpty) {
    return kFallbackSeed;
  }

  // `Score` prefers vibrant, saturated, non-grey candidates and rejects colors
  // too close to black or white to carry a theme.
  final ranked = Score.score(colorsToPopulation);
  if (ranked.isEmpty) {
    return kFallbackSeed;
  }
  return Color(ranked.first);
}

/// Resolves the current wallpaper path to a seed color.
///
/// TODO(phase-4): decode the wallpaper image, downsample to 116x116, then hand
/// the quantized palette to [seedFromPalette]. Needs an image decode backend.
Color seedFromWallpaper(String wallpaperPath) => kFallbackSeed;
