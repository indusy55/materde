// HCT color space helpers for the MaterDE Material You theme engine.
//
// HCT (Hue, Chroma, Tone) is perceptually uniform: colors sharing a tone value
// appear equally light to human perception regardless of hue, which is what
// makes Material You's tonal ramps accessible. See docs/05 for the full spec.
//
// The heavy lifting lives in Google's `material_color_utilities` package; this
// file only adapts it to Flutter's `Color` type.

import 'dart:ui';

import 'package:material_color_utilities/hct/hct.dart';

export 'package:material_color_utilities/hct/hct.dart' show Hct;

/// Converts a Flutter [Color] into an [Hct].
Hct hctFromColor(Color color) => Hct.fromInt(color.toARGB32());

/// Converts an [Hct] back into a Flutter [Color].
Color colorFromHct(Hct hct) => Color(hct.toInt());

/// Returns [hct] shifted to [tone], keeping hue and chroma.
///
/// Tone is perceptual lightness (0 = black, 100 = white), so this is the safe
/// way to derive an "on" color from a container color.
Hct hctWithTone(Hct hct, double tone) =>
    Hct.from(hct.hue, hct.chroma, tone);

/// Returns [hct] with its hue rotated by [degrees].
Hct hctRotatedHue(Hct hct, double degrees) =>
    Hct.from((hct.hue + degrees) % 360, hct.chroma, hct.tone);
