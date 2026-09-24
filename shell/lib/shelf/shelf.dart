// The MaterDE shelf: the bottom bar (docs/04 §1 "Shelf", docs/05 "Shelf").
//
// The layer surface is taller than the visible bar: kShelfBarHeight of
// opaque bar at the bottom, plus a visually transparent zone above it where
// tooltips and menu panels render (a 48px surface has no room for either).
// While no menu is open only the bar itself accepts input, so the zone stays
// click-through for whatever is behind it — dynamic input region,
// docs/06 Option A + embedder/LAYER-SHELL-NOTES.md §14.
//
// Layout:  [Launcher] [pins…]      [running…]      [tray | clock]
//
// Menus are hand-rolled Positioned panels inside the transparent zone
// instead of showMenu(): a 248px-tall viewport gives popup routes no room
// to lay themselves out, while a plain panel needs no guessing — and we
// control the input-region switch and outside-click dismissal explicitly.

import 'package:flutter/material.dart';

import '../services/desktop_app.dart';
import '../wayland/layer_shell.dart';
import 'pinned_apps.dart';
import 'running_apps.dart';
import 'shelf_config.dart';
import 'shelf_item.dart';
import 'system_tray.dart';

/// Visible height of the shelf bar in logical px (docs/04: 48px).
const double kShelfBarHeight = 48;

/// Transparent zone above the bar, reserved for tooltips/menu panels.
const double kShelfMenuZoneHeight = 200;

/// Total layer-surface height — pass to flutter-client as `-h`.
const double kShelfSurfaceHeight = kShelfBarHeight + kShelfMenuZoneHeight;

class MaterdeShelf extends StatefulWidget {
  const MaterdeShelf({
    super.key,
    this.configPath,
    this.appsOverride,
    this.trayPoll,
    this.appLauncher,
  });

  /// Test seam: where the pin config is read/written (defaults to
  /// `~/.config/materde/shelf.json`).
  final String? configPath;

  /// Test seam: replaces the XDG `.desktop` scan.
  final List<DesktopApp>? appsOverride;

  /// Test seam: skip volume/network/battery process polling when null is
  /// not wanted; defaults to true, widget tests pass false.
  final bool? trayPoll;

  /// Test seam: replaces process spawning (Process.start misbehaves under
  /// the fake-async test clock); null = real [DesktopApp.launch].
  final Future<void> Function(DesktopApp app)? appLauncher;

  @override
  State<MaterdeShelf> createState() => _MaterdeShelfState();
}

class _MaterdeShelfState extends State<MaterdeShelf> {
  List<DesktopApp> _apps = const [];
  List<DesktopApp> _pinned = const [];

  /// Fed by WindowService's zcosmic_toplevel snapshot in Commit C.
  final List<DesktopApp> _running = const [];

  bool _launcherOpen = false;
  DesktopApp? _contextApp;
  Offset? _contextPos;

  bool get _menuOpen => _launcherOpen || _contextApp != null;

  void _launch(DesktopApp app) {
    final launcher = widget.appLauncher;
    if (launcher != null) {
      launcher(app);
    } else {
      app.launch();
    }
  }

  @override
  void initState() {
    super.initState();
    // Apply click-through geometry after the first frame, when MediaQuery
    // reports the real surface size.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncInputRegion();
      _load();
    });
  }

  Future<void> _load() async {
    final apps = widget.appsOverride ?? DesktopApp.discover();
    var config = ShelfConfig.load(path: widget.configPath);
    if (!config.existed) {
      // First run: seed sensible pins and persist them right away.
      config = ShelfConfig.initial(
        suggestDefaultPins(apps).map((a) => a.id).toList(),
        path: widget.configPath,
      );
      await config.save();
    }
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _pinned = [
        for (final id in config.pinned)
          ...apps.where((a) => a.id == id),
      ];
    });
  }

  Set<String> get _runningIds => _running.map((a) => a.id).toSet();

  /// Pinned running apps show their indicator in place (ChromeOS style);
  /// only unpinned windows get their own slot in the running section.
  List<DesktopApp> get _runningUnpinned => [
        for (final app in _running)
          if (!_pinned.any((p) => p.id == app.id)) app,
      ];

  void _syncInputRegion() {
    if (!mounted) return;
    // While a menu is open the whole surface takes input (menu panels live
    // in the transparent zone; outside clicks must reach the barrier).
    if (_menuOpen) {
      LayerShell.setInputRegionFull();
      return;
    }
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

  void _openLauncher() {
    if (_apps.isEmpty) return;
    setState(() {
      _launcherOpen = true;
      _contextApp = null;
      _contextPos = null;
    });
    _syncInputRegion();
  }

  void _openContext(DesktopApp app, Offset position) {
    setState(() {
      _contextApp = app;
      _contextPos = position;
      _launcherOpen = false;
    });
    _syncInputRegion();
  }

  void _closeMenus() {
    if (!_menuOpen) return;
    setState(() {
      _launcherOpen = false;
      _contextApp = null;
      _contextPos = null;
    });
    _syncInputRegion();
  }

  Future<void> _togglePin(DesktopApp app) async {
    setState(() {
      _pinned = _pinned.any((p) => p.id == app.id)
          ? _pinned.where((p) => p.id != app.id).toList()
          : [..._pinned, app];
    });
    // initial() doubles as "fresh config to persist" (same default path).
    await ShelfConfig.initial(
      _pinned.map((a) => a.id).toList(),
      path: widget.configPath,
    ).save();
  }

  /// Launcher panel: every installed app, click = launch, the trailing pin
  /// icon toggles pinning without closing the panel.
  Widget _buildLauncherPanel(ColorScheme scheme) {
    return Positioned(
      left: 6,
      top: 6,
      right: 6,
      bottom: kShelfBarHeight + 6,
      child: Material(
        color: scheme.surfaceContainerHigh,
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: _apps.length,
          separatorBuilder: (_, _) => Padding(
            padding: const EdgeInsets.only(left: 52, right: 12),
            child:
                Container(height: 1, color: scheme.surfaceContainerHighest),
          ),
          itemBuilder: (context, index) {
            final app = _apps[index];
            final isPinned = _pinned.any((p) => p.id == app.id);
            return InkWell(
              onTap: () {
                _launch(app);
                _closeMenus();
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  children: [
                    appIcon(app, scheme, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(app.displayName,
                          overflow: TextOverflow.ellipsis),
                    ),
                    GestureDetector(
                      onTap: () => _togglePin(app),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          isPinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          size: 17,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Context menu for a pinned/running item (right-click, docs/04 §1).
  /// Window actions (close, activate all) arrive with Commit C.
  Widget _buildContextPanel(Size view, ColorScheme scheme) {
    final app = _contextApp!;
    final pos = _contextPos!;
    final isPinned = _pinned.any((p) => p.id == app.id);
    const width = 210.0;
    final left = _clamp(pos.dx, 0, view.width - width);
    final top = _clamp(pos.dy, 0, view.height - kShelfBarHeight - 44);
    return Positioned(
      left: left,
      top: top,
      width: width,
      child: Material(
        color: scheme.surfaceContainerHigh,
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            _togglePin(app);
            _closeMenus();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isPinned ? 'Unpin from shelf' : 'Pin to shelf',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static double _clamp(double v, double lo, double hi) {
    if (hi < lo) return lo;
    return v < lo ? lo : (v > hi ? hi : v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final view = MediaQuery.sizeOf(context);
    return Scaffold(
      // The menu/tooltip zone must show whatever is behind the surface.
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: ColoredBox(
              color: scheme.surfaceContainer,
              child: SizedBox(
                width: double.infinity,
                height: kShelfBarHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      ShelfItem(
                        icon:
                            Icon(Icons.apps, size: 28, color: scheme.onSurface),
                        tooltip: 'Launch apps',
                        onTap: _apps.isEmpty ? null : _openLauncher,
                      ),
                      const SizedBox(width: 2),
                      PinnedApps(
                        apps: _pinned,
                        runningIds: _runningIds,
                        onLaunch: _launch,
                        onContextMenu: _openContext,
                      ),
                      Expanded(
                        child: Center(
                          child: RunningApps(
                            apps: _runningUnpinned,
                            // Focus comes with Commit C; until then re-launch.
                            onActivate: _launch,
                            onContextMenu: _openContext,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SystemTray(poll: widget.trayPoll ?? true),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Dismiss layer: covers the bar and the transparent zone while a
          // menu is open, so any outside click closes it. Opaque behavior is
          // required — a fully transparent ColoredBox does not hit-test.
          if (_menuOpen)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeMenus,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
          if (_launcherOpen) _buildLauncherPanel(scheme),
          if (_contextApp != null) _buildContextPanel(view, scheme),
        ],
      ),
    );
  }
}
