// Tonal palette generation for the MaterDE theme engine.
//
// A Material You theme derives 13 tonal palettes from a single seed color.
// Each palette carries the same tone stops (0, 4, 6, 10, ... 100); a theme role
// simply names which tone it reads. See docs/05 for the role/tone tables.

import 'dart:ui';

import 'package:material_color_utilities/palettes/tonal_palette.dart';

import 'hct.dart';

export 'package:material_color_utilities/palettes/tonal_palette.dart'
    show TonalPalette;

/// Tone stops shared by every Material You palette.
///
/// Named by intent rather than number so call sites read as roles, not magic
/// values.
abstract final class Tone {
  /// Text drawn on top of a Tone 40 fill (light mode "on primary").
  static const double onDarkText = 100;

  /// Filled surfaces in light mode (light mode "primary").
  static const double lightFill = 40;

  /// Text drawn on top of a Tone 80 fill (dark mode "on primary").
  static const double darkText = 20;

  /// Filled surfaces in dark mode (dark mode "primary").
  static const double darkFill = 80;

  /// Container fills in dark mode.
  static const double darkContainer = 30;

  /// Container fills in light mode.
  static const double lightContainer = 90;

  /// Body text in dark mode.
  static const double darkOnSurface = 90;

  /// Body text in light mode.
  static const double lightOnSurface = 10;

  /// Backgrounds and surfaces in dark mode.
  static const double darkSurface = 6;

  /// Backgrounds and surfaces in light mode.
  static const double lightSurface = 98;
}

/// Builds a tonal palette from a seed [Color].
TonalPalette tonalPaletteFromSeed(Color seed, {double chromaOffset = 0}) {
  final hct = hctFromColor(seed);
  return TonalPalette.of(hct.hue, (hct.chroma + chromaOffset).clamp(0, 150));
}

/// Reads a tone from [palette] as a Flutter [Color].
Color toneFromPalette(TonalPalette palette, double tone) =>
    Color(palette.get(tone.round()));
