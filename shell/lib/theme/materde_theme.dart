// App theme configuration: seed color -> ThemeData.
//
// Wires the Material You scheme into Flutter's ThemeData. Kept deliberately
// thin so the shelf, launcher, and overview can be themed independently later
// (see docs/05 "Component Theming").

import 'package:flutter/material.dart';

import 'scheme.dart';

/// Builds the MaterDE [ThemeData] for a seed color.
///
/// Set [seed] to re-theme the whole app; the verification for this is simply
/// changing the seed and watching every color role update.
ThemeData materdeTheme({
  required Color seed,
  required Brightness brightness,
  double contrastLevel = 0.0,
  SchemeVariant variant = SchemeVariant.content,
}) {
  final colorScheme = colorSchemeFromSeed(
    seed: seed,
    brightness: brightness,
    contrastLevel: contrastLevel,
    variant: variant,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    brightness: brightness,
    // ChromeOS-style generous rounding, per docs/05 "Corner Radii".
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(100),
        ),
      ),
    ),
  );
}
