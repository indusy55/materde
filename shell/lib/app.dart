// Root widget for the MaterDE shell.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'shelf/shelf.dart';
import 'theme/materde_theme.dart';

/// Whether this process renders the shelf instead of the Phase 0 acceptance
/// page. Set `MATERDE_UI=shelf` when launching flutter-client as the layer
/// surface, with `-h` = `kShelfSurfaceHeight` (README §3). Without it the
/// acceptance page renders, which is what Phase 0 re-runs use.
final bool kShelfMode = Platform.environment['MATERDE_UI'] == 'shelf';

/// The MaterDE application root.
///
/// Owns the current seed color and brightness so the whole app can be
/// re-themed at runtime.
class MaterdeApp extends StatefulWidget {
  const MaterdeApp({super.key, this.initialSeed});

  /// Seed color the app starts themed from. Defaults to Material 3's baseline
  /// purple when null.
  final Color? initialSeed;

  @override
  State<MaterdeApp> createState() => _MaterdeAppState();
}

class _MaterdeAppState extends State<MaterdeApp> {
  late Color _seed = widget.initialSeed ?? const Color(0xFF6750A4);
  Brightness _brightness = Brightness.dark;

  /// Re-themes the app from a new seed color.
  void _setSeed(Color seed) {
    setState(() => _seed = seed);
  }

  void _toggleBrightness() {
    setState(() {
      _brightness =
          _brightness == Brightness.dark ? Brightness.light : Brightness.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MaterDE',
      debugShowCheckedModeBanner: false,
      theme: materdeTheme(seed: _seed, brightness: Brightness.light),
      darkTheme: materdeTheme(seed: _seed, brightness: Brightness.dark),
      themeMode:
          _brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: kShelfMode
          ? const MaterdeShelf()
          : _HomeView(
              seed: _seed,
              onSeedChanged: _setSeed,
              onToggleBrightness: _toggleBrightness,
            ),
    );
  }
}

/// Phase 0 acceptance page: a colored rectangle plus seed/brightness controls.
///
/// Phase 0 verifies this two ways (docs/07): the rectangle renders as a
/// layer surface, and changing the seed updates every color role.
class _HomeView extends StatelessWidget {
  const _HomeView({
    required this.seed,
    required this.onSeedChanged,
    required this.onToggleBrightness,
  });

  final Color seed;
  final ValueChanged<Color> onSeedChanged;
  final VoidCallback onToggleBrightness;

  static const List<Color> _seeds = <Color>[
    Color(0xFF6750A4), // Baseline purple
    Color(0xFF006A6A), // Teal
    Color(0xFFB3261E), // Red
    Color(0xFF386A20), // Green
    Color(0xFF0061A4), // Blue
    Color(0xFF7D5260), // Rose
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                // The shelf is a 48px strip: the controls below are window-sized,
                // so in a short viewport fall back to the bare colored rectangle
                // that Phase 0 verifies against (docs/07).
                if (constraints.maxHeight < 220) {
                  return ColoredBox(color: scheme.primary);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The colored rectangle used for the layer surface acceptance test.
                    Expanded(
                      child: Container(
                        color: scheme.primary,
                        alignment: Alignment.center,
                        child: Text(
                          'MaterDE',
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                color: scheme.onPrimary,
                              ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Seed color',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final candidate in _seeds)
                                _SeedSwatch(
                                  color: candidate,
                                  selected:
                                      candidate.toARGB32() == seed.toARGB32(),
                                  onTap: () => onSeedChanged(candidate),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton.filledTonal(
                              onPressed: onToggleBrightness,
                              icon: Icon(
                                _brightnessIcon(scheme.brightness),
                              ),
                              tooltip: 'Toggle brightness',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _brightnessIcon(Brightness brightness) =>
      brightness == Brightness.dark ? Icons.dark_mode : Icons.light_mode;
}

class _SeedSwatch extends StatelessWidget {
  const _SeedSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? scheme.onSurface : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: 20, color: scheme.onSurface)
            : null,
      ),
    );
  }
}
