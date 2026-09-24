// One interactive shelf item (docs/04 §1: hover highlight, tooltip,
// optional running indicator, click + right-click).

import 'dart:io';

import 'package:flutter/material.dart';

import '../services/desktop_app.dart';
import 'shelf_config.dart';

/// Fixed square-ish hit area of an item inside the 48px bar.
const double kShelfItemSize = 44;
const double kShelfItemIconSize = 26;

class ShelfItem extends StatefulWidget {
  const ShelfItem({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.onSecondaryTapUp,
    this.showIndicator = false,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// Right-click hook; receives the global pointer position so the parent
  /// can anchor a context menu there.
  final void Function(Offset position)? onSecondaryTapUp;

  /// Small primary dot under the icon (app is running, docs/04).
  final bool showIndicator;

  @override
  State<ShelfItem> createState() => _ShelfItemState();
}

class _ShelfItemState extends State<ShelfItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // docs/04 says hover = surfaceVariant; that token was folded into the
    // Material-3 surface roles, so this is its successor color.
    final hoverColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: (details) =>
            widget.onSecondaryTapUp?.call(details.globalPosition),
        child: MouseRegion(
          cursor: widget.onTap != null
              ? SystemMouseCursors.click
              : MouseCursor.defer,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: kShelfItemSize,
            height: kShelfItemSize,
            decoration: BoxDecoration(
              color: _hovered ? hoverColor : Colors.transparent,
              borderRadius: BorderRadius.circular(kShelfItemRadius),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: kShelfItemIconSize + 2,
                  height: kShelfItemIconSize,
                  child: Center(child: widget.icon),
                ),
                SizedBox(
                  height: 6,
                  child: Center(
                    child: widget.showIndicator
                        ? Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Builds the icon for [app]: the themed image file when a PNG can be found,
/// otherwise a Material icon picked from id/name/category keywords
/// (docs/04: "Use app icon or fallback material icon").
///
/// Icon file probing results are cached for the process lifetime.
Widget appIcon(DesktopApp app, ColorScheme scheme, {double size = 24}) {
  final file = _resolveIconFile(app);
  if (file != null) {
    return Image.file(
      file,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => _fallbackIcon(app, scheme, size),
    );
  }
  return _fallbackIcon(app, scheme, size);
}

final Map<String, File?> _iconFileCache = {};

File? _resolveIconFile(DesktopApp app) {
  final icon = app.iconName;
  if (icon == null) return null;
  return _iconFileCache.putIfAbsent(icon, () {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = <String>[
      for (final base in <String>[
        '/usr/share/icons/hicolor',
        '$home/.local/share/icons/hicolor',
      ])
        for (final dim in <String>['128x128', '64x64', '48x48', '32x32'])
          '$base/$dim/apps/$icon.png',
      '/usr/share/pixmaps/$icon.png',
      '$home/.local/share/icons/$icon.png',
    ];
    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) return file;
    }
    // SVG variants are skipped: no SVG decoder without extra dependencies.
    return null;
  });
}

Icon _fallbackIcon(DesktopApp app, ColorScheme scheme, double size) {
  final haystack =
      '${app.id} ${app.displayName} ${app.categories.join(' ')}'.toLowerCase();
  const table = <List<String>, IconData>{
    [
      'firefox',
      'chromium',
      'chrome',
      'brave',
      'vivaldi',
      'webbrowser',
      'epiphany'
    ]: Icons.public,
    [
      'konsole',
      'terminal',
      'xterm',
      'alacritty',
      'kitty',
      'foot',
      'ghostty'
    ]: Icons.terminal,
    ['nautilus', 'dolphin', 'files', 'filemanager', 'nemo', 'thunar']:
        Icons.folder,
    ['thunderbird', 'mail', 'geary']: Icons.mail,
    ['spotify', 'rhythmbox', 'music', 'audacious', 'amarok']: Icons.music_note,
    ['vlc', 'mpv', 'videos', 'totem', 'kdenlive']: Icons.movie,
    ['gimp', 'inkscape', 'photos', 'image']: Icons.photo_camera,
    ['libreoffice', 'writer', 'word', 'calc', 'excel']: Icons.description,
    ['settings', 'control', 'tweak']: Icons.settings,
    ['steam', 'game', 'minecraft']: Icons.sports_esports,
    ['code', 'studio', 'kate', 'gedit', 'vim', 'editor']: Icons.code,
    ['calculator']: Icons.calculate,
    ['update', 'updater']: Icons.system_update,
    ['snapstore', 'software', 'store', 'appcenter']: Icons.storefront,
  };
  for (final entry in table.entries) {
    for (final keyword in entry.key) {
      if (haystack.contains(keyword)) {
        return Icon(entry.value, size: size, color: scheme.onSurfaceVariant);
      }
    }
  }
  return Icon(Icons.widgets, size: size, color: scheme.onSurfaceVariant);
}
