// Theme scheme: seed color -> Flutter ColorScheme (dark and light).
//
// This is the heart of the MaterDE theme engine. We hand `material_color_utilities`
// a seed color and get back every Material You color role, then map those roles
// onto Flutter's ColorScheme. See docs/05 for the role/tone tables.

import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'hct.dart';

/// Which Material You dynamic color variant to generate.
enum SchemeVariant {
  /// Source color lands in the primary container. Best color fidelity to the
  /// seed, and the default for MaterDE.
  content,

  /// The classic Material You default: pastel, low-chroma palettes.
  tonalSpot,

  /// High-chroma, maximum vibrancy.
  vibrant,

  /// Medium chroma with a rotated primary hue for variety.
  expressive,
}

/// Builds a Material You [ColorScheme] from a single [seed] color.
///
/// [brightness] selects dark or light mode, and [contrastLevel] picks the
/// contrast variant (-1.0, 0.0, +1.0).
ColorScheme colorSchemeFromSeed({
  required Color seed,
  required Brightness brightness,
  double contrastLevel = 0.0,
  SchemeVariant variant = SchemeVariant.content,
}) {
  final DynamicScheme scheme = switch (variant) {
    SchemeVariant.content =>
      SchemeContent(
        sourceColorHct: hctFromColor(seed),
        isDark: brightness == Brightness.dark,
        contrastLevel: contrastLevel,
      ),
    SchemeVariant.tonalSpot =>
      SchemeTonalSpot(
        sourceColorHct: hctFromColor(seed),
        isDark: brightness == Brightness.dark,
        contrastLevel: contrastLevel,
      ),
    SchemeVariant.vibrant =>
      SchemeVibrant(
        sourceColorHct: hctFromColor(seed),
        isDark: brightness == Brightness.dark,
        contrastLevel: contrastLevel,
      ),
    SchemeVariant.expressive =>
      SchemeExpressive(
        sourceColorHct: hctFromColor(seed),
        isDark: brightness == Brightness.dark,
        contrastLevel: contrastLevel,
      ),
  };

  return ColorScheme(
    brightness: brightness,
    // Filled surfaces.
    primary: colorFromInt(scheme.primary),
    onPrimary: colorFromInt(scheme.onPrimary),
    primaryContainer: colorFromInt(scheme.primaryContainer),
    onPrimaryContainer: colorFromInt(scheme.onPrimaryContainer),
    primaryFixed: colorFromInt(scheme.primaryFixed),
    primaryFixedDim: colorFromInt(scheme.primaryFixedDim),
    onPrimaryFixed: colorFromInt(scheme.onPrimaryFixed),
    onPrimaryFixedVariant: colorFromInt(scheme.onPrimaryFixedVariant),
    secondary: colorFromInt(scheme.secondary),
    onSecondary: colorFromInt(scheme.onSecondary),
    secondaryContainer: colorFromInt(scheme.secondaryContainer),
    onSecondaryContainer: colorFromInt(scheme.onSecondaryContainer),
    secondaryFixed: colorFromInt(scheme.secondaryFixed),
    secondaryFixedDim: colorFromInt(scheme.secondaryFixedDim),
    onSecondaryFixed: colorFromInt(scheme.onSecondaryFixed),
    onSecondaryFixedVariant: colorFromInt(scheme.onSecondaryFixedVariant),
    tertiary: colorFromInt(scheme.tertiary),
    onTertiary: colorFromInt(scheme.onTertiary),
    tertiaryContainer: colorFromInt(scheme.tertiaryContainer),
    onTertiaryContainer: colorFromInt(scheme.onTertiaryContainer),
    tertiaryFixed: colorFromInt(scheme.tertiaryFixed),
    tertiaryFixedDim: colorFromInt(scheme.tertiaryFixedDim),
    onTertiaryFixed: colorFromInt(scheme.onTertiaryFixed),
    onTertiaryFixedVariant: colorFromInt(scheme.onTertiaryFixedVariant),
    error: colorFromInt(scheme.error),
    onError: colorFromInt(scheme.onError),
    errorContainer: colorFromInt(scheme.errorContainer),
    onErrorContainer: colorFromInt(scheme.onErrorContainer),
    // Surfaces.
    surface: colorFromInt(scheme.surface),
    onSurface: colorFromInt(scheme.onSurface),
    surfaceDim: colorFromInt(scheme.surfaceDim),
    surfaceBright: colorFromInt(scheme.surfaceBright),
    surfaceContainerLowest: colorFromInt(scheme.surfaceContainerLowest),
    surfaceContainerLow: colorFromInt(scheme.surfaceContainerLow),
    surfaceContainer: colorFromInt(scheme.surfaceContainer),
    surfaceContainerHigh: colorFromInt(scheme.surfaceContainerHigh),
    surfaceContainerHighest: colorFromInt(scheme.surfaceContainerHighest),
    onSurfaceVariant: colorFromInt(scheme.onSurfaceVariant),
    outline: colorFromInt(scheme.outline),
    outlineVariant: colorFromInt(scheme.outlineVariant),
    shadow: colorFromInt(scheme.shadow),
    scrim: colorFromInt(scheme.scrim),
    inverseSurface: colorFromInt(scheme.inverseSurface),
    onInverseSurface: colorFromInt(scheme.inverseOnSurface),
    inversePrimary: colorFromInt(scheme.inversePrimary),
    surfaceTint: colorFromInt(scheme.surfaceTint),
  );
}

/// Wraps an ARGB int from material_color_utilities as a Flutter [Color].
Color colorFromInt(int argb) => Color(argb);
