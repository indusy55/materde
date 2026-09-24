// Running apps section of the shelf (docs/04 §1: "Appear when app is open,
// disappear when closed", primary dot under the icon).
//
// The window list comes from WindowService's zcosmic_toplevel snapshot
// (docs/06, wired in Commit C); until then the shelf passes an empty list
// and this section renders nothing.

import 'package:flutter/material.dart';

import '../services/desktop_app.dart';
import 'shelf_item.dart';

class RunningApps extends StatelessWidget {
  const RunningApps({
    super.key,
    required this.apps,
    required this.onActivate,
    required this.onContextMenu,
  });

  /// Distinct apps with at least one open window, in stacking order.
  final List<DesktopApp> apps;

  /// Click = focus the app's window (Commit C; [] until then, so the
  /// shelf passes no-op launch as a stopgap — see MaterdeShelf).
  final void Function(DesktopApp app) onActivate;

  final void Function(DesktopApp app, Offset position) onContextMenu;

  @override
  Widget build(BuildContext context) {
    if (apps.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final app in apps)
          ShelfItem(
            key: ValueKey('run-${app.id}'),
            icon: appIcon(app, scheme),
            tooltip: app.displayName,
            showIndicator: true,
            onTap: () => onActivate(app),
            onSecondaryTapUp: (pos) => onContextMenu(app, pos),
          ),
    ],
    );
  }
}
