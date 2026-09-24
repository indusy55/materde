// MaterDE shell entry point.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterdeApp(initialSeed: _seedFromEnvironment()));
}

/// Reads the initial theme seed from `MATERDE_SEED`.
///
/// Accepts `#RRGGBB` or `0xAARRGGBB`. Wallpaper extraction replaces this later
/// (see `theme/wallpaper_color.dart`); until then it is the quickest way to
/// re-theme without rebuilding, and it is what the Phase 0 acceptance uses to
/// verify that changing the seed updates every color role.
Color? _seedFromEnvironment() {
  final raw = Platform.environment['MATERDE_SEED'];
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final hex = raw.startsWith('#') ? raw.substring(1) : raw;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) {
    return null;
  }
  return Color(hex.length <= 6 ? 0xFF000000 | value : value);
}
