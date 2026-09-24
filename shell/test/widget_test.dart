// Smoke tests for the MaterDE shell.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:materde_shell/app.dart';
import 'package:materde_shell/theme/scheme.dart';
import 'package:materde_shell/theme/materde_theme.dart';

void main() {
  testWidgets('app renders the phase 0 colored rectangle', (tester) async {
    await tester.pumpWidget(const MaterdeApp());

    expect(find.text('MaterDE'), findsOneWidget);
    expect(find.text('Seed color'), findsOneWidget);
  });

  test('colorSchemeFromSeed produces a full scheme for both brightnesses', () {
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final scheme = colorSchemeFromSeed(
        seed: const Color(0xFF6750A4),
        brightness: brightness,
      );

      expect(scheme.brightness, brightness);
      // The four roles ColorScheme requires, plus the ones the shelf uses.
      expect(scheme.primary, isNotNull);
      expect(scheme.onPrimary, isNotNull);
      expect(scheme.surface, isNotNull);
      expect(scheme.onSurface, isNotNull);
      expect(scheme.surfaceContainer, isNotNull);
      expect(scheme.outline, isNotNull);
    }
  });

  test('changing the seed changes the generated colors', () {
    final purple = colorSchemeFromSeed(
      seed: const Color(0xFF6750A4),
      brightness: Brightness.dark,
    );
    final teal = colorSchemeFromSeed(
      seed: const Color(0xFF006A6A),
      brightness: Brightness.dark,
    );

    expect(purple.primary, isNot(equals(teal.primary)));
    expect(purple.primaryContainer, isNot(equals(teal.primaryContainer)));
  });

  test('materdeTheme is Material 3 and honours the seed', () {
    final theme = materdeTheme(
      seed: const Color(0xFF006A6A),
      brightness: Brightness.dark,
    );

    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(
      theme.colorScheme.primary,
      equals(
        colorSchemeFromSeed(
          seed: const Color(0xFF006A6A),
          brightness: Brightness.dark,
        ).primary,
      ),
    );
  });
}
