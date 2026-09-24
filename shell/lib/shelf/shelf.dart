// The MaterDE shelf: the bottom bar (docs/04 §1 "Shelf", docs/05 "Shelf").
//
// The layer surface is taller than the visible bar: kShelfBarHeight of
// opaque bar at the bottom, plus a visually transparent zone above it where
// tooltips and context menus render (a 48px surface has no room for either).
// While no menu is open only the bar itself accepts input, so the zone stays
// click-through for whatever is behind it — dynamic input region,
// docs/06 Option A + embedder/LAYER-SHELL-NOTES.md.

import 'package:flutter/material.dart';

import '../wayland/layer_shell.dart';

/// Visible height of the shelf bar in logical px (docs/04: 48px).
const double kShelfBarHeight = 48;

/// Transparent zone above the bar, reserved for tooltips/context menus.
const double kShelfMenuZoneHeight = 200;

/// Total layer-surface height — pass to flutter-client as `-h`.
const double kShelfSurfaceHeight = kShelfBarHeight + kShelfMenuZoneHeight;

/// The shelf widget: lays the bar out at the bottom of the (taller) surface
/// and keeps the surface's input region in sync with menu state.
class MaterdeShelf extends StatefulWidget {
  const MaterdeShelf({super.key});

  @override
  State<MaterdeShelf> createState() => _MaterdeShelfState();
}

class _MaterdeShelfState extends State<MaterdeShelf> {
  @override
  void initState() {
    super.initState();
    // Apply click-through geometry after the first frame, when MediaQuery
    // reports the real surface size.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncInputRegion());
  }

  void _syncInputRegion() {
    if (!mounted) return;
    // While no menu is open, only the bar takes input; the menu/tooltip zone
    // above stays click-through. Menus flip this via setInputRegionFull —
    // wired up together with the Phase 1 context menus.
    final view = MediaQuery.sizeOf(context);
    LayerShell.setInputRegion(
      Rect.fromLTWH(
        0,
        view.height - kShelfBarHeight,
        view.width,
        kShelfBarHeight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      // The menu/tooltip zone must show whatever is behind the surface.
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.bottomCenter,
        child: ColoredBox(
          color: scheme.surfaceContainer,
          child: SizedBox(
            width: double.infinity,
            height: kShelfBarHeight,
          ),
        ),
      ),
    );
  }
}
