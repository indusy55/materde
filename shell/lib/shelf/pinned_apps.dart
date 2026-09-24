// Pinned apps section of the shelf (docs/04 §1).

import 'package:flutter/material.dart';

import '../services/desktop_app.dart';
import 'shelf_item.dart';

/// Pinned applications, always visible, click = launch, right-click = menu.
class PinnedApps extends StatelessWidget {
  const PinnedApps({
    super.key,
    required this.apps,
    required this.runningIds,
    required this.onLaunch,
    required this.onContextMenu,
  });

  final List<DesktopApp> apps;

  /// Ids of pinned apps that currently have a window (for the indicator).
  final Set<String> runningIds;

  final void Function(DesktopApp app) onLaunch;

  /// Right-click hook; the shelf shows the pin/unpin context menu anchored
  /// at [position].
  final void Function(DesktopApp app, Offset position) onContextMenu;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final app in apps) ...[
          ShelfItem(
            key: ValueKey('pin-${app.id}'),
            icon: appIcon(app, Theme.of(context).colorScheme),
            tooltip: app.displayName,
            showIndicator: runningIds.contains(app.id),
            onTap: () => onLaunch(app),
            onSecondaryTapUp: (pos) => onContextMenu(app, pos),
          ),
        ],
      ],
    );
  }
}

/// First-run default pins: a terminal, a browser, a file manager and a
/// music player if the system has them (docs/04: pinned apps are always
/// visible — an empty shelf on first boot would be a poor default).
///
/// At most four entries; order is the order of [wanted].
List<DesktopApp> suggestDefaultPins(List<DesktopApp> apps) {
  const wanted = <String>[
    'WebBrowser',
    'TerminalEmulator',
    'FileManager',
    'AudioVideo',
  ];
  final picks = <DesktopApp>[];
  for (final category in wanted) {
    DesktopApp? found;
    for (final app in apps) {
      if (app.categories.contains(category)) {
        found = app;
        break;
      }
    }
    final match = found;
    if (match == null) continue;
    if (!picks.any((p) => p.id == match.id)) {
      picks.add(match);
    }
    if (picks.length >= 4) break;
  }
  return picks;
}
